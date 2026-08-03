import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../theme/tokens.dart';
import 'nh_ad_inquiry_sheet.dart';

class NhAdCard extends StatelessWidget {
  final NeedHubTokens t;
  const NhAdCard({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const NhAdInquirySheet(),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              NeedHubTokens.ochre.withValues(alpha: 0.08),
              NeedHubTokens.ochre.withValues(alpha: 0.03),
            ],
          ),
          border: Border.all(
            color: NeedHubTokens.ochre.withValues(alpha: 0.30),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: NeedHubTokens.ochre.withValues(alpha: 0.10),
              offset: const Offset(0, 4),
              blurRadius: 12,
              spreadRadius: -4,
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Decorative accent strip on left
            Positioned(
              top: 0, bottom: 0, left: 0,
              child: Container(width: 6, color: NeedHubTokens.ochre),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: NeedHubTokens.ochre.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(Icons.campaign_rounded, color: NeedHubTokens.ochre, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              S.current.advertiseHere,
                              style: GoogleFonts.bricolageGrotesque(
                                fontSize: 17, fontWeight: FontWeight.w800,
                                color: t.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              S.current.advertiseDesc,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 13, color: t.muted2, height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // AD badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: NeedHubTokens.ochre,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text('AD',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 10, fontWeight: FontWeight.w800,
                            letterSpacing: 0.5, color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // CTA button
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: NeedHubTokens.ochre,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        S.current.getInTouch,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
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
