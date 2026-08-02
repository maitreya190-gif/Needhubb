import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_strings.dart';
import '../../providers/language_provider.dart';
import '../../services/personality_api.dart';
import '../../services/profiles_api.dart';
import '../../services/social_providers.dart';
import '../../services/translate_api.dart';
import '../../theme/tokens.dart';

/// A 10-question personality quiz that hands off to the Lyzr analyzer agent
/// and shows the user their personality profile at the end. The profile is
/// stored on the server so other users can see a compatibility % on Connect.
class PersonalityTestScreen extends ConsumerStatefulWidget {
  const PersonalityTestScreen({super.key});

  @override
  ConsumerState<PersonalityTestScreen> createState() =>
      _PersonalityTestScreenState();
}

class _PersonalityTestScreenState extends ConsumerState<PersonalityTestScreen> {
  static const _questions = <({String prompt, List<String> options})>[
    (
      prompt: 'You have a free Saturday. What sounds best?',
      options: [
        'Long walk somewhere new',
        'Deep-focus solo project',
        'Big group hangout',
        'Cozy day in with one close friend',
      ],
    ),
    (
      prompt: 'When you meet someone new, you usually…',
      options: [
        'Ask a lot of questions',
        'Listen more than you speak',
        'Crack a joke to break the ice',
        'Wait for them to open up first',
      ],
    ),
    (
      prompt: 'Which of these describes your workspace?',
      options: [
        'Everything has its place',
        'Organized chaos I can navigate',
        'A rotating pile of inspiration',
        'Wherever my laptop lands',
      ],
    ),
    (
      prompt: 'A friend cancels plans last-minute. Your first reaction?',
      options: [
        'Relief — I needed the reset',
        'Curiosity — hope they’re okay',
        'Slightly annoyed but flexible',
        'Text three other people to swap plans',
      ],
    ),
    (
      prompt: 'You’re happiest when…',
      options: [
        'Building something with your hands',
        'Learning a new idea',
        'Helping someone through something',
        'Being surrounded by good energy',
      ],
    ),
    (
      prompt: 'Which quote hits hardest?',
      options: [
        '"Depth over breadth."',
        '"Stay curious."',
        '"People are the point."',
        '"Ship, then polish."',
      ],
    ),
    (
      prompt: 'Under stress, you tend to…',
      options: [
        'Withdraw and recharge alone',
        'Talk it out with someone',
        'Distract yourself with a task',
        'Move your body — walk, workout, dance',
      ],
    ),
    (
      prompt: 'What draws you to a stranger at a meetup?',
      options: [
        'They said something unexpected',
        'They actually listened',
        'They felt warm and easy',
        'They shared a niche interest',
      ],
    ),
    (
      prompt: 'You’re most likely to try something new because…',
      options: [
        'Someone you trust recommended it',
        'You saw data that convinced you',
        'It scratches an itch you’ve had for months',
        'You’re bored of your usual thing',
      ],
    ),
    (
      prompt: 'Which compliment lands best?',
      options: [
        '"You’re the person I call when things get hard."',
        '"You make things happen."',
        '"You always see something no one else sees."',
        '"Being around you is easy."',
      ],
    ),
  ];

  // Indices into _questions[i].options — keeps English answers for API submission
  final List<int?> _answerIndices = List<int?>.filled(_questions.length, null);
  // Groq-translated display questions; falls back to _questions when English
  List<({String prompt, List<String> options})> _displayQuestions = _questions;
  bool _translatingQuestions = false;
  int _step = 0;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    uiLanguageNotifier.addListener(_onLangChange);
    _loadTranslations();
  }

  @override
  void dispose() {
    uiLanguageNotifier.removeListener(_onLangChange);
    super.dispose();
  }

  void _onLangChange() => _loadTranslations();

  Future<void> _loadTranslations() async {
    final lang = uiLanguageNotifier.value;
    if (lang == 'en') {
      if (mounted) setState(() => _displayQuestions = _questions);
      return;
    }
    if (mounted) setState(() => _translatingQuestions = true);
    // Flatten all strings: [q1prompt, q1opt1..q1opt4, q2prompt, ...]
    final flat = <String>[];
    for (final q in _questions) {
      flat.add(q.prompt);
      flat.addAll(q.options);
    }
    final translated = await translateBatch(flat, lang);
    final display = <({String prompt, List<String> options})>[];
    var idx = 0;
    for (final q in _questions) {
      final prompt = translated[idx++];
      final opts = [translated[idx++], translated[idx++], translated[idx++], translated[idx++]];
      display.add((prompt: prompt, options: opts));
    }
    if (mounted) setState(() { _displayQuestions = display; _translatingQuestions = false; });
  }

  Future<void> _submit() async {
    // Jump to the first unanswered question instead of just showing an error
    final firstMissing = _answerIndices.indexWhere((a) => a == null);
    if (firstMissing != -1) {
      setState(() {
        _step = firstMissing;
        _error = S.current.pleaseAnswerFirst(firstMissing + 1);
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    // Always submit original English answers regardless of display language
    final englishAnswers = List.generate(
      _questions.length,
      (i) => _questions[i].options[_answerIndices[i]!],
    );

    PersonalityProfile? profile;
    Object? failure;
    // Belt-and-suspenders: wrap the whole flow so even a widget/parse crash
    // during the profile refresh can't red-screen the app.
    try {
      final api = ref.read(personalityApiProvider);
      profile = await api.submit(englishAnswers);
      // Cache the profile on the app-wide notifier so downstream widgets
      // (Home CTA, feed match badge) pick it up on the next rebuild.
      myPersonalityNotifier.value = profile;
      // Best-effort profile refresh — swallowed so it can never cascade.
      try {
        final me = await ref.read(profilesApiProvider).me();
        myProfileNotifier.value = me;
      } catch (e) {
        debugPrint('[PersonalityTest] profile refresh warning: $e');
      }
    } catch (e, stack) {
      debugPrint('[PersonalityTest] submit failed: $e\n$stack');
      failure = e;
    }

    if (!mounted) return;

    if (failure != null || profile == null) {
      setState(() {
        _submitting = false;
        _error = failure != null
            ? _friendlyError(failure)
            : S.current.somethingWentWrongRetry;
      });
      return;
    }

    // Success — clear the loading flag BEFORE navigating away so the widget
    // never tries to rebuild after disposal (fixes `_owner != null` crash).
    setState(() => _submitting = false);
    final resolved = profile;
    // Guard the navigation itself — if the result screen throws on mount
    // we don't want to leave the user on a broken white screen.
    try {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PersonalityResultScreen(profile: resolved, isFromQuiz: true)),
      );
    } catch (navErr) {
      debugPrint('[PersonalityTest] result-screen navigation failed: $navErr');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved your personality! Check the You tab.')),
        );
        Navigator.of(context).maybePop();
      }
    }
  }

  /// Convert Dio / network errors into a clean message the user can act on.
  String _friendlyError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final code = data is Map ? data['code']?.toString() : null;
      final serverErr = data is Map ? data['error']?.toString() : null;

      if (status == 401 || code == 'AUTH_REQUIRED') {
        return S.current.sessionExpired;
      }
      if (code == 'ALREADY_TAKEN') {
        return S.current.alreadyTakenTest;
      }
      if (serverErr != null && serverErr.isNotEmpty) {
        return serverErr;
      }
      if (status == 400) {
        return S.current.answersInvalid;
      }
      if (status == 404) {
        return S.current.testServiceNotFound;
      }
      return S.current.networkErrorRetry(status?.toString() ?? 'no connection');
    }
    return S.current.couldNotAnalyzeAnswers;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;
    final q = _displayQuestions[_step];
    final isLast = _step == _questions.length - 1;
    final progress = (_step + 1) / _questions.length;

    if (_translatingQuestions) {
      return Scaffold(
        backgroundColor: t.paper,
        body: Center(
          child: CircularProgressIndicator(color: NeedHubTokens.clay),
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with progress
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Icon(Icons.close_rounded, color: t.ink),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: t.chip,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            NeedHubTokens.clay),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_step + 1}/${_questions.length}',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.personalityQuizTitle,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: NeedHubTokens.clay,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      q.prompt,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ...q.options.asMap().entries.map((entry) {
                      final j = entry.key;
                      final opt = entry.value;
                      final selected = _answerIndices[_step] == j;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onTap: () => setState(() => _answerIndices[_step] = j),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: selected
                                  ? NeedHubTokens.clay.withValues(alpha: 0.08)
                                  : t.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? NeedHubTokens.clay
                                    : t.rail,
                                width: selected ? 1.6 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: selected
                                      ? NeedHubTokens.clay
                                      : t.muted2,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    opt,
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      color: t.ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          color: Colors.red.shade400,
                        ),
                      ),
                    ],
                    // Big inline Next/Submit button INSIDE the scroll area.
                    // This is the primary CTA — always visible on every question
                    // regardless of device chrome, keyboard, or nav bar issues.
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _submitting
                            ? null
                            : () {
                                if (isLast) {
                                  _submit();
                                } else if (_answerIndices[_step] == null) {
                                  setState(() => _error = s.pickAnAnswer);
                                } else {
                                  setState(() {
                                    _error = null;
                                    _step++;
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NeedHubTokens.clay,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (isLast)
                                    const Icon(Icons.check_rounded,
                                        size: 20, color: Colors.white),
                                  if (isLast) const SizedBox(width: 8),
                                  Text(
                                    isLast ? s.submitTest : s.next,
                                    style: GoogleFonts.hankenGrotesk(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white),
                                  ),
                                  if (!isLast) const SizedBox(width: 8),
                                  if (!isLast)
                                    const Icon(Icons.arrow_forward_rounded,
                                        size: 18, color: Colors.white),
                                ],
                              ),
                      ),
                    ),
                    if (_step > 0) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () => setState(() => _step--),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: t.ink,
                            side: BorderSide(color: t.rail, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(s.back,
                              style: GoogleFonts.hankenGrotesk(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}

/// The result screen shown right after the quiz completes. Also used by
/// You screen tapping the "personality" card to re-view results.
class PersonalityResultScreen extends StatelessWidget {
  final PersonalityProfile profile;
  final bool isFromQuiz;
  const PersonalityResultScreen({
    super.key,
    required this.profile,
    this.isFromQuiz = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final traits = profile.traits;

    return PopScope(
      canPop: !isFromQuiz,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isFromQuiz) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      child: Scaffold(
        backgroundColor: t.paper,
        appBar: AppBar(
          backgroundColor: t.paper,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: t.ink),
            onPressed: () {
              if (isFromQuiz) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
          title: Text(
            S.current.yourPersonalityTitle,
            style: GoogleFonts.hankenGrotesk(
                fontSize: 16, fontWeight: FontWeight.w800, color: t.ink),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    NeedHubTokens.clay,
                    NeedHubTokens.clay.withValues(alpha: 0.72),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.current.youAre,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.nickname,
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile.summary,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 14.5,
                      color: Colors.white.withValues(alpha: 0.95),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: profile.vibeTags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tag,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              S.current.traitProfile,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: t.muted2,
              ),
            ),
            const SizedBox(height: 12),
            _TraitBar(label: S.current.traitOpenness, value: traits.openness, t: t),
            _TraitBar(label: S.current.traitConscientiousness, value: traits.conscientiousness, t: t),
            _TraitBar(label: S.current.traitExtraversion, value: traits.extraversion, t: t),
            _TraitBar(label: S.current.traitAgreeableness, value: traits.agreeableness, t: t),
            _TraitBar(label: S.current.traitEmotionalStability, value: traits.emotionalStability, t: t),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.chip,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: t.muted2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      S.current.yourProfileHelps,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 12.5, color: t.muted, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            if (isFromQuiz) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NeedHubTokens.clay,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    S.current.backToNeedHub,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TraitBar extends StatelessWidget {
  final String label;
  final int value;
  final NeedHubTokens t;
  const _TraitBar({required this.label, required this.value, required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: t.ink),
                ),
              ),
              Text(
                '$value',
                style: GoogleFonts.bricolageGrotesque(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: NeedHubTokens.clay),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: t.chip,
              valueColor: const AlwaysStoppedAnimation<Color>(NeedHubTokens.clay),
            ),
          ),
        ],
      ),
    );
  }
}
