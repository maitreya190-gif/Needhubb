import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/personality_api.dart';
import '../../services/profiles_api.dart';
import '../../services/social_providers.dart';
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

  final List<String?> _answers = List<String?>.filled(_questions.length, null);
  int _step = 0;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Defense-in-depth: if this screen ever opens for a user who already
    // took the test, bounce them straight to their result screen. The
    // Home CTA already handles this, but this covers any deep-link or
    // stale navigation path.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final me = myProfileNotifier.value;
      final existing = me?.personalityProfile;
      if (existing != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PersonalityResultScreen(profile: existing),
          ),
        );
      }
    });
  }

  Future<void> _submit() async {
    // Jump to the first unanswered question instead of just showing an error
    final firstMissing = _answers.indexWhere((a) => a == null || a.isEmpty);
    if (firstMissing != -1) {
      setState(() {
        _step = firstMissing;
        _error = 'Please answer question ${firstMissing + 1} first.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    PersonalityProfile? profile;
    Object? failure;
    try {
      final api = ref.read(personalityApiProvider);
      profile = await api.submit(_answers.cast<String>());
      myPersonalityNotifier.value = profile;

      // Refresh my full profile so downstream screens pick it up.
      try {
        final me = await ref.read(profilesApiProvider).me();
        myProfileNotifier.value = me;
      } catch (_) {}
    } catch (e) {
      debugPrint('[PersonalityTest] submit failed: $e');
      failure = e;
    }

    if (!mounted) return;
    if (failure != null) {
      // Show the error and leave the user on the quiz to retry.
      setState(() {
        _submitting = false;
        _error = _friendlyError(failure!);
      });
      return;
    }
    // Success — clear the loading flag BEFORE navigating away so the widget
    // never tries to rebuild after disposal (fixes `_owner != null` crash).
    setState(() => _submitting = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PersonalityResultScreen(profile: profile!)),
    );
  }

  /// Convert Dio / network errors into a clean message the user can act on.
  String _friendlyError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final code = data is Map ? data['code']?.toString() : null;
      final serverErr = data is Map ? data['error']?.toString() : null;

      if (status == 401 || code == 'AUTH_REQUIRED') {
        return 'Your session expired. Log out and log in, then retry.';
      }
      if (code == 'ALREADY_TAKEN') {
        return "You've already taken the test — check your You tab.";
      }
      if (serverErr != null && serverErr.isNotEmpty) {
        return serverErr;
      }
      if (status == 400) {
        return 'Something in your answers was invalid.';
      }
      if (status == 404) {
        return 'Personality test service not found. Please restart the backend server.';
      }
      return 'Network error (${status ?? "no connection"}). Please check if the server is running.';
    }
    return 'Could not analyze your answers. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final q = _questions[_step];
    final isLast = _step == _questions.length - 1;
    final progress = (_step + 1) / _questions.length;

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
                      'PERSONALITY QUIZ · POWERED BY LYZR',
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
                    ...q.options.map((opt) {
                      final selected = _answers[_step] == opt;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onTap: () => setState(() => _answers[_step] = opt),
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
                    // Big inline submit button on the last question so it
                    // can never be hidden by device chrome or a broken
                    // bottom bar layout. Always tappable — _submit()
                    // handles missing answers itself.
                    if (isLast) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
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
                                    const Icon(Icons.check_rounded,
                                        size: 20, color: Colors.white),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Submit test',
                                      style: GoogleFonts.hankenGrotesk(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
            // Bottom nav
            Container(
              padding: EdgeInsets.fromLTRB(
                20, 12, 20, MediaQuery.of(context).padding.bottom + 14),
              decoration: BoxDecoration(
                color: t.paper,
                border: Border(top: BorderSide(color: t.rail, width: 1)),
              ),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _step--),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: t.ink,
                        side: BorderSide(color: t.rail),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                      ),
                      child: Text('Back',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  if (_step > 0) const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      // On the last step, always allow the tap — _submit()
                      // itself handles missing answers by jumping to the
                      // first unanswered question. This means users are
                      // never stuck if a state bug leaves the current answer
                      // stale. On intermediate steps we still require an
                      // answer to advance.
                      onPressed: _submitting
                          ? null
                          : (isLast || _answers[_step] != null)
                              ? () {
                                  if (isLast) {
                                    _submit();
                                  } else {
                                    setState(() => _step++);
                                  }
                                }
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NeedHubTokens.clay,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: t.chip,
                        disabledForegroundColor: t.muted,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  isLast ? 'Submit test' : 'Next',
                                  style: GoogleFonts.hankenGrotesk(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800),
                                ),
                                if (isLast) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.check_rounded, size: 18),
                                ],
                              ],
                            ),
                    ),
                  ),
                ],
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
  const PersonalityResultScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final traits = profile.traits;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        backgroundColor: t.paper,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Your Personality',
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
                  'YOU ARE',
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
            'TRAIT PROFILE',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: t.muted2,
            ),
          ),
          const SizedBox(height: 12),
          _TraitBar(label: 'Openness', value: traits.openness, t: t),
          _TraitBar(label: 'Conscientiousness', value: traits.conscientiousness, t: t),
          _TraitBar(label: 'Extraversion', value: traits.extraversion, t: t),
          _TraitBar(label: 'Agreeableness', value: traits.agreeableness, t: t),
          _TraitBar(label: 'Emotional Stability', value: traits.emotionalStability, t: t),
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
                    'Your profile helps us surface a compatibility % on Connect. '
                    'You can retake anytime from your You tab.',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 12.5, color: t.muted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
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
