import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/need.dart';
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

  Future<void> _refreshRankedFeed() async {
    try {
      final api = ref.read(needsApiProvider);
      final res = await api.feed(sort: 'smart', take: 60);
      feedNeedsNotifier.value = res.needs;
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

  // Decomposed needs from the API — each item matches the /needs/decompose response shape.
  List<Map<String, dynamic>> _subNeeds = [];
  Set<int> _selectedSubNeedIndexes = {};

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _budgetMinController.dispose();
    _budgetMaxController.dispose();
    super.dispose();
  }

  bool get _canPost =>
      _titleController.text.trim().length >= 5 &&
      _descController.text.trim().length >= 10;

  bool get _canDecompose =>
      _descController.text.trim().length >= 20 && !_decomposed;

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
          _error = e.response?.data?['error'] as String? ?? 'Could not reach the server.';
        }
      });
    } catch (_) {
      setState(() { _decomposing = false; _error = 'Something went wrong.'; });
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
        'deadline': null,
      }];
    }

    Need? postedNeed;

    try {
      final client = ref.read(apiClientProvider);
      final res = await client.post('/needs', {'needs': needsPayload});
      if (res != null && res['parent'] is Map<String, dynamic>) {
        final parent = res['parent'] as Map<String, dynamic>;
        postedNeed = Need(
          id: parent['id'] as String? ?? 'posted_${DateTime.now().millisecondsSinceEpoch}',
          posterId: parent['posterId'] as String? ?? ref.read(authProvider).userId ?? '',
          title: parent['title'] as String? ?? _titleController.text.trim(),
          description: parent['description'] as String? ?? _descController.text.trim(),
          category: (parent['needType'] as String? ?? (_category == 'earn' ? 'EARN' : 'CONNECT')) == 'EARN' ? 'earn' : 'connect',
          authorName: 'You',
          authorInitials: 'ME',
          location: 'Nearby',
          createdAt: DateTime.tryParse(parent['createdAt'] as String? ?? '') ?? DateTime.now(),
          budgetMin: (parent['budgetMin'] as num?)?.toInt(),
          budgetMax: (parent['budgetMax'] as num?)?.toInt(),
        );
      }
    } catch (_) {
      // Backend request failed or offline — fall back to optimistic local Need
    }

    // Fallback: If API did not return parent, create optimistic local Need
    postedNeed ??= Need(
      id: 'posted_${DateTime.now().millisecondsSinceEpoch}',
      posterId: ref.read(authProvider).userId ?? '',
      title: needsPayload.first['title'] as String? ?? _titleController.text.trim(),
      description: needsPayload.first['description'] as String? ?? _descController.text.trim(),
      category: _category,
      authorName: 'You',
      authorInitials: 'ME',
      location: 'Nearby',
      createdAt: DateTime.now(),
      budgetMin: int.tryParse(_budgetMinController.text.trim()),
      budgetMax: int.tryParse(_budgetMaxController.text.trim()),
    );

    // Optimistically prepend to local feed so the feed refreshes immediately
    mockNeeds.insert(0, postedNeed);
    feedNeedsNotifier.value = [
      postedNeed,
      ...feedNeedsNotifier.value.where((n) => n.id != postedNeed!.id),
    ];
    needsNotifier.value++;
    unawaited(_refreshRankedFeed());

    if (mounted) {
      setState(() => _posting = false);
      Navigator.of(context).pop(postedNeed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (_decomposed && _selectedSubNeedIndexes.isNotEmpty)
                ? 'Posted ${needsPayload.length} selected needs!'
                : 'Need posted successfully!',
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
                        'Profanity detected. Please revise your post.',
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
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onChanged;
  final VoidCallback onDecompose;
  final ValueChanged<int> onToggleSubNeed;
  final VoidCallback onSelectAllSubNeeds;
  final VoidCallback onSelectNoneSubNeeds;
  final VoidCallback onUseOriginalNeed;
  final VoidCallback onPost;

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
    required this.onCategoryChanged,
    required this.onChanged,
    required this.onDecompose,
    required this.onToggleSubNeed,
    required this.onSelectAllSubNeeds,
    required this.onSelectNoneSubNeeds,
    required this.onUseOriginalNeed,
    required this.onPost,
  });

  @override
  Widget build(BuildContext context) {
    String postButtonText() {
      if (!decomposed) return 'Post need';
      if (selectedSubNeedIndexes.isEmpty) return 'Post original need';
      if (selectedSubNeedIndexes.length == subNeeds.length) {
        return 'Post all needs (${subNeeds.length})';
      }
      return 'Post selected needs (${selectedSubNeedIndexes.length} of ${subNeeds.length})';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category selector
        Row(
          children: [
            _CatButton(
              label: 'Connect',
              icon: Icons.handshake_outlined,
              color: NeedHubTokens.forest,
              selected: category == 'connect',
              onTap: () => onCategoryChanged('connect'),
              t: t,
            ),
            const SizedBox(width: 8),
            _CatButton(
              label: 'Earn',
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
          label: 'TITLE',
          hint: category == 'earn'
              ? 'e.g., Need calculus tutor for 2 weeks'
              : 'e.g., Looking for hackathon teammate',
          onChanged: (_) => onChanged(),
          t: t,
        ),
        const SizedBox(height: 14),

        _Field(
          controller: descController,
          label: 'DETAILS',
          hint: 'Describe what you need in detail...',
          minLines: 3,
          maxLines: 5,
          onChanged: (_) => onChanged(),
          t: t,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              !canPost
                  ? 'Title (min 5) & details (min 10) required to post'
                  : 'Ready to post!',
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
                  label: 'MIN BUDGET (₹)',
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
                  label: 'MAX BUDGET (₹)',
                  hint: '2000',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onChanged(),
                  t: t,
                ),
              ),
            ],
          ),
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
                        ? 'Decomposing with AI...'
                        : 'Decompose with AI',
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
              'Add at least 20 characters of detail to decompose',
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
                      'AI decomposed into ${subNeeds.length} recommendations',
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
                        'Select All',
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
                        'Select None',
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
                        'Use Original Need',
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
    final label = isEarn ? 'Earn' : 'Connect';

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
    this.inputFormatters,
  });

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
