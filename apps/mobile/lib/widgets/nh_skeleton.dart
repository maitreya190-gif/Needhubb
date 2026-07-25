import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/tokens.dart';

class NhSkeleton extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const NhSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Shimmer.fromColors(
      baseColor: t.rail,
      highlightColor: t.card,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: t.rail,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class NhEarnCardSkeleton extends StatelessWidget {
  const NhEarnCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Shimmer.fromColors(
      baseColor: t.rail,
      highlightColor: t.card,
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Positioned(
              top: 0, bottom: 0, left: 0,
              child: Container(width: 6, color: t.rail2),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(width: 60, height: 18, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(5))),
                            const SizedBox(height: 10),
                            Container(width: double.infinity, height: 20, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(6))),
                            const SizedBox(height: 6),
                            Container(width: 200, height: 20, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(6))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(width: 60, height: 60, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(9))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: t.rail),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(width: 24, height: 24, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(7))),
                      const SizedBox(width: 8),
                      Container(width: 160, height: 14, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(5))),
                    ],
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

class NhPersonCardSkeleton extends StatelessWidget {
  const NhPersonCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Shimmer.fromColors(
      baseColor: t.rail,
      highlightColor: t.card,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 50, height: 50, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(16))),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 140, height: 18, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(6))),
                      const SizedBox(height: 6),
                      Container(width: 100, height: 14, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(5))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(width: double.infinity, height: 14, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(5))),
            const SizedBox(height: 6),
            Container(width: 240, height: 14, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(5))),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(width: 70, height: 26, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(9))),
                const SizedBox(width: 8),
                Container(width: 70, height: 26, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(9))),
                const SizedBox(width: 8),
                Container(width: 70, height: 26, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(9))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class NhChatRowSkeleton extends StatelessWidget {
  const NhChatRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Shimmer.fromColors(
      baseColor: t.rail,
      highlightColor: t.card,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(14))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 120, height: 15, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(5))),
                  const SizedBox(height: 6),
                  Container(width: 200, height: 13, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(5))),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 32, height: 12, decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(5))),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _Unused extends StatelessWidget {
  const _Unused();
  @override
  Widget build(BuildContext context) => GoogleFonts.hankenGrotesk(fontSize: 0) as Widget;
}
