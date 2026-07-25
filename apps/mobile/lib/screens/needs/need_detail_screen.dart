import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/need.dart';
import '../../services/api_client.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_empty_state.dart';
import '../../widgets/nh_report_sheet.dart';

// Static offers that always appear under every need (mock)
final _staticOffers = [
  _OfferData(
    initials: 'MK',
    name: 'Meera Krishnan',
    note: 'I can start this weekend!',
    amount: '₹600',
    tint: NeedHubTokens.forest,
  ),
  _OfferData(
    initials: 'AB',
    name: 'Arjun Bhat',
    note: 'Experienced, have portfolio ready.',
    amount: '₹500',
    tint: NeedHubTokens.ochre,
  ),
];

class _OfferData {
  final String initials;
  final String name;
  final String note;
  final String amount;
  final Color tint;
  const _OfferData({
    required this.initials,
    required this.name,
    required this.note,
    required this.amount,
    required this.tint,
  });
}

class NeedDetailScreen extends ConsumerStatefulWidget {
  final Need need;

  const NeedDetailScreen({super.key, required this.need});

  @override
  ConsumerState<NeedDetailScreen> createState() => _NeedDetailScreenState();
}

class _NeedDetailScreenState extends ConsumerState<NeedDetailScreen> {
  Need get need => widget.need;
  List<_OfferData> _realOffers = const [];
  bool _isPoster = false;

  @override
  void initState() {
    super.initState();
    offersNotifier.addListener(_rebuild);
    Future.microtask(_hydrateOffers);
  }

  Future<void> _hydrateOffers() async {
    try {
      final api = ref.read(apiClientProvider);
      // GET /needs/:id/responses — poster-only; a 403 tells us we're not the poster.
      final rows = await api.getList('/needs/${need.id}/responses');
      if (!mounted) return;
      setState(() {
        _isPoster = true;
        _realOffers = rows.map((j) {
          final responder =
              (j['responder'] as Map<String, dynamic>?) ?? const {};
          final name = responder['displayName'] as String? ?? 'Someone';
          final initials = _initialsOf(name);
          final price = (j['quotedPrice'] as num?)?.toInt();
          return _OfferData(
            initials: initials,
            name: name,
            note: j['message'] as String? ?? '',
            amount: price != null ? '₹$price' : '—',
            tint: NeedHubTokens.forest,
          );
        }).toList();
      });
    } catch (_) {/* not the poster — keep static offers */}
  }

  static String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    offersNotifier.removeListener(_rebuild);
    super.dispose();
  }

  Color get _categoryColor {
    switch (need.category) {
      case 'earn': return NeedHubTokens.ochre;
      case 'chitchat': return NeedHubTokens.clay;
      default: return NeedHubTokens.forest;
    }
  }

  String get _categoryLabel {
    switch (need.category) {
      case 'earn': return 'Earn';
      case 'chitchat': return 'Chit-chat';
      default: return 'Connect';
    }
  }

  String get _actionLabel {
    switch (need.category) {
      case 'earn': return 'Apply to Help';
      case 'chitchat': return 'Start a chat';
      default: return 'Connect';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cat = _categoryColor;
    final hasBudget = need.budgetMin != null;

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header nav
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: t.card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: t.ink.withValues(alpha: 0.09),
                                  width: 1,
                                ),
                              ),
                              child: Icon(Icons.chevron_left_rounded,
                                  size: 20, color: t.ink),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => NhReportSheet.open(
                              context,
                              targetName: need.title,
                              targetType: 'NEED',
                              targetId: need.id,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.flag_outlined,
                                    size: 15, color: t.muted),
                                const SizedBox(width: 5),
                                Text(
                                  'Report',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: t.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Main need card (with left bar)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.card,
                          border: Border.all(
                            color: const Color(0xFF211E17).withValues(alpha: 0.10),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          children: [
                            // Left bar
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: 0,
                              child: Container(width: 8, color: cat),
                            ),
                            // Content
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Category + pay badge row
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: cat,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                _categoryLabel.toUpperCase(),
                                                style:
                                                    GoogleFonts.hankenGrotesk(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.06 * 11,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              need.title,
                                              style: GoogleFonts
                                                  .bricolageGrotesque(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                                color: t.ink,
                                                height: 1.15,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (hasBudget) ...[
                                        const SizedBox(width: 14),
                                        Transform.rotate(
                                          angle: 0.0524,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 10),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                  color: cat, width: 2.5),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  '₹${need.budgetMin}',
                                                  style: GoogleFonts
                                                      .bricolageGrotesque(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.w800,
                                                    color: cat,
                                                    height: 1,
                                                  ),
                                                ),
                                                Text(
                                                  'per job',
                                                  style:
                                                      GoogleFonts.hankenGrotesk(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: t.muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),

                                  // Description
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Text(
                                      need.description,
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: t.ink2,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),

                                  // Tags
                                  if (need.tags.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 7,
                                      runSpacing: 7,
                                      children: need.tags
                                          .map((tag) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: t.chip,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  '#$tag',
                                                  style:
                                                      GoogleFonts.hankenGrotesk(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: t.muted2,
                                                  ),
                                                ),
                                              ))
                                          .toList(),
                                    ),
                                  ],

                                  // Footer (author)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Container(
                                      padding: const EdgeInsets.only(top: 14),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(
                                            color: const Color(0xFF211E17)
                                                .withValues(alpha: 0.16),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              color: t.rail2,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              need.authorInitials,
                                              style:
                                                  GoogleFonts.hankenGrotesk(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: t.muted4,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 9),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                need.authorName,
                                                style:
                                                    GoogleFonts.hankenGrotesk(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: t.ink,
                                                ),
                                              ),
                                              Text(
                                                '${need.location} · 0 offers',
                                                style:
                                                    GoogleFonts.hankenGrotesk(
                                                  fontSize: 12,
                                                  color: t.muted,
                                                ),
                                              ),
                                            ],
                                          ),
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
                    ),
                    const SizedBox(height: 18),

                    // Recent offers section
                    Builder(builder: (context) {
                      final userOffers = mockOffers[need.id] ?? [];
                      // If the API returned real offers (poster view), those
                      // come first. Otherwise show local + static mock offers.
                      final allOffers = _realOffers.isNotEmpty
                          ? [
                              ..._realOffers,
                              ...userOffers.map((o) => _OfferData(
                                    initials: o.initials,
                                    name: o.name,
                                    note: o.note,
                                    amount: o.amount,
                                    tint: o.color,
                                  )),
                            ]
                          : [
                              ...userOffers.map((o) => _OfferData(
                                    initials: o.initials,
                                    name: o.name,
                                    note: o.note,
                                    amount: o.amount,
                                    tint: o.color,
                                  )),
                              ..._staticOffers,
                            ];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'RECENT OFFERS (${allOffers.length})',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.08 * 12,
                                color: t.muted,
                              ),
                            ),
                            const SizedBox(height: 9),
                            if (allOffers.isEmpty)
                              const NhEmptyState(
                                icon: Icons.inbox_outlined,
                                title: 'No offers yet',
                                subtitle: 'Be the first to respond to this need',
                              )
                            else
                              ...allOffers.map((o) => Padding(
                                padding: const EdgeInsets.only(bottom: 9),
                                child: _OfferCard(
                                  initials: o.initials,
                                  name: o.name,
                                  note: o.note,
                                  amount: o.amount,
                                  tint: o.tint,
                                  catTint: cat,
                                  t: t,
                                ),
                              )),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            // CTA button
            Container(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: BoxDecoration(
                color: t.paper,
                border:
                    Border(top: BorderSide(color: t.rail, width: 1)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => need.category == 'earn'
                          ? _EarnOfferSheet(need: need)
                          : _ConnectSheet(
                              need: need,
                              actionLabel: _actionLabel,
                              categoryColor: cat,
                            ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cat,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: GoogleFonts.bricolageGrotesque(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(_actionLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final String initials;
  final String name;
  final String note;
  final String amount;
  final Color tint;
  final Color catTint;
  final NeedHubTokens t;

  const _OfferCard({
    required this.initials,
    required this.name,
    required this.note,
    required this.amount,
    required this.tint,
    required this.catTint,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(
          color: const Color(0xFF211E17).withValues(alpha: 0.08),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
                Text(
                  note,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    color: t.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: catTint,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Earn Offer sheet ──────────────────────────────────────────────────────────

class _EarnOfferSheet extends ConsumerStatefulWidget {
  final Need need;

  const _EarnOfferSheet({required this.need});

  @override
  ConsumerState<_EarnOfferSheet> createState() => _EarnOfferSheetState();
}

class _EarnOfferSheetState extends ConsumerState<_EarnOfferSheet> {
  final _rateController = TextEditingController();
  final _noteController = TextEditingController();
  String? _workSamplePath;
  bool _sent = false;
  bool _sending = false;

  @override
  void dispose() {
    _rateController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _rateController.text.trim().isNotEmpty &&
      _noteController.text.trim().length >= 5 &&
      !_sending;

  Future<void> _submit() async {
    if (!_canSend) return;
    setState(() => _sending = true);
    try {
      final api = ref.read(apiClientProvider);
      final Map<String, dynamic> fields = {
        'message': _noteController.text.trim(),
        'quotedPrice': double.tryParse(_rateController.text.trim()) ?? 0,
      };

      if (_workSamplePath != null) {
        final form = FormData.fromMap({
          ...fields.map((k, v) => MapEntry(k, v.toString())),
          'workSample': await MultipartFile.fromFile(
            _workSamplePath!,
            filename: _workSamplePath!.split('/').last,
          ),
        });
        await api.postForm('/needs/${widget.need.id}/responses', form);
      } else {
        await api.post('/needs/${widget.need.id}/responses', fields);
      }

      // Also update local mock state so the offers list shows immediately
      final offers = mockOffers.putIfAbsent(widget.need.id, () => []);
      offers.insert(0, NeedOffer(
        name: 'You',
        initials: 'ME',
        note: _noteController.text.trim(),
        amount: '₹${_rateController.text.trim()}',
        color: NeedHubTokens.forest,
      ));
      offersNotifier.value++;
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send offer: $e')),
        );
        setState(() => _sending = false);
      }
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
      child: _sent ? _OfferSentView(t: t) : _OfferFormView(
        need: widget.need,
        t: t,
        rateController: _rateController,
        noteController: _noteController,
        workSamplePath: _workSamplePath,
        canSend: _canSend,
        sending: _sending,
        onPickWorkSample: () async {
          final file = await ImagePicker().pickImage(
            source: ImageSource.gallery,
            imageQuality: 80,
          );
          if (file != null && mounted) {
            setState(() => _workSamplePath = file.path);
          }
        },
        onSend: _submit,
        onChanged: () => setState(() {}),
      ),
    );
  }
}

class _OfferFormView extends StatelessWidget {
  final Need need;
  final NeedHubTokens t;
  final TextEditingController rateController;
  final TextEditingController noteController;
  final String? workSamplePath;
  final bool canSend;
  final bool sending;
  final VoidCallback onPickWorkSample;
  final VoidCallback onSend;
  final VoidCallback onChanged;

  const _OfferFormView({
    required this.need,
    required this.t,
    required this.rateController,
    required this.noteController,
    required this.workSamplePath,
    required this.canSend,
    required this.sending,
    required this.onPickWorkSample,
    required this.onSend,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: t.rail, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Apply to help',
                      style: GoogleFonts.bricolageGrotesque(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: t.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      need.title,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 14, color: t.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.rail, width: 1),
                  ),
                  child: Icon(Icons.close_rounded,
                      size: 18, color: t.muted2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Rate
          Text('YOUR RATE (₹/hr)',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.muted2,
                  letterSpacing: 0.7)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: t.paper,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: t.rail, width: 1.5),
            ),
            child: TextField(
              controller: rateController,
              keyboardType: TextInputType.number,
              onChanged: (_) => onChanged(),
              style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
              decoration: InputDecoration(
                hintText: 'e.g. 500',
                hintStyle: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
                prefixIcon: Icon(Icons.currency_rupee_rounded,
                    size: 18, color: t.muted),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                filled: false,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Note
          Text('INTRO NOTE',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.muted2,
                  letterSpacing: 0.7)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: t.paper,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: t.rail, width: 1.5),
            ),
            child: TextField(
              controller: noteController,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => onChanged(),
              style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
              decoration: InputDecoration(
                hintText: 'Tell them why you\'re a great fit…',
                hintStyle: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
                filled: false,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Work sample slot (optional)
          GestureDetector(
            onTap: onPickWorkSample,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: workSamplePath != null
                    ? NeedHubTokens.ochre.withValues(alpha: 0.08)
                    : t.paper,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: workSamplePath != null ? NeedHubTokens.ochre : t.rail,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    workSamplePath != null
                        ? Icons.check_circle_rounded
                        : Icons.attach_file_rounded,
                    color: workSamplePath != null ? NeedHubTokens.ochre : t.muted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workSamplePath != null
                              ? 'Work sample added'
                              : 'Add work sample (optional)',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: workSamplePath != null
                                ? NeedHubTokens.ochre
                                : t.muted2,
                          ),
                        ),
                        Text(
                          'Portfolio, screenshot, or file',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 12, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                  if (workSamplePath == null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: t.chip,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.rail),
                      ),
                      child: Text(
                        'Browse',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: t.muted2),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: canSend ? onSend : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: NeedHubTokens.ochre,
                foregroundColor: Colors.white,
                disabledBackgroundColor: t.rail,
                disabledForegroundColor: t.muted,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                textStyle: GoogleFonts.bricolageGrotesque(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: sending
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send offer'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferSentView extends StatelessWidget {
  final NeedHubTokens t;

  const _OfferSentView({required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: NeedHubTokens.ochre.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.check_rounded,
              color: NeedHubTokens.ochre, size: 30),
        ),
        const SizedBox(height: 16),
        Text(
          'Offer sent!',
          style: GoogleFonts.bricolageGrotesque(
              fontSize: 22, fontWeight: FontWeight.w800, color: t.ink),
        ),
        const SizedBox(height: 6),
        Text(
          'Chat unlocks when they accept your offer.',
          style: GoogleFonts.hankenGrotesk(
              fontSize: 14, color: t.muted, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Done',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

// ── Connect / Apply bottom sheet ───────────────────────────────────────────────

class _ConnectSheet extends StatefulWidget {
  final Need need;
  final String actionLabel;
  final Color categoryColor;

  const _ConnectSheet({
    required this.need,
    required this.actionLabel,
    required this.categoryColor,
  });

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  final _controller = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad + 20),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: _sent
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: NeedHubTokens.forest.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.check_rounded, color: NeedHubTokens.forest, size: 28),
                ),
                const SizedBox(height: 14),
                Text(
                  'Message sent!',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.need.authorName} will be notified.',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    color: t.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Done',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.rail,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.actionLabel,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Send a short intro to ${widget.need.authorName}',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    color: t.muted,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: t.rail, width: 1.5),
                  ),
                  child: TextField(
                    controller: _controller,
                    minLines: 3,
                    maxLines: 5,
                    style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
                    decoration: InputDecoration(
                      hintText: 'Hi! I saw your need and…',
                      hintStyle: GoogleFonts.hankenGrotesk(
                        fontSize: 14,
                        color: t.muted,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(14),
                      filled: false,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_controller.text.trim().isEmpty) return;
                      setState(() => _sent = true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.categoryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: GoogleFonts.bricolageGrotesque(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text('Send message'),
                  ),
                ),
              ],
            ),
    );
  }
}
