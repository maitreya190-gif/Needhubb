import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../models/need.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../l10n/app_strings.dart';
import '../../services/api_client.dart';
import '../../services/needs_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';

class PostNeedSheet extends ConsumerStatefulWidget {
  const PostNeedSheet({super.key});

  @override
  ConsumerState<PostNeedSheet> createState() => _PostNeedSheetState();
}

class _PostNeedSheetState extends ConsumerState<PostNeedSheet> {
  String _category = 'connect';

  // STT
  final _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _liveWords = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
    uiLanguageNotifier.addListener(_onLangChange);
  }

  void _onLangChange() {
    if (mounted) setState(() {});
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) return;
    final locale = kLangLocaleIds[uiLanguageNotifier.value] ?? 'en_IN';
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(localeId: locale),
      onResult: (result) {
        if (!mounted) return;
        setState(() => _liveWords = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          final cur = _descController.text;
          _descController.text = cur.isEmpty
              ? result.recognizedWords
              : '$cur ${result.recognizedWords}';
          setState(() => _liveWords = '');
        }
      },
    );
    if (mounted) setState(() => _isListening = true);
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted) setState(() { _isListening = false; _liveWords = ''; });
  }

  Future<void> _refreshRankedFeed() async {
    try {
      final api = ref.read(needsApiProvider);
      final res = await api.feed(sort: 'smart', take: 60);
      // Merge: keep locally-posted "You" needs that may not appear server-side yet
      final Map<String, Need> map = {};
      for (final n in feedNeedsNotifier.value
          .where((n) => n.authorName == 'You' || n.authorInitials == 'ME')) {
        map[n.id] = n;
      }
      for (final n in res.needs) {
        map[n.id] = n;
      }
      feedNeedsNotifier.value = map.values.toList();
      feedRankerNotifier.value = res.ranker;
    } catch (_) {/* silent */}
  }

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _budgetMinController = TextEditingController();
  final _budgetMaxController = TextEditingController();

  bool _decomposing = false;
  bool _decomposed = false;
  bool _posting = false;
  String? _error;

  // Urgency Mode — off by default. Only applies to the manual single-need
  // path: decomposed sub-needs post as-is, without a per-need urgent toggle.
  bool _isUrgent = false;
  DateTime? _urgentDeadline;
  int _peopleNeeded = 1;

  // Decomposed needs from the API — each item matches the /needs/decompose response shape.
  List<Map<String, dynamic>> _subNeeds = [];
  Set<int> _selectedSubNeedIndexes = {};

  @override
  void dispose() {
    uiLanguageNotifier.removeListener(_onLangChange);
    _titleController.dispose();
    _descController.dispose();
    _budgetMinController.dispose();
    _budgetMaxController.dispose();
    super.dispose();
  }

  bool get _canPost =>
      _titleController.text.trim().length >= 5 &&
      _descController.text.trim().length >= 10 &&
      // Urgency Mode requires a deadline before it can be posted — the
      // toggle alone isn't enough (matches the API's own validation).
      (!_isUrgent || _decomposed || _urgentDeadline != null);

  bool get _canDecompose =>
      _descController.text.trim().length >= 20 && !_decomposed;

  Future<void> _pickUrgentDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _urgentDeadline ?? now.add(const Duration(hours: 3)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          _urgentDeadline ?? now.add(const Duration(hours: 3))),
    );
    if (time == null || !mounted) return;
    setState(() {
      _urgentDeadline =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _decompose() async {
    setState(() { _decomposing = true; _error = null; });
    try {
      final client = ref.read(apiClientProvider);
      final text = '${_titleController.text.trim()} ${_descController.text.trim()}';
      final res = await client.post('/needs/decompose', {'text': text});
      final needs = (res['needs'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _decomposed = true;
        _decomposing = false;
        _subNeeds = needs;
        _selectedSubNeedIndexes = Set.from(List.generate(needs.length, (i) => i));
      });
    } on DioException catch (e) {
      final code = e.response?.data?['code'] as String?;
      setState(() {
        _decomposing = false;
        if (code == 'MODERATION_BLOCKED') {
          _error = 'moderation';
        } else {
          _error = e.response?.data?['error'] as String? ?? S.current.couldNotReachServer;
        }
      });
    } catch (_) {
      setState(() { _decomposing = false; _error = S.current.somethingWentWrong; });
    }
  }

  void _toggleSubNeed(int index) {
    setState(() {
      if (_selectedSubNeedIndexes.contains(index)) {
        _selectedSubNeedIndexes.remove(index);
      } else {
        _selectedSubNeedIndexes.add(index);
      }
    });
  }

  void _selectAllSubNeeds() {
    setState(() {
      _selectedSubNeedIndexes = Set.from(List.generate(_subNeeds.length, (i) => i));
    });
  }

  void _selectNoneSubNeeds() {
    setState(() {
      _selectedSubNeedIndexes.clear();
    });
  }

  void _useOriginalNeed() {
    setState(() {
      _decomposed = false;
      _subNeeds.clear();
      _selectedSubNeedIndexes.clear();
    });
  }

  Future<void> _post() async {
    if (!_canPost) return;
    setState(() { _posting = true; _error = null; });

    // Build the needs list to post.
    List<Map<String, dynamic>> needsPayload;
    if (_decomposed && _selectedSubNeedIndexes.isNotEmpty) {
      final sortedIdx = _selectedSubNeedIndexes.toList()..sort();
      needsPayload = sortedIdx.map((i) => _subNeeds[i]).toList();
    } else {
      // Single original customer need
      final budgetMin = double.tryParse(_budgetMinController.text.trim());
      final budgetMax = double.tryParse(_budgetMaxController.text.trim());
      final isEarn = budgetMin != null || _category == 'earn';
      needsPayload = [{
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'needType': isEarn ? 'EARN' : 'CONNECT',
        'earnCategory': isEarn ? 'OTHER' : null,
        'connectCategory': isEarn ? null : 'OTHER',
        'budgetMin': budgetMin,
        'budgetMax': budgetMax,
        'deadline': _isUrgent ? _urgentDeadline!.toIso8601String() : null,
        'peopleNeeded': _peopleNeeded,
        if (_isUrgent) 'isUrgent': true,
      }];
    }

    final List<Need> postedNeeds = [];
    final myUserId = ref.read(authProvider).userId ?? '';

    Need makeNeed(Map<String, dynamic> n, String fallbackId) => Need(
      id: n['id'] as String? ?? fallbackId,
      posterId: n['posterId'] as String? ?? myUserId,
      title: n['title'] as String? ?? '',
      description: n['description'] as String? ?? '',
      category: (n['needType'] as String? ?? 'CONNECT') == 'EARN' ? 'earn' : 'connect',
      authorName: 'You',
      authorInitials: 'ME',
      location: 'Nearby',
      createdAt: DateTime.tryParse(n['createdAt'] as String? ?? '') ?? DateTime.now(),
      budgetMin: (n['budgetMin'] as num?)?.toInt(),
      budgetMax: (n['budgetMax'] as num?)?.toInt(),
      isUrgent: n['isUrgent'] as bool? ?? false,
      deadline: n['deadline'] != null
          ? DateTime.tryParse(n['deadline'] as String)
          : null,
      peopleNeeded: (n['peopleNeeded'] as num?)?.toInt() ?? _peopleNeeded,
    );

    try {
      final client = ref.read(apiClientProvider);
      final res = await client.post('/needs', {'needs': needsPayload});
      final ts = DateTime.now().millisecondsSinceEpoch;
      if (res['parent'] is Map<String, dynamic>) {
        postedNeeds.add(makeNeed(res['parent'] as Map<String, dynamic>, 'p_$ts'));
      }
      final subsRaw = res['subs'] as List? ?? [];
      for (int i = 0; i < subsRaw.length; i++) {
        if (subsRaw[i] is Map<String, dynamic>) {
          postedNeeds.add(makeNeed(subsRaw[i] as Map<String, dynamic>, 's_${ts}_$i'));
        }
      }
    } on DioException catch (e) {
      final code = e.response?.data?['code'] as String?;
      if (code == 'MODERATION_BLOCKED') {
        if (mounted) {
          setState(() { _posting = false; _error = 'moderation'; });
        }
        return;
      }
    } catch (_) {}

    // Fallback: if API returned nothing, build optimistic Need for every sub-need payload
    if (postedNeeds.isEmpty) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < needsPayload.length; i++) {
        final n = needsPayload[i];
        postedNeeds.add(Need(
          id: 'opt_${ts}_$i',
          posterId: myUserId,
          title: n['title'] as String? ?? _titleController.text.trim(),
          description: n['description'] as String? ?? _descController.text.trim(),
          category: _category,
          authorName: 'You',
          authorInitials: 'ME',
          location: 'Nearby',
          createdAt: DateTime.now(),
          budgetMin: int.tryParse(_budgetMinController.text.trim()),
          budgetMax: int.tryParse(_budgetMaxController.text.trim()),
          isUrgent: _isUrgent,
          deadline: _isUrgent ? _urgentDeadline : null,
          peopleNeeded: _peopleNeeded,
        ));
      }
    }

    // Prepend ALL posted needs to the feed immediately
    final postedIds = postedNeeds.map((n) => n.id).toSet();
    for (final n in postedNeeds) mockNeeds.insert(0, n);
    feedNeedsNotifier.value = [
      ...postedNeeds,
      ...feedNeedsNotifier.value.where((n) => !postedIds.contains(n.id)),
    ];
    needsNotifier.value += postedNeeds.length;
    unawaited(_refreshRankedFeed());

    if (mounted) {
      setState(() => _posting = false);
      Navigator.of(context).pop(postedNeeds.first);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (_decomposed && _selectedSubNeedIndexes.isNotEmpty)
                ? '${needsPayload.length} ${S.current.needsPostedSuccess}'
                : S.current.needPostedSuccess,
          ),
          backgroundColor: NeedHubTokens.forest,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 20),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: t.rail, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),

            // Moderation block banner
            if (_error == 'moderation') ...[
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.block_rounded, color: Colors.red.shade600, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        S.current.profanityDetected,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 13, color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  _error!,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 13, color: Colors.orange.shade800),
                ),
              ),
            ],            _NeedForm(
              t: t,
              category: _category,
              titleController: _titleController,
              descController: _descController,
              budgetMinController: _budgetMinController,
              budgetMaxController: _budgetMaxController,
              canDecompose: _canDecompose,
              decomposing: _decomposing,
              decomposed: _decomposed,
              posting: _posting,
              subNeeds: _subNeeds,
              selectedSubNeedIndexes: _selectedSubNeedIndexes,
              canPost: _canPost,
              isUrgent: _isUrgent,
              urgentDeadline: _urgentDeadline,
              peopleNeeded: _peopleNeeded,
              onPeopleNeededChanged: (v) => setState(() => _peopleNeeded = v),
              onToggleUrgent: (v) => setState(() {
                _isUrgent = v;
                if (!v) _urgentDeadline = null;
              }),
              onPickDeadline: _pickUrgentDeadline,
              onCategoryChanged: (v) => setState(() {
                _category = v;
                _decomposed = false;
                _subNeeds = [];
                _selectedSubNeedIndexes.clear();
                _error = null;
              }),
              onChanged: () => setState(() {}),
              onDecompose: _decompose,
              onToggleSubNeed: _toggleSubNeed,
              onSelectAllSubNeeds: _selectAllSubNeeds,
              onSelectNoneSubNeeds: _selectNoneSubNeeds,
              onUseOriginalNeed: _useOriginalNeed,
              onPost: _post,
              isListening: _isListening,
              speechAvailable: _speechAvailable,
              liveWords: _liveWords,
              onMicTap: _isListening ? _stopListening : _startListening,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Need form ─────────────────────────────────────────────────────────────────

class _NeedForm extends StatelessWidget {
  final NeedHubTokens t;
  final String category;
  final TextEditingController titleController;
  final TextEditingController descController;
  final TextEditingController budgetMinController;
  final TextEditingController budgetMaxController;
  final bool canDecompose;
  final bool decomposing;
  final bool decomposed;
  final bool posting;
  final List<Map<String, dynamic>> subNeeds;
  final Set<int> selectedSubNeedIndexes;
  final bool canPost;
  final bool isUrgent;
  final DateTime? urgentDeadline;
  final int peopleNeeded;
  final ValueChanged<int> onPeopleNeededChanged;
  final ValueChanged<bool> onToggleUrgent;
  final VoidCallback onPickDeadline;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onChanged;
  final VoidCallback onDecompose;
  final ValueChanged<int> onToggleSubNeed;
  final VoidCallback onSelectAllSubNeeds;
  final VoidCallback onSelectNoneSubNeeds;
  final VoidCallback onUseOriginalNeed;
  final VoidCallback onPost;
  final bool isListening;
  final bool speechAvailable;
  final String liveWords;
  final VoidCallback? onMicTap;

  const _NeedForm({
    required this.t,
    required this.category,
    required this.titleController,
    required this.descController,
    required this.budgetMinController,
    required this.budgetMaxController,
    required this.canDecompose,
    required this.decomposing,
    required this.decomposed,
    required this.posting,
    required this.subNeeds,
    required this.selectedSubNeedIndexes,
    required this.canPost,
    required this.isUrgent,
    required this.urgentDeadline,
    required this.peopleNeeded,
    required this.onPeopleNeededChanged,
    required this.onToggleUrgent,
    required this.onPickDeadline,
    required this.onCategoryChanged,
    required this.onChanged,
    required this.onDecompose,
    required this.onToggleSubNeed,
    required this.onSelectAllSubNeeds,
    required this.onSelectNoneSubNeeds,
    required this.onUseOriginalNeed,
    required this.onPost,
    this.isListening = false,
    this.speechAvailable = false,
    this.liveWords = '',
    this.onMicTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    String postButtonText() {
      if (!decomposed) return s.post;
      if (selectedSubNeedIndexes.isEmpty) return s.post;
      if (selectedSubNeedIndexes.length == subNeeds.length) {
        return '${s.post} (${subNeeds.length})';
      }
      return '${s.post} (${selectedSubNeedIndexes.length}/${subNeeds.length})';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category selector
        Row(
          children: [
            _CatButton(
              label: s.connect,
              icon: Icons.handshake_outlined,
              color: NeedHubTokens.forest,
              selected: category == 'connect',
              onTap: () => onCategoryChanged('connect'),
              t: t,
            ),
            const SizedBox(width: 8),
            _CatButton(
              label: s.earn,
              icon: Icons.currency_rupee_rounded,
              color: NeedHubTokens.ochre,
              selected: category == 'earn',
              onTap: () => onCategoryChanged('earn'),
              t: t,
            ),
          ],
        ),
        const SizedBox(height: 16),

        _Field(
          controller: titleController,
          label: s.title.toUpperCase(),
          hint: category == 'earn'
              ? s.earnTitleHint
              : s.connectTitleHint,
          onChanged: (_) => onChanged(),
          t: t,
        ),
        const SizedBox(height: 14),

        _Field(
          controller: descController,
          label: s.description.toUpperCase(),
          hint: s.describeNeedHint,
          minLines: 3,
          maxLines: 5,
          onChanged: (_) => onChanged(),
          t: t,
        ),
        const SizedBox(height: 8),
        _MicBar(
          speechAvailable: speechAvailable,
          isListening: isListening,
          liveWords: liveWords,
          onMicTap: onMicTap,
          t: t,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              !canPost
                  ? s.titleAndDetailsRequired
                  : s.readyToPost,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: !canPost ? Colors.orange.shade800 : NeedHubTokens.forest,
              ),
            ),
            Text(
              '${descController.text.trim().length} chars',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11.5,
                color: t.muted,
              ),
            ),
          ],
        ),

        // Budget fields (only shown for Earn category)
        if (category == 'earn') ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Field(
                  controller: budgetMinController,
                  label: '${s.minBudget} (₹)',
                  hint: '500',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onChanged(),
                  t: t,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Field(
                  controller: budgetMaxController,
                  label: '${s.maxBudget} (₹)',
                  hint: '2000',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onChanged(),
                  t: t,
                ),
              ),
            ],
          ),
        ],

        // People Needed counter — manual single-need path only
        if (!decomposed) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: t.paper,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.rail),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PEOPLE NEEDED',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: t.muted2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'How many people do you need?',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.rail),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 18),
                        onPressed: peopleNeeded > 1
                            ? () => onPeopleNeededChanged(peopleNeeded - 1)
                            : null,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '$peopleNeeded',
                          style: GoogleFonts.bricolageGrotesque(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: t.ink,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 18),
                        onPressed: peopleNeeded < 100
                            ? () => onPeopleNeededChanged(peopleNeeded + 1)
                            : null,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Urgency Mode — manual single-need path only. Hidden once decomposed
        // since sub-needs post as-is without a per-need urgent toggle.
        if (!decomposed) ...[
          const SizedBox(height: 14),
          InkWell(
            onTap: () => onToggleUrgent(!isUrgent),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isUrgent
                    ? Colors.red.withValues(alpha: 0.08)
                    : t.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUrgent
                      ? Colors.red.withValues(alpha: 0.35)
                      : t.rail,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded,
                      size: 18,
                      color: isUrgent ? Colors.red.shade600 : t.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.markAsUrgent,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isUrgent ? Colors.red.shade700 : t.ink,
                          ),
                        ),
                        Text(
                          s.urgentDesc,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 11,
                            color: t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isUrgent,
                    onChanged: onToggleUrgent,
                    activeTrackColor: Colors.red.shade400,
                  ),
                ],
              ),
            ),
          ),
          if (isUrgent) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: onPickDeadline,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: urgentDeadline == null
                        ? Colors.orange.shade300
                        : t.rail,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 17, color: t.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        urgentDeadline == null
                            ? s.setDeadline
                            : 'Due ${_formatDeadline(urgentDeadline!)}',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: urgentDeadline == null
                              ? Colors.orange.shade800
                              : t.ink,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: t.muted),
                  ],
                ),
              ),
            ),
          ],
        ],

        const SizedBox(height: 14),

        // AI decompose button
        if (!decomposed) ...[
          InkWell(
            onTap: canDecompose && !decomposing ? onDecompose : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: canDecompose
                    ? NeedHubTokens.clay.withValues(alpha: 0.10)
                    : t.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: canDecompose
                      ? NeedHubTokens.clay.withValues(alpha: 0.35)
                      : t.rail,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  decomposing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NeedHubTokens.clay,
                          ),
                        )
                      : Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: canDecompose ? NeedHubTokens.clay : t.muted,
                        ),
                  const SizedBox(width: 10),
                  Text(
                    decomposing
                        ? s.decomposingWithAi
                        : s.decomposeWithAi,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: canDecompose ? NeedHubTokens.clay : t.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!canDecompose) ...[
            const SizedBox(height: 4),
            Text(
              s.addMoreDetailToDecompose,
              style: GoogleFonts.hankenGrotesk(fontSize: 11, color: t.muted),
            ),
          ],
        ],

        // Decomposition result
        if (decomposed && subNeeds.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NeedHubTokens.clay.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: NeedHubTokens.clay.withValues(alpha: 0.20),
                  width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 15, color: NeedHubTokens.clay),
                    const SizedBox(width: 6),
                    Text(
                      '${s.aiDecomposedInto} ${subNeeds.length} ${s.recommendations}',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: NeedHubTokens.clay,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    GestureDetector(
                      onTap: onSelectAllSubNeeds,
                      child: Text(
                        s.selectAll,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: NeedHubTokens.forest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: onSelectNoneSubNeeds,
                      child: Text(
                        s.selectNone,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: t.muted,
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onUseOriginalNeed,
                      child: Text(
                        s.useOriginalNeed,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: NeedHubTokens.clay,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...List.generate(subNeeds.length, (index) {
                  final sn = subNeeds[index];
                  final isSelected = selectedSubNeedIndexes.contains(index);
                  return _ApiSubNeedCard(
                    sn: sn,
                    t: t,
                    isSelected: isSelected,
                    onTap: () => onToggleSubNeed(index),
                  );
                }),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: (canPost && !posting) ? onPost : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: decomposed ? NeedHubTokens.clay : t.surfaceDark,
              foregroundColor: Colors.white,
              disabledBackgroundColor: t.rail,
              disabledForegroundColor: t.muted,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              textStyle: GoogleFonts.bricolageGrotesque(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
            child: posting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(postButtonText()),
          ),
        ),
      ],
    );
  }
}

String _formatDeadline(DateTime d) {
  final now = DateTime.now();
  final sameDay =
      d.year == now.year && d.month == now.month && d.day == now.day;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final period = d.hour >= 12 ? 'PM' : 'AM';
  final time = '$h:${d.minute.toString().padLeft(2, '0')} $period';
  if (sameDay) return 'today, $time';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, $time';
}

// ── Sub-need card (from API response) ────────────────────────────────────────

class _ApiSubNeedCard extends StatelessWidget {
  final Map<String, dynamic> sn;
  final NeedHubTokens t;
  final bool isSelected;
  final VoidCallback onTap;

  const _ApiSubNeedCard({
    required this.sn,
    required this.t,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEarn = (sn['needType'] as String?) == 'EARN';
    final color = isEarn ? NeedHubTokens.ochre : NeedHubTokens.forest;
    final label = isEarn ? S.current.earn : S.current.connect;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? NeedHubTokens.clay.withValues(alpha: 0.08) : t.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? NeedHubTokens.clay : t.rail,
              width: isSelected ? 1.8 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isSelected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 20,
                color: isSelected ? NeedHubTokens.clay : t.muted,
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 11, fontWeight: FontWeight.w700, color: color),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sn['title'] as String? ?? '',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13, fontWeight: FontWeight.w600, color: t.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sn['description'] as String? ?? '',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 12, color: t.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _CatButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _CatButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : t.paper,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : t.rail, width: 1.5),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: selected ? color : t.muted),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? color : t.muted2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String>? onChanged;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final NeedHubTokens t;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.t,
    this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
  }) : inputFormatters = null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: t.muted2,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: t.paper,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: t.rail, width: 1.5),
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            minLines: minLines,
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: false,
            ),
          ),
        ),
      ],
    );
  }
}

class _MicBar extends StatelessWidget {
  final bool speechAvailable;
  final bool isListening;
  final String liveWords;
  final VoidCallback? onMicTap;
  final NeedHubTokens t;

  const _MicBar({
    required this.speechAvailable,
    required this.isListening,
    required this.liveWords,
    required this.onMicTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(uiLanguageNotifier.value);
    return GestureDetector(
      onTap: speechAvailable ? onMicTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isListening
              ? NeedHubTokens.clay.withValues(alpha: 0.08)
              : t.rail.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isListening
                ? NeedHubTokens.clay.withValues(alpha: 0.3)
                : t.rail,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            _PulsingMic(active: isListening),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isListening
                    ? (liveWords.isNotEmpty ? liveWords : s.listening)
                    : speechAvailable
                        ? s.tapToSpeak
                        : s.voiceNotAvailable,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 13.5,
                  color: isListening ? NeedHubTokens.clay : t.muted,
                  fontStyle: isListening && liveWords.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingMic extends StatefulWidget {
  final bool active;
  const _PulsingMic({required this.active});

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (widget.active) _anim.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingMic old) {
    super.didUpdateWidget(old);
    if (widget.active && !_anim.isAnimating) {
      _anim.repeat(reverse: true);
    } else if (!widget.active) {
      _anim.stop();
      _anim.value = 0;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Transform.scale(
        scale: widget.active ? 1.0 + 0.35 * _anim.value : 1.0,
        child: Icon(
          Icons.mic_rounded,
          size: 22,
          color: widget.active ? NeedHubTokens.clay : Colors.grey.shade400,
        ),
      ),
    );
  }
}
