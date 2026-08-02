import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_state.dart';
import '../theme/tokens.dart';
import '../l10n/app_strings.dart';
import 'nh_report_sheet.dart';

class NhPersonProfileSheet extends StatelessWidget {
  final String name;
  final String initials;
  final Color avatarColor;
  final String? subtitle;

  const NhPersonProfileSheet({
    super.key,
    required this.name,
    required this.initials,
    required this.avatarColor,
    this.subtitle,
  });

  static Future<void> open(
    BuildContext context, {
    required String name,
    required String initials,
    required Color avatarColor,
    String? subtitle,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NhPersonProfileSheet(
        name: name,
        initials: initials,
        avatarColor: avatarColor,
        subtitle: subtitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 14, 24, MediaQuery.of(context).padding.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: t.rail, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),

            // Avatar
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: avatarColor,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF281E0F).withValues(alpha: 0.5),
                    offset: const Offset(0, 16),
                    blurRadius: 30,
                    spreadRadius: -14,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              name,
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: t.ink,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 13.5,
                  color: t.muted2,
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Friend / blocked status
            ValueListenableBuilder<Set<String>>(
              valueListenable: blockedNotifier,
              builder: (_, blocked, __) {
                final isBlocked = blocked.contains(name);
                if (isBlocked) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.block_rounded,
                            size: 15, color: Colors.red.shade400),
                        const SizedBox(width: 6),
                        Text(
                          S.current.blockedStatus,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.red.shade400,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ValueListenableBuilder<Set<String>>(
                  valueListenable: friendsNotifier,
                  builder: (_, friends, __) {
                    final isFriend = friends.contains(name);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isFriend
                            ? NeedHubTokens.forest.withValues(alpha: 0.10)
                            : t.chip,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isFriend
                                ? Icons.check_circle_rounded
                                : Icons.person_outline_rounded,
                            size: 15,
                            color: isFriend
                                ? NeedHubTokens.forest
                                : t.muted2,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isFriend ? S.current.friendsStatus : S.current.notFriendsYet,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isFriend
                                  ? NeedHubTokens.forest
                                  : t.muted2,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 28),

            // Actions
            ValueListenableBuilder<Set<String>>(
              valueListenable: friendsNotifier,
              builder: (_, friends, __) {
                final isFriend = friends.contains(name);
                return SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (isFriend) {
                        removeFriend(name);
                      } else {
                        addFriend(name);
                      }
                    },
                    icon: Icon(
                      isFriend
                          ? Icons.person_remove_outlined
                          : Icons.person_add_outlined,
                      size: 18,
                      color: NeedHubTokens.clay,
                    ),
                    label: Text(
                      isFriend ? S.current.removeFriend : S.current.addFriend,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: NeedHubTokens.clay),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: NeedHubTokens.clay.withValues(alpha: 0.35),
                          width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                NhReportSheet.open(context, targetName: name);
              },
              icon: Icon(Icons.flag_outlined,
                  size: 16, color: Colors.red.shade400),
              label: Text(
                S.current.report,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
