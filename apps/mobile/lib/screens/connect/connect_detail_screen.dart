import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/person.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_avatar.dart';
import '../../widgets/nh_report_sheet.dart';
import 'connect_request_sheet.dart';
import '../../../l10n/app_strings.dart';

class ConnectDetailScreen extends StatefulWidget {
  final Person person;

  const ConnectDetailScreen({super.key, required this.person});

  @override
  State<ConnectDetailScreen> createState() => _ConnectDetailScreenState();
}

class _ConnectDetailScreenState extends State<ConnectDetailScreen> {
  bool _friendRequestSent = false;
  bool _pressingFriend = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final person = widget.person;
    final shared = person.sharedInterests;
    final unique = person.uniqueInterests;

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
                              targetName: person.name,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.flag_outlined,
                                    size: 15, color: t.muted),
                                const SizedBox(width: 5),
                                Text(
                                  S.current.report,
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

                    // Centered avatar + name section
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                      child: Center(
                        child: Column(
                          children: [
                            NhAvatar(
                              avatarUrl: person.avatarUrl,
                              initials: person.initials,
                              size: 88,
                              borderRadius: 26,
                              backgroundColor: person.avatarColor,
                              fontSize: 32,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              person.name,
                              style: GoogleFonts.bricolageGrotesque(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: t.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              person.promptQ1,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 13.5,
                                color: t.muted2,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Container(
                              padding: const EdgeInsets.fromLTRB(7, 5, 12, 5),
                              decoration: BoxDecoration(
                                color: t.chip,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: NeedHubTokens.forest,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${person.location} · ${person.distanceLabel}',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: t.muted4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    // The Overlap card (dark surface)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        decoration: BoxDecoration(
                          color: t.surfaceDark,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              S.current.theOverlap,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1 * 11,
                                color: NeedHubTokens.clay,
                              ),
                            ),
                            const SizedBox(height: 11),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ...shared.map((label) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 13, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: NeedHubTokens.clay,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        label,
                                        style: GoogleFonts.hankenGrotesk(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    )),
                                ...unique.map((label) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 13, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.25),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        label,
                                        style: GoogleFonts.hankenGrotesk(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: t.onDarkMuted2,
                                        ),
                                      ),
                                    )),
                              ],
                            ),
                            const SizedBox(height: 11),
                            Text(
                              S.current.overlapDesc,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 12.5,
                                color: t.onDarkMuted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Prompt Q&A cards
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          _PromptCard(
                              q: person.promptQ1,
                              a: person.promptA1,
                              t: t),
                          const SizedBox(height: 12),
                          _PromptCard(
                              q: person.promptQ2,
                              a: person.promptA2,
                              t: t),
                          const SizedBox(height: 12),
                          _PromptCard(
                              q: person.promptQ3,
                              a: person.promptA3,
                              t: t),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Photos section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            S.current.fewPhotosSection,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.08 * 11,
                              color: t.muted,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                            child: Row(
                              children: [
                                Icon(Icons.photo_library_outlined, size: 22, color: t.muted2),
                                const SizedBox(width: 10),
                                Text(
                                  S.current.noPhotosYet,
                                  style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // CTA
            Container(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
              decoration: BoxDecoration(
                color: t.paper,
                border: Border(top: BorderSide(color: t.rail, width: 1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Add Friend button with press bounce
                  AnimatedScale(
                    scale: _pressingFriend ? 0.93 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    child: GestureDetector(
                      onTapDown: _friendRequestSent
                          ? null
                          : (_) => setState(() => _pressingFriend = true),
                      onTapUp: _friendRequestSent
                          ? null
                          : (_) => setState(() {
                                _pressingFriend = false;
                                _friendRequestSent = true;
                              }),
                      onTapCancel: () => setState(() => _pressingFriend = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _friendRequestSent
                              ? Colors.transparent
                              : NeedHubTokens.clay.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _friendRequestSent
                                ? t.rail
                                : NeedHubTokens.clay.withValues(alpha: 0.40),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _friendRequestSent
                                  ? Icons.check_rounded
                                  : Icons.person_add_outlined,
                              size: 18,
                              color: _friendRequestSent ? t.muted : NeedHubTokens.clay,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _friendRequestSent ? S.current.requestSent : S.current.addFriend,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _friendRequestSent ? t.muted : NeedHubTokens.clay,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Connect request button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => ConnectRequestSheet(person: person),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NeedHubTokens.forest,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        textStyle: GoogleFonts.bricolageGrotesque(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      child: Text(S.current.sendConnectRequest),
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

class _PromptCard extends StatelessWidget {
  final String q;
  final String a;
  final NeedHubTokens t;

  const _PromptCard({required this.q, required this.a, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(
          color: const Color(0xFF211E17).withValues(alpha: 0.09),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: NeedHubTokens.forest,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            a,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: t.ink,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
