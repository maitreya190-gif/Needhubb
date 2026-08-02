import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_strings.dart';
import '../../providers/language_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../../models/need.dart';
import '../../models/user_state.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/league_api.dart';
import '../../services/needs_api.dart';
import '../../services/referrals_api.dart';
import '../../services/personality_api.dart';
import '../../services/profiles_api.dart';
import '../../services/social_providers.dart';
import '../../services/uploads_api.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_avatar.dart';
import '../../widgets/nh_badge_row.dart';
import '../../widgets/nh_seasonal_badge.dart';
import '../../widgets/nh_skill_vouch_section.dart';
import '../history/history_screen.dart';
import '../hub/tabs/feed_tab.dart';
import '../league/impact_league_screen.dart';
import '../needs/need_detail_screen.dart';
import '../personality/personality_test_screen.dart';
import '../redeem/redeem_screen.dart';
import 'edit_profile_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'qr_scanner_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

class YouScreen extends ConsumerWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final t = context.tokens;
    final s = S.current;
    final name = auth.displayName ?? auth.email ?? 'You';
    final initials = _initials(name);

    Future<void> handlePullToRefresh() async {
      final profilesApi = ref.read(profilesApiProvider);
      try {
        final me = await profilesApi.me();
        myProfileNotifier.value = me;
        pointsNotifier.value = me.pointsTotal;
        bioNotifier.value = me.bio ?? '';
        promptSkillNotifier.value = me.promptSkill ?? '';
        promptCollabNotifier.value = me.promptCollab ?? '';
        promptNeedNotifier.value = me.promptNeed ?? '';
        genderNotifier.value = me.gender;
        locationNotifier.value = me.locationText ?? '';
        avatarUrlNotifier.value = me.avatarUrl;
        customInterestsNotifier.value = me.interestLabels;
        customSkillsNotifier.value = me.skillLabels;
      } catch (_) {/* keep last-known profile */}
      final uploadsApi = ref.read(uploadsApiProvider);
      try {
        myCertificatesNotifier.value = await uploadsApi.myCertificates();
      } catch (_) {/* keep last-known list */}
      try {
        myAchievementsNotifier.value = await uploadsApi.myAchievements();
      } catch (_) {/* keep last-known list */}
    }

    return Scaffold(
      backgroundColor: t.paper,
      body: RefreshIndicator(
        onRefresh: handlePullToRefresh,
        color: NeedHubTokens.clay,
        child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Dark profile header
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Container(
                decoration: BoxDecoration(
                  color: t.surfaceDark,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(28),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Settings + Edit row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () => context.push('/settings'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.settings_outlined,
                                    size: 14, color: t.onDark),
                                const SizedBox(width: 5),
                                Text(
                                  s.settings,
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: t.onDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Text(
                              s.edit,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: t.onDark,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Avatar + name row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ValueListenableBuilder<String?>(
                              valueListenable: avatarUrlNotifier,
                              builder: (_, avatarUrl, __) => NhAvatar(
                                avatarUrl: avatarUrl,
                                initials: initials,
                                size: 70,
                                borderRadius: 22,
                                backgroundColor: NeedHubTokens.forest,
                                fontSize: 26,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () => _showQrBottomSheet(context, auth, t),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    width: 1,
                                  ),
                                ),
                                child: QrImageView(
                                  data: 'needhub:profile:${auth.userId}',
                                  version: QrVersions.auto,
                                  size: 42,
                                  gapless: false,
                                  eyeStyle: QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: t.onDark,
                                  ),
                                  dataModuleStyle: QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: t.onDark,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                auth.displayName ?? 'Welcome!',
                                style: GoogleFonts.bricolageGrotesque(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: t.onDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              ValueListenableBuilder<ProfileMe?>(
                                valueListenable: myProfileNotifier,
                                builder: (_, me, __) => me?.username != null
                                    ? Text(
                                        '@${me!.username}',
                                        style: GoogleFonts.hankenGrotesk(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: t.onDarkMuted,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                auth.email ?? '',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 12.5,
                                  color: t.onDarkMuted,
                                ),
                              ),
                              ValueListenableBuilder<String>(
                                valueListenable: locationNotifier,
                                builder: (_, loc, __) =>
                                    ValueListenableBuilder<String?>(
                                  valueListenable: genderNotifier,
                                  builder: (_, gender, __) => Text(
                                    gender == null
                                        ? loc
                                        : '$loc · $gender',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 12,
                                      color: t.onDarkMuted,
                                    ),
                                  ),
                                ),
                              ),
                              FutureBuilder<({double avg, int count, List<Map<String, dynamic>> reviews})>(
                                future: ref.read(reviewsApiProvider).forUser(ref.read(authProvider).userId ?? ''),
                                builder: (context, snapshot) {
                                  final data = snapshot.data;
                                  if (data == null || data.count == 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: GestureDetector(
                                      onTap: () {
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          backgroundColor: Colors.transparent,
                                          builder: (_) => _UserReviewsSheet(
                                            avg: data.avg,
                                            count: data.count,
                                            reviews: data.reviews,
                                          ),
                                        );
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.star_rounded, size: 15, color: Color(0xFFEAB308)),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${data.avg.toStringAsFixed(1)} ★ (${data.count} ${data.count == 1 ? 'rating' : 'ratings'})',
                                            style: GoogleFonts.hankenGrotesk(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: t.onDark,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(Icons.chevron_right_rounded, size: 16, color: t.onDarkMuted),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              ValueListenableBuilder<String>(
                                valueListenable: bioNotifier,
                                builder: (_, bio, __) {
                                  if (bio.trim().isEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: GestureDetector(
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) => const EditProfileScreen()),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_note_rounded,
                                                size: 15, color: t.onDarkMuted),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Add a short bio about yourself…',
                                              style: GoogleFonts.hankenGrotesk(
                                                fontSize: 12,
                                                color: t.onDarkMuted,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      bio,
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 12.5,
                                        color: t.onDark,
                                        height: 1.35,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // "People you've helped" link
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => HistoryScreen(
                                  userId: ref.read(authProvider).userId,
                                )),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.people_outline_rounded,
                                size: 16, color: t.onDarkMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.peopleYouveHelped,
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: t.onDarkMuted,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                size: 18, color: t.onDarkMuted),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── My Posted Needs & History ──────────────────────────────
                  _MyPostedNeedsSection(t: t),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1, thickness: 1.5),
                  const SizedBox(height: 22),

                  // ── Trust Score ─────────────────────────────────────────────
                  _TrustScoreSection(t: t),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1, thickness: 1.5),
                  const SizedBox(height: 22),

                  // ── Verifications ─────────────────────────────────────────
                  _CollapsibleSection(
                    title: 'VERIFICATIONS',
                    t: t,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FaceVerifySection(t: t),
                        const SizedBox(height: 16),
                        _PhoneVerifySection(t: t),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1, thickness: 1.5),
                  const SizedBox(height: 22),

                  // ── Impact section ───────────────────────────────────────
                  Text(
                    'IMPACT',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.muted2,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Balance card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: t.surfaceDark,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.reliabilityPoints,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                            color: t.onDarkMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ValueListenableBuilder<int>(
                          valueListenable: pointsNotifier,
                          builder: (_, points, __) => TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: points.toDouble()),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (_, value, __) => Text(
                              '${value.round()}',
                              style: GoogleFonts.bricolageGrotesque(
                                fontSize: 52,
                                fontWeight: FontWeight.w800,
                                color: NeedHubTokens.clay,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Breakdown pills
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _BreakdownPill(
                                label: s.needsDone, value: '+180'),
                            _BreakdownPill(
                                label: s.reviews, value: '+90'),
                            _BreakdownPill(
                                label: 'Certificates', value: '+70'),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Redeem button
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  RedeemScreen(balance: pointsNotifier.value),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 11),
                            decoration: BoxDecoration(
                              color: NeedHubTokens.clay,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              s.redeemPoints,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Refer a Friend card ──────────────────────────────────
                  _ReferAFriendCard(ref: ref, t: t),

                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1, thickness: 1.5),
                  const SizedBox(height: 22),

                  // ── Sustainability Certificates ──────────────────────────
                  Row(
                    children: [
                      Text(
                        s.sustainabilityCerts,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: t.muted2,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showAddCertificateSheet(context, t),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: NeedHubTokens.forest.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: NeedHubTokens.forest
                                    .withValues(alpha: 0.35),
                                width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add_rounded,
                                  size: 15, color: NeedHubTokens.forest),
                              const SizedBox(width: 4),
                              Text(
                                'Add',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: NeedHubTokens.forest,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<List<MyCertificate>>(
                    valueListenable: myCertificatesNotifier,
                    builder: (_, certs, __) {
                      if (certs.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: t.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: t.rail, width: 1),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.workspace_premium_outlined,
                                  color: t.muted2, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  s.noCertificates,
                                  style: GoogleFonts.hankenGrotesk(
                                      fontSize: 13, color: t.muted),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return Column(
                        children: certs.map((c) {
                          final approved = c.status == 'APPROVED';
                          final rejected = c.status == 'REJECTED';
                          final status = approved
                              ? 'Approved'
                              : rejected
                                  ? 'Rejected'
                                  : 'Pending';
                          final color = approved
                              ? NeedHubTokens.forest
                              : rejected
                                  ? NeedHubTokens.clay
                                  : NeedHubTokens.ochre;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _CertTile(
                              title: c.title,
                              org: c.subtitle.isNotEmpty
                                  ? c.subtitle
                                  : c.type.replaceAll('_', ' '),
                              status: status,
                              statusColor: color,
                              t: t,
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1, thickness: 1.5),
                  const SizedBox(height: 22),

                  // ── Badges (earned, server-computed) ─────────────────────
                  Text(
                    s.badges,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.muted2,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Earned automatically from what you actually do. Each one adds to your Trust Score.',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 12.5, color: t.muted),
                  ),
                  const SizedBox(height: 14),
                  _BadgesSection(t: t),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1, thickness: 1.5),
                  const SizedBox(height: 22),

                  // ── Skills & Vouches (earned, server-computed) ────────────
                  _CollapsibleSection(
                    title: 'SKILLS & VOUCHES',
                    subtitle:
                        'Skill vouches from people you\'ve worked with. A "Verified" badge means you actually completed a Need together.',
                    t: t,
                    child: _SkillVouchesSection(t: t),
                  ),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1, thickness: 1.5),
                  const SizedBox(height: 22),

                  // ── Impact League (seasonal leaderboard + badges) ─────────
                  Text(
                    s.impactLeague,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.muted2,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.impactLeagueDesc,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 12.5, color: t.muted),
                  ),
                  const SizedBox(height: 14),
                  const _ImpactLeagueSection(),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1, thickness: 1.5),
                  const SizedBox(height: 22),

                  // ── Achievements ─────────────────────────────────────────
                  Row(
                    children: [
                      Text(
                        s.achievements,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: t.muted2,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showAddAchievementSheet(context, t),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: NeedHubTokens.clay.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: NeedHubTokens.clay
                                    .withValues(alpha: 0.35),
                                width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add_rounded,
                                  size: 15, color: NeedHubTokens.clay),
                              const SizedBox(width: 4),
                              Text(
                                'Add',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: NeedHubTokens.clay,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Earned through doing — not spendable.',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 12.5, color: t.muted),
                  ),
                  const SizedBox(height: 14),
                  _AchievementsRow(t: t),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1, thickness: 1.5),
                  const SizedBox(height: 22),

                  // ── Quick links ──────────────────────────────────────────
                  _QuickLink(
                    icon: Icons.history_rounded,
                    label: s.pastWorkHistory,
                    color: NeedHubTokens.forest,
                    t: t,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const HistoryScreen()),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1, thickness: 1.5),
                  const SizedBox(height: 22),

                  // ── Interests ────────────────────────────────────────────
                  _CollapsibleSection(
                    title: s.interests.toUpperCase(),
                    t: t,
                    child: ValueListenableBuilder<List<String>>(
                      valueListenable: customInterestsNotifier,
                      builder: (_, interests, __) {
                        if (interests.isEmpty) {
                          return Text(
                            'No interests added yet — tap Edit to add some',
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 13, color: t.muted2),
                          );
                        }
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: interests
                              .map((i) => _Chip(
                                  label: i, color: NeedHubTokens.forest, t: t))
                              .toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Skills ───────────────────────────────────────────────
                  _CollapsibleSection(
                    title: s.skills.toUpperCase(),
                    t: t,
                    child: ValueListenableBuilder<List<String>>(
                      valueListenable: customSkillsNotifier,
                      builder: (_, skills, __) {
                        if (skills.isEmpty) {
                          return Text(
                            'No skills added yet — tap Edit to add some',
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 13, color: t.muted2),
                          );
                        }
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: skills
                              .map((s) => _Chip(
                                  label: s, color: NeedHubTokens.ochre, t: t))
                              .toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1, thickness: 1.5),
                  const SizedBox(height: 22),

                  // ── About me prompts ─────────────────────────────────────
                  _CollapsibleSection(
                    title: s.aboutMe,
                    t: t,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ValueListenableBuilder<String>(
                          valueListenable: promptSkillNotifier,
                          builder: (_, a, __) => _PromptCard(
                            q: s.skillIdLoveToTeach,
                            a: a,
                            t: t,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ValueListenableBuilder<String>(
                          valueListenable: promptCollabNotifier,
                          builder: (_, a, __) => _PromptCard(
                            q: s.myIdealCollab,
                            a: a,
                            t: t,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ValueListenableBuilder<String>(
                          valueListenable: promptNeedNotifier,
                          builder: (_, a, __) => _PromptCard(
                            q: s.needIdPostRightNow,
                            a: a,
                            t: t,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1, thickness: 1.5),
                  const SizedBox(height: 22),

                  // ── Logout ───────────────────────────────────────────────
                  OutlinedButton(
                    onPressed: () async {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) context.go('/login');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.muted2,
                      minimumSize: const Size.fromHeight(48),
                      side: BorderSide(color: t.rail, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      s.logout,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.muted2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  void _showAddCertificateSheet(BuildContext context, NeedHubTokens t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddCertificateSheet(),
    );
  }

  void _showAddAchievementSheet(BuildContext context, NeedHubTokens t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddAchievementSheet(),
    );
  }

  void _showQrBottomSheet(BuildContext context, AuthState auth, NeedHubTokens t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProfileQrSheet(auth: auth, t: t),
    );
  }
}

// ── Achievement upload sheet ─────────────────────────────────────────────────

class _AddAchievementSheet extends ConsumerStatefulWidget {
  const _AddAchievementSheet();

  @override
  ConsumerState<_AddAchievementSheet> createState() =>
      _AddAchievementSheetState();
}

class _AddAchievementSheetState extends ConsumerState<_AddAchievementSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _category = 'COMPETITION';
  String? _filePath;
  bool _submitting = false;

  static const _categories = [
    'COMPETITION', 'HACKATHON', 'TOURNAMENT', 'AWARD',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90);
    if (file != null && mounted) setState(() => _filePath = file.path);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      final fields = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'category': _category,
      };
      if (_filePath != null) {
        final form = FormData.fromMap({
          ...fields.map((k, v) => MapEntry(k, v.toString())),
          'file': await MultipartFile.fromFile(_filePath!,
              filename: _filePath!.split('/').last),
        });
        await api.postForm('/achievements', form);
      } else {
        await api.post('/achievements', fields);
      }
      try {
        final uploads = ref.read(uploadsApiProvider);
        myAchievementsNotifier.value = await uploads.myAchievements();
      } catch (_) {/* silent */}
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Achievement submitted for review')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canSubmit = _titleController.text.trim().isNotEmpty &&
        _descriptionController.text.trim().isNotEmpty;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SingleChildScrollView(
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
              const SizedBox(height: 18),
              Text('Add an achievement',
                  style: GoogleFonts.bricolageGrotesque(
                      fontSize: 22, fontWeight: FontWeight.w800, color: t.ink)),
              const SizedBox(height: 6),
              Text(
                  'Submit a competition win, hackathon finish, tournament placement, or award. Admin will review it.',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 13.5, color: t.muted, height: 1.4)),
              const SizedBox(height: 18),
              _FieldLabel(label: 'CATEGORY', t: t),
              Wrap(
                spacing: 8,
                children: _categories.map((c) {
                  final selected = _category == c;
                  return GestureDetector(
                    onTap: () => setState(() => _category = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? NeedHubTokens.clay : t.paper,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: selected ? NeedHubTokens.clay : t.rail,
                            width: 1.5),
                      ),
                      child: Text(c,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : t.ink,
                            letterSpacing: 0.4,
                          )),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              _FieldLabel(label: 'TITLE', t: t),
              _PlainField(
                  controller: _titleController,
                  hint: 'e.g. Runner-up, InovaHack 2026',
                  onChanged: () => setState(() {}),
                  t: t),
              const SizedBox(height: 12),
              _FieldLabel(label: 'DESCRIPTION', t: t),
              _PlainField(
                  controller: _descriptionController,
                  hint: 'What did you achieve? (dates, org, placement)',
                  onChanged: () => setState(() {}),
                  t: t),
              const SizedBox(height: 12),
              _FieldLabel(label: 'IMAGE (OPTIONAL)', t: t),
              GestureDetector(
                onTap: _pickFile,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.rail, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _filePath != null
                            ? Icons.check_circle_rounded
                            : Icons.upload_file_rounded,
                        color: _filePath != null
                            ? NeedHubTokens.forest
                            : t.muted2,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _filePath != null
                              ? _filePath!.split('/').last
                              : 'Choose image (optional)',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: _filePath != null ? t.ink : t.muted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (canSubmit && !_submitting) ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NeedHubTokens.clay,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: t.rail,
                    disabledForegroundColor: t.muted,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Submit for review',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddCertificateSheet extends ConsumerStatefulWidget {
  const _AddCertificateSheet();

  @override
  ConsumerState<_AddCertificateSheet> createState() => _AddCertificateSheetState();
}

class _AddCertificateSheetState extends ConsumerState<_AddCertificateSheet> {
  final _titleController = TextEditingController();
  final _orgController = TextEditingController();
  String? _filePath;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _orgController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file != null && mounted) setState(() => _filePath = file.path);
  }

  Future<void> _submit() async {
    if (_filePath == null) return;
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      final desc = '${_titleController.text.trim()} — ${_orgController.text.trim()}';
      final form = FormData.fromMap({
        'type': 'VOLUNTEERING',
        'description': desc,
        'file': await MultipartFile.fromFile(_filePath!, filename: _filePath!.split('/').last),
      });
      await api.postForm('/certificates', form);
      // Refresh the certificates list so it appears immediately on the You screen.
      try {
        final uploads = ref.read(uploadsApiProvider);
        myCertificatesNotifier.value = await uploads.myCertificates();
      } catch (_) {/* silent */}
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Certificate submitted for review')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canSubmit = _titleController.text.trim().isNotEmpty &&
        _orgController.text.trim().isNotEmpty &&
        _filePath != null;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SingleChildScrollView(
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
              const SizedBox(height: 18),
              Text(
                'Add a certificate',
                style: GoogleFonts.bricolageGrotesque(
                    fontSize: 22, fontWeight: FontWeight.w800, color: t.ink),
              ),
              const SizedBox(height: 6),
              Text(
                'Upload proof of a completed sustainability or volunteer programme. Our team will review it.',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 13.5, color: t.muted, height: 1.4),
              ),
              const SizedBox(height: 18),
              _FieldLabel(label: 'CERTIFICATE TITLE', t: t),
              _PlainField(
                controller: _titleController,
                hint: 'e.g. Community Volunteer',
                onChanged: () => setState(() {}),
                t: t,
              ),
              const SizedBox(height: 12),
              _FieldLabel(label: 'ISSUING ORGANISATION', t: t),
              _PlainField(
                controller: _orgController,
                hint: 'e.g. Teach India',
                onChanged: () => setState(() {}),
                t: t,
              ),
              const SizedBox(height: 12),
              _FieldLabel(label: 'ATTACHMENT (IMAGE)', t: t),
              GestureDetector(
                onTap: _pickFile,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.rail, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _filePath != null
                            ? Icons.check_circle_rounded
                            : Icons.upload_file_rounded,
                        color: _filePath != null
                            ? NeedHubTokens.forest
                            : t.muted2,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _filePath != null
                              ? _filePath!.split('/').last
                              : 'Choose image from gallery',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: _filePath != null ? t.ink : t.muted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (canSubmit && !_submitting) ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NeedHubTokens.forest,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: t.rail,
                    disabledForegroundColor: t.muted,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Submit for review',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final NeedHubTokens t;
  const _FieldLabel({required this.label, required this.t});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: GoogleFonts.hankenGrotesk(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: t.muted2,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _PlainField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final NeedHubTokens t;
  const _PlainField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.t,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: t.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.rail, width: 1.5),
      ),
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          filled: false,
        ),
      ),
    );
  }
}

// ── Breakdown pill (inside impact card) ──────────────────────────────────────

class _BreakdownPill extends StatelessWidget {
  final String label;
  final String value;

  const _BreakdownPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: NeedHubTokens.ochre,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Certificate tile ──────────────────────────────────────────────────────────

class _CertTile extends StatelessWidget {
  final String title;
  final String org;
  final String status;
  final Color statusColor;
  final NeedHubTokens t;

  const _CertTile({
    required this.title,
    required this.org,
    required this.status,
    required this.statusColor,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.rail, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              status == 'Approved'
                  ? Icons.verified_rounded
                  : Icons.hourglass_top_rounded,
              color: statusColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  org,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 12, color: t.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Badges (earned, computed server-side) ────────────────────────────────────

/// Your own badges, including the ones still locked so you can see what is
/// available to earn. The server decides what is earned — see `lib/badges.ts`.
class _BadgesSection extends StatelessWidget {
  final NeedHubTokens t;

  const _BadgesSection({required this.t});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileMe?>(
      valueListenable: myProfileNotifier,
      builder: (_, profile, __) {
        final badges = profile?.badges ?? const <ProfileBadge>[];
        final earned = badges.where((b) => b.earned).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (badges.isNotEmpty) ...[
              Text(
                '$earned of ${badges.length} earned',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: 10),
            ],
            NhBadgeRow(badges: badges, t: t),
          ],
        );
      },
    );
  }
}

// ── Skill vouches (read-only on your own profile) ────────────────────────────

/// Own profile is view-only: you cannot vouch for your own skills, so this
/// renders NhSkillVouchSection without an onVouch callback at all — the
/// section then has no Vouch/Edit affordance to show, same widget used on
/// person_screen.dart, just without the action.
class _SkillVouchesSection extends StatelessWidget {
  final NeedHubTokens t;

  const _SkillVouchesSection({required this.t});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileMe?>(
      valueListenable: myProfileNotifier,
      builder: (_, profile, __) {
        return NhSkillVouchSection(
          skills: profile?.skillEntries ?? const [],
          skillVouches: profile?.skillVouches ?? const {},
          t: t,
        );
      },
    );
  }
}

// ── Impact League (rank teaser, seasonal badges, achievement showcase) ──────

/// Own profile only. Seasonal badges and milestone achievements come from
/// the same profile fetch that already loaded [myProfileNotifier] (see
/// ProfileMe.seasonalBadges / .leagueAchievements) — no extra call needed.
/// Current rank is genuinely live (it changes as the season progresses), so
/// that alone is fetched separately from lib/impact-league.ts's /league/me.
class _ImpactLeagueSection extends ConsumerStatefulWidget {
  const _ImpactLeagueSection();

  @override
  ConsumerState<_ImpactLeagueSection> createState() => _ImpactLeagueSectionState();
}

class _ImpactLeagueSectionState extends ConsumerState<_ImpactLeagueSection> {
  bool _loading = true;
  MyRank? _rank;
  bool _busy = false;
  /// Optimistic local override after a successful feature/unfeature save —
  /// avoids reconstructing the entire (30+ field) ProfileMe just to update
  /// one list. Cleared automatically whenever the profile notifier itself
  /// refreshes with newer data.
  List<String>? _featuredOverride;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRank());
  }

  Future<void> _loadRank() async {
    try {
      final rank = await ref.read(leagueApiProvider).myRank();
      if (mounted) setState(() { _rank = rank; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFeatured(String id, List<String> current) async {
    if (_busy) return;
    final isFeatured = current.contains(id);
    if (!isFeatured && current.length >= 3) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(S.current.featuredLimitReached)));
      return;
    }
    final next = isFeatured ? current.where((x) => x != id).toList() : [...current, id];
    setState(() => _busy = true);
    try {
      final saved = await ref.read(leagueApiProvider).setFeatured(next);
      if (mounted) setState(() => _featuredOverride = saved);
    } catch (_) {
      // Leave state as-is — a failed save just means the toggle didn't stick.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final rank = _rank;

    return ValueListenableBuilder<ProfileMe?>(
      valueListenable: myProfileNotifier,
      builder: (_, profile, __) => _buildBody(context, t, s, rank, profile),
    );
  }

  Widget _buildBody(BuildContext context, NeedHubTokens t, S s, MyRank? rank, ProfileMe? profile) {
    final seasonalBadges = profile?.seasonalBadges ?? const <SeasonalBadge>[];
    final achievements = profile?.leagueAchievements ?? const <LeagueAchievement>[];
    final featuredIds = _featuredOverride ?? profile?.featuredAchievementIds ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ImpactLeagueScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.rail, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: NeedHubTokens.forest.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.leaderboard_rounded, color: NeedHubTokens.forest, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rank?.rank != null ? '#${rank!.rank} ${s.impactLeague}' : s.impactLeague,
                        style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w800, color: t.ink),
                      ),
                      Text(
                        rank != null && rank.seasonPoints > 0
                            ? '${rank.seasonPoints} ${s.impactPointsThisSeason}'
                            : s.notRankedYet,
                        style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: t.muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: t.muted),
              ],
            ),
          ),
        ),
        if (seasonalBadges.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            s.seasonalBadges,
            style: GoogleFonts.hankenGrotesk(fontSize: 10.5, fontWeight: FontWeight.w700, color: t.muted2, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          NhSeasonalBadgeRow(badges: seasonalBadges, t: t),
        ],
        if (achievements.any((a) => a.earned)) ...[
          const SizedBox(height: 14),
          Text(
            s.leagueAchievements,
            style: GoogleFonts.hankenGrotesk(fontSize: 10.5, fontWeight: FontWeight.w700, color: t.muted2, letterSpacing: 0.5),
          ),
          const SizedBox(height: 4),
          Text(
            s.leagueAchievementsDesc,
            style: GoogleFonts.hankenGrotesk(fontSize: 11.5, color: t.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: earnedAchievementsChronological(achievements).map((a) {
              final featured = featuredIds.contains(a.id);
              return GestureDetector(
                onTap: () => _toggleFeatured(a.id, featuredIds),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: featured ? NeedHubTokens.forest.withValues(alpha: 0.12) : t.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: featured ? NeedHubTokens.forest : t.rail, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (featured) const Icon(Icons.star_rounded, size: 14, color: NeedHubTokens.forest),
                      if (featured) const SizedBox(width: 4),
                      Text(
                        a.label,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: featured ? NeedHubTokens.forest : t.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

// ── Achievements row (seal-style) ─────────────────────────────────────────────

class _AchievementsRow extends StatelessWidget {
  final NeedHubTokens t;

  const _AchievementsRow({required this.t});

  static const _plum = Color(0xFF6B3FA0);

  static IconData _iconFor(String category) {
    switch (category) {
      case 'HACKATHON': return Icons.rocket_launch_outlined;
      case 'COMPETITION': return Icons.emoji_events_outlined;
      case 'TOURNAMENT': return Icons.sports_esports_outlined;
      case 'AWARD': return Icons.workspace_premium_outlined;
      default: return Icons.star_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<MyAchievement>>(
      valueListenable: myAchievementsNotifier,
      builder: (_, real, __) {
        // Only real, user-submitted achievements. This row used to pad itself
        // with five hardcoded placeholders when a user had none, three of them
        // marked as earned — so every new account displayed achievements it
        // had not earned. Earned badges are a separate, server-computed thing
        // (see NhBadgeRow); this row is strictly uploaded certificates.
        final items = real
            .map((a) => (
                  icon: _iconFor(a.category),
                  label:
                      a.title.length > 12 ? a.title.substring(0, 12) : a.title,
                  earned: a.status == 'APPROVED',
                ))
            .toList();

        if (items.isEmpty) {
          return Text(
            'Nothing submitted yet — add a certificate or competition win above.',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: t.muted,
            ),
          );
        }

        return SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final item = items[i];
              final color = item.earned ? _plum : t.muted;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: item.earned
                      ? _plum.withValues(alpha: 0.12)
                      : t.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: item.earned
                        ? _plum.withValues(alpha: 0.30)
                        : t.rail,
                    width: 1.5,
                  ),
                ),
                child: Icon(item.icon, color: color, size: 24),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 60,
                child: Text(
                  item.label,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
        );
      },
    );
  }
}

// ── Collapsible section (dropdown) ────────────────────────────────────────────

/// A titled section whose content is hidden behind a tap, so a long profile
/// page doesn't dump everything on screen at once. Collapsed by default —
/// the header (and subtitle, if given) always stay visible so it's still
/// obvious what's inside before expanding it.
class _CollapsibleSection extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final NeedHubTokens t;

  const _CollapsibleSection({
    required this.title,
    this.subtitle,
    required this.child,
    required this.t,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.muted2,
                        letterSpacing: 0.7,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle!,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12.5, color: t.muted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: t.muted,
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 14),
          widget.child,
        ],
      ],
    );
  }
}

// ── Quick link card ───────────────────────────────────────────────────────────

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final NeedHubTokens t;
  final VoidCallback onTap;

  const _QuickLink({
    required this.icon,
    required this.label,
    required this.color,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: color.withValues(alpha: 0.20), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Interest / skill chip ─────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final NeedHubTokens t;
  final Color color;

  const _Chip({required this.label, required this.t, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Text(
        label,
        style: GoogleFonts.hankenGrotesk(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Prompt card ───────────────────────────────────────────────────────────────

class _PromptCard extends StatelessWidget {
  final String q;
  final String a;
  final NeedHubTokens t;

  const _PromptCard({required this.q, required this.a, required this.t});

  @override
  Widget build(BuildContext context) {
    final isEmpty = a.trim().isEmpty || a == '—';
    final s = S.current;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EditProfileScreen()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: isEmpty
              ? Border.all(color: t.rail, width: 1.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              q,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            if (isEmpty)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.tapToAnswerPrompt,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13.5,
                        fontStyle: FontStyle.italic,
                        color: t.muted,
                      ),
                    ),
                  ),
                  const Icon(Icons.add_circle_outline_rounded,
                      size: 18, color: NeedHubTokens.forest),
                ],
              )
            else
              Text(
                a,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 14,
                  color: t.ink,
                  height: 1.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Face Verification Section ─────────────────────────────────────────────────

class _FaceVerifySection extends ConsumerStatefulWidget {
  final NeedHubTokens t;
  const _FaceVerifySection({required this.t});

  @override
  ConsumerState<_FaceVerifySection> createState() => _FaceVerifySectionState();
}

class _FaceVerifySectionState extends ConsumerState<_FaceVerifySection> {
  bool _verifying = false;

  Future<void> _startVerification() async {
    if (_verifying) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1280,
      maxHeight: 1280,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null || !mounted) return;

    setState(() => _verifying = true);
    try {
      final api = ref.read(apiClientProvider);
      final form = FormData.fromMap({
        'selfie': await MultipartFile.fromFile(
          file.path,
          filename: 'selfie.jpg',
        ),
      });
      await api.postForm('/profile/me/face-verify', form);

      // Refresh the profile so faceVerifiedAt is updated
      try {
        final profilesApi = ref.read(profilesApiProvider);
        myProfileNotifier.value = await profilesApi.me();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Face verified! Badge now appears on your connect needs'),
          ),
        );
        setState(() {});
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      final reason = (data is Map ? data['reason'] : null) as String? ??
          'Verification failed. Please retake in good lighting.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final s = S.current;
    return ValueListenableBuilder<ProfileMe?>(
      valueListenable: myProfileNotifier,
      builder: (_, me, __) {
        final isVerified = me?.faceVerifiedAt != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.faceVerification,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted2,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isVerified
                    ? NeedHubTokens.forest.withValues(alpha: 0.06)
                    : t.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isVerified
                      ? NeedHubTokens.forest.withValues(alpha: 0.30)
                      : t.rail,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isVerified
                          ? NeedHubTokens.forest.withValues(alpha: 0.12)
                          : t.chip,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isVerified
                          ? Icons.verified_user_rounded
                          : Icons.face_retouching_natural_rounded,
                      color: isVerified ? NeedHubTokens.forest : t.muted2,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isVerified ? s.faceVerified : s.verifyYourFace,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isVerified ? NeedHubTokens.forest : t.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isVerified
                              ? 'Verified badge shown on your connect needs'
                              : 'Upload a clear photo of your face to get a verified badge on your connect needs',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            color: t.muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isVerified) ...[
                    const SizedBox(width: 8),
                    _verifying
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: NeedHubTokens.forest,
                            ),
                          )
                        : GestureDetector(
                            onTap: _startVerification,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: NeedHubTokens.forest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.camera_alt_rounded,
                                      size: 14, color: Colors.white),
                                  const SizedBox(width: 5),
                                  Text(
                                    s.takeSelfie,
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Trust Score Section ─────────────────────────────────────────────────────
// Trust Score (0-100) blends identity verification — email (least, it's
// compulsory), face, phone (most, hardest to fake) — with real track record:
// approved certificates, fulfilled needs, and review rating. Shown here and
// on Connect cards so people meeting strangers have a real safety signal.

class _TrustScoreSection extends StatelessWidget {
  final NeedHubTokens t;
  const _TrustScoreSection({required this.t});

  Color _colorFor(int score) {
    if (score >= 70) return NeedHubTokens.forest;
    if (score >= 40) return NeedHubTokens.clay;
    return const Color(0xFF9CA3AF);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    return ValueListenableBuilder<ProfileMe?>(
      valueListenable: myProfileNotifier,
      builder: (_, me, __) {
        final score = me?.trustScore ?? 0;
        final color = _colorFor(score);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.trustScore,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted2,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.rail, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.shield_rounded, color: color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$score',
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: color,
                          height: 1,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 3),
                        child: Text('/ 100',
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 12, color: t.muted)),
                      ),
                      const Spacer(),
                      Text(
                        s.shownOnConnectCards,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 11,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: score / 100,
                      minHeight: 6,
                      backgroundColor: t.rail,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TrustChip(label: 'Email', done: me?.emailVerifiedAt != null),
                      _TrustChip(label: 'Phone', done: me?.phoneVerifiedAt != null),
                      _TrustChip(label: 'Face', done: me?.faceVerifiedAt != null),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.trustScoreGrows,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11.5,
                      color: t.muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrustChip extends StatelessWidget {
  final String label;
  final bool done;
  const _TrustChip({required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    final color = done ? NeedHubTokens.forest : const Color(0xFF9CA3AF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Phone Verification Section ────────────────────────────────────────────────

class _PhoneVerifySection extends ConsumerStatefulWidget {
  final NeedHubTokens t;
  const _PhoneVerifySection({required this.t});

  @override
  ConsumerState<_PhoneVerifySection> createState() => _PhoneVerifySectionState();
}

class _PhoneVerifySectionState extends ConsumerState<_PhoneVerifySection> {
  Future<void> _openSheet() async {
    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PhoneVerifySheet(),
    );
    if (verified == true) {
      try {
        final profilesApi = ref.read(profilesApiProvider);
        myProfileNotifier.value = await profilesApi.me();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final s = S.current;
    return ValueListenableBuilder<ProfileMe?>(
      valueListenable: myProfileNotifier,
      builder: (_, me, __) {
        final isVerified = me?.phoneVerifiedAt != null;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isVerified ? NeedHubTokens.forest.withValues(alpha: 0.06) : t.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isVerified ? NeedHubTokens.forest.withValues(alpha: 0.30) : t.rail,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isVerified
                      ? NeedHubTokens.forest.withValues(alpha: 0.12)
                      : t.chip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isVerified ? Icons.verified_user_rounded : Icons.phone_iphone_rounded,
                  color: isVerified ? NeedHubTokens.forest : t.muted2,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isVerified ? s.phoneVerified : s.verifyYourPhone,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isVerified ? NeedHubTokens.forest : t.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isVerified
                          ? (me?.phone ?? 'Boosts your trust score')
                          : 'Adds the biggest boost to your trust score',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 12,
                        color: t.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isVerified) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _openSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: NeedHubTokens.forest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sms_rounded, size: 14, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(
                          s.verify,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Two-step bottom sheet: enter phone → send OTP → enter 6-digit code → verify.
/// Pops `true` on success so the caller can refresh the profile.
class _PhoneVerifySheet extends ConsumerStatefulWidget {
  const _PhoneVerifySheet();

  @override
  ConsumerState<_PhoneVerifySheet> createState() => _PhoneVerifySheetState();
}

class _PhoneVerifySheetState extends ConsumerState<_PhoneVerifySheet> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!RegExp(r'^\+?[1-9]\d{7,14}$').hasMatch(phone)) {
      setState(() => _error = 'Enter a valid number with country code, e.g. +919876543210');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(profilesApiProvider);
      final res = await api.sendPhoneOtp(phone);
      final devOtp = res['devOtp'] as String?;
      if (devOtp != null) _codeController.text = devOtp; // demo auto-fill, same as email OTP
      if (mounted) setState(() => _codeSent = true);
    } on DioException catch (e) {
      final data = e.response?.data;
      setState(() => _error = (data is Map ? data['error'] : null) as String? ?? 'Could not send code');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(profilesApiProvider);
      await api.verifyPhoneOtp(code);
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final data = e.response?.data;
      setState(() => _error = (data is Map ? data['error'] : null) as String? ?? 'Incorrect code');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: BoxDecoration(
          color: t.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 16),
            Text(
              _codeSent ? 'Enter the code' : 'Verify your phone',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: t.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _codeSent
                  ? 'We sent a 6-digit code to ${_phoneController.text.trim()}'
                  : 'Enter your number with country code — this adds the biggest boost to your trust score.',
              style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            if (!_codeSent)
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                autofocus: true,
                style: GoogleFonts.hankenGrotesk(fontSize: 15, color: t.ink),
                decoration: InputDecoration(
                  hintText: '+919876543210',
                  hintStyle: GoogleFonts.hankenGrotesk(color: t.muted),
                  filled: true,
                  fillColor: t.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: t.rail),
                  ),
                ),
              )
            else
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                autofocus: true,
                maxLength: 6,
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 22, letterSpacing: 8, color: t.ink, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  filled: true,
                  fillColor: t.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: t.rail),
                  ),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: GoogleFonts.hankenGrotesk(fontSize: 12.5, color: Colors.red)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : (_codeSent ? _verifyCode : _sendCode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NeedHubTokens.forest,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _codeSent ? s.verify : 'Send code',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
              ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : _sendCode,
                  child: Text('Resend code',
                      style: GoogleFonts.hankenGrotesk(fontSize: 12.5, color: t.muted)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── My Posted Needs & History Section ─────────────────────────────────────────

class _MyPostedNeedsSection extends ConsumerStatefulWidget {
  final NeedHubTokens t;
  const _MyPostedNeedsSection({required this.t});

  @override
  ConsumerState<_MyPostedNeedsSection> createState() => _MyPostedNeedsSectionState();
}

class _MyPostedNeedsSectionState extends ConsumerState<_MyPostedNeedsSection> {
  String _filter = 'all'; // 'all' | 'connect' | 'earn'
  List<Need> _apiPostedNeeds = [];
  static const int _collapsedCount = 2;
  bool _showAllNeeds = false;

  @override
  void initState() {
    super.initState();
    needsNotifier.addListener(_onNeedsChanged);
    ratingsGivenNotifier.addListener(_rebuild);
    feedNeedsNotifier.addListener(_onNeedsChanged);
    Future.microtask(_fetchMine);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refetch every time the You tab becomes visible again.
    Future.microtask(_fetchMine);
  }

  @override
  void dispose() {
    needsNotifier.removeListener(_onNeedsChanged);
    ratingsGivenNotifier.removeListener(_rebuild);
    feedNeedsNotifier.removeListener(_onNeedsChanged);
    super.dispose();
  }

  void _rebuild() => setState(() {});
  void _onNeedsChanged() {
    _fetchMine();
    if (mounted) setState(() {});
  }

  Future<void> _fetchMine() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/needs/mine/list');
      final list = ((res['needs'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _apiPostedNeeds = list.map((j) {
          final needType = (j['needType'] as String? ?? 'CONNECT').toLowerCase();
          final category = needType == 'earn' ? 'earn' : 'connect';
          final createdIso = j['createdAt'] as String?;
          return Need(
            id: j['id'] as String,
            posterId: j['posterId'] as String? ?? '',
            title: j['title'] as String? ?? '',
            description: j['description'] as String? ?? '',
            category: category,
            authorName: 'You',
            authorInitials: 'ME',
            location: j['locationText'] as String? ?? 'Nearby',
            createdAt: createdIso != null ? (DateTime.tryParse(createdIso) ?? DateTime.now()) : DateTime.now(),
            budgetMin: (j['budgetMin'] as num?)?.toInt(),
            budgetMax: (j['budgetMax'] as num?)?.toInt(),
          );
        }).toList();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final s = S.current;
    final localMine = feedNeedsNotifier.value.where((n) => n.authorName == 'You' || n.authorInitials == 'ME').toList();

    // Merge API posted needs + local mine
    final Map<String, Need> map = {};
    for (final n in _apiPostedNeeds) {
      map[n.id] = n;
    }
    for (final n in localMine) {
      if (!map.containsKey(n.id)) {
        map[n.id] = n;
      }
    }
    final allMine = map.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final filtered = _filter == 'all'
        ? allMine
        : allMine.where((n) => n.category.toLowerCase() == _filter).toList();

    final connectCount = allMine.where((n) => n.category.toLowerCase() == 'connect').length;
    final earnCount = allMine.where((n) => n.category.toLowerCase() == 'earn').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              s.myPostedNeeds,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted2,
                letterSpacing: 0.7,
              ),
            ),
            const Spacer(),
            Text(
              '${allMine.length} Total',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: NeedHubTokens.clay,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Filter chips: All, Connect, Earn
        Row(
          children: [
            _HistoryChip(
              label: 'All (${allMine.length})',
              selected: _filter == 'all',
              onTap: () => setState(() { _filter = 'all'; _showAllNeeds = false; }),
              t: t,
            ),
            const SizedBox(width: 8),
            _HistoryChip(
              label: 'Connect ($connectCount)',
              selected: _filter == 'connect',
              onTap: () => setState(() { _filter = 'connect'; _showAllNeeds = false; }),
              t: t,
              color: NeedHubTokens.forest,
            ),
            const SizedBox(width: 8),
            _HistoryChip(
              label: 'Earn ($earnCount)',
              selected: _filter == 'earn',
              onTap: () => setState(() { _filter = 'earn'; _showAllNeeds = false; }),
              t: t,
              color: NeedHubTokens.ochre,
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (filtered.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.rail, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.assignment_outlined, size: 24, color: t.muted2),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.noPostedNeeds,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: t.ink,
                        ),
                      ),
                      Text(
                        'Needs you post will appear here with status, offers & feedback',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 11.5,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else ...[
          Column(
            children: (_showAllNeeds ? filtered : filtered.take(_collapsedCount).toList())
                .map((n) => _PostedNeedCard(need: n, t: t))
                .toList(),
          ),
          if (filtered.length > _collapsedCount)
            GestureDetector(
              onTap: () => setState(() => _showAllNeeds = !_showAllNeeds),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _showAllNeeds
                          ? 'Show less'
                          : 'Show ${filtered.length - _collapsedCount} more',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: NeedHubTokens.clay,
                      ),
                    ),
                    Icon(
                      _showAllNeeds
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: NeedHubTokens.clay,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _HistoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final NeedHubTokens t;
  final Color? color;

  const _HistoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.t,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? NeedHubTokens.clay;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? activeColor.withValues(alpha: 0.14) : t.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? activeColor : t.rail,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? activeColor : t.muted,
          ),
        ),
      ),
    );
  }
}

class _PostedNeedCard extends StatelessWidget {
  final Need need;
  final NeedHubTokens t;

  const _PostedNeedCard({required this.need, required this.t});

  @override
  Widget build(BuildContext context) {
    final isEarn = need.category.toLowerCase() == 'earn';
    final catColor = isEarn ? NeedHubTokens.ochre : NeedHubTokens.forest;
    final offersCount = need.totalOfferCount;
    final rating = ratingsGivenNotifier.value[need.title] ?? ratingsGivenNotifier.value[need.id];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => NeedDetailScreen(need: need)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.rail, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                offset: const Offset(0, 2),
                blurRadius: 6,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isEarn ? 'EARN' : 'CONNECT',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: catColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: NeedHubTokens.forest.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'ACTIVE',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: NeedHubTokens.forest,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    need.timeAgo,
                    style: GoogleFonts.hankenGrotesk(fontSize: 11, color: t.muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                need.title,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                need.description,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 12.5,
                  color: t.muted,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.local_offer_outlined, size: 14, color: catColor),
                  const SizedBox(width: 4),
                  Text(
                    '$offersCount ${offersCount == 1 ? 'offer received' : 'offers received'}',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: catColor,
                    ),
                  ),
                  const Spacer(),
                  if (rating != null) ...[
                    const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(
                      '$rating.0 / 5.0 Rating',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Tap to view details →',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: t.muted2,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserReviewsSheet extends StatelessWidget {
  final double avg;
  final int count;
  final List<Map<String, dynamic>> reviews;

  const _UserReviewsSheet({
    required this.avg,
    required this.count,
    required this.reviews,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.rail,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                s.ratingsAndReviews,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: t.ink,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAB308).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 16, color: Color(0xFFEAB308)),
                    const SizedBox(width: 4),
                    Text(
                      '${avg.toStringAsFixed(1)} ($count)',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: reviews.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final rev = reviews[index];
                final reviewer =
                    rev['reviewer'] as Map<String, dynamic>? ?? {};
                final reviewerProfile =
                    reviewer['profile'] as Map<String, dynamic>?;
                final reviewerName =
                    reviewer['displayName'] as String? ?? 'User';
                final rating = (rev['rating'] as num?)?.toInt() ?? 5;
                final comment = rev['comment'] as String?;
                final need = rev['need'] as Map<String, dynamic>?;
                final needTitle = need?['title'] as String?;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.rail, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ClipOval(
                            child: reviewerProfile?['avatarUrl'] != null
                                ? Image.network(
                                    reviewerProfile!['avatarUrl'] as String,
                                    width: 32,
                                    height: 32,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 32,
                                      height: 32,
                                      color: t.rail2,
                                      alignment: Alignment.center,
                                      child: Text(
                                        reviewerName.isNotEmpty
                                            ? reviewerName[0]
                                            : '?',
                                        style: GoogleFonts.hankenGrotesk(
                                          fontSize: 12,
                                          color: t.muted4,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 32,
                                    height: 32,
                                    color: t.rail2,
                                    alignment: Alignment.center,
                                    child: Text(
                                      reviewerName.isNotEmpty
                                          ? reviewerName[0]
                                          : '?',
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 12,
                                        color: t.muted4,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reviewerName,
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: t.ink,
                                  ),
                                ),
                                if (needTitle != null &&
                                    needTitle.isNotEmpty)
                                  Text(
                                    'For: $needTitle',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 11.5,
                                      color: t.muted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          Row(
                            children: List.generate(
                              5,
                              (i) => Icon(
                                i < rating
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 14,
                                color: i < rating
                                    ? const Color(0xFFEAB308)
                                    : t.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (comment != null && comment.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          comment,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 12.5,
                            color: t.ink,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Personality Section ───────────────────────────────────────────────────────

class _PersonalitySection extends StatelessWidget {
  final NeedHubTokens t;
  const _PersonalitySection({required this.t});

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              s.personality,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted2,
                letterSpacing: 0.7,
              ),
            ),
            const Spacer(),
            ValueListenableBuilder<PersonalityProfile?>(
              valueListenable: myPersonalityNotifier,
              builder: (_, p, __) => p != null
                  ? GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PersonalityResultScreen(profile: p),
                        ),
                      ),
                      child: Text(
                        'View full results →',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: NeedHubTokens.clay,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder<PersonalityProfile?>(
          valueListenable: myPersonalityNotifier,
          builder: (_, profile, __) {
            if (profile == null) {
              return GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PersonalityTestScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: NeedHubTokens.clay.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: NeedHubTokens.clay.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: NeedHubTokens.clay.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.psychology_outlined,
                          color: NeedHubTokens.clay,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.takePersonalityTest,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: t.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              s.poweredByLyzr,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 12,
                                color: t.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 14, color: t.muted2),
                    ],
                  ),
                ),
              );
            }

            return GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PersonalityResultScreen(profile: profile),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      NeedHubTokens.clay,
                      NeedHubTokens.clay.withValues(alpha: 0.78),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'YOU ARE',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                profile.nickname,
                                style: GoogleFonts.bricolageGrotesque(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.7)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      profile.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.4,
                      ),
                    ),
                    if (profile.vibeTags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: profile.vibeTags.take(4).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              tag,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Refer a Friend card ───────────────────────────────────────────────────────

class _ReferAFriendCard extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final NeedHubTokens t;
  const _ReferAFriendCard({required this.ref, required this.t});

  @override
  ConsumerState<_ReferAFriendCard> createState() => _ReferAFriendCardState();
}

class _ReferAFriendCardState extends ConsumerState<_ReferAFriendCard> {
  ReferralMe? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(referralsApiProvider).me();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _share() {
    final code = _data?.referralCode ?? '';
    if (code.isEmpty) return;
    Share.share(
      'Join me on NeedHub! Sign up with my code $code and both of us earn 15 bonus points when you post your first need.\n\nhttps://play.google.com/store/apps/details?id=com.needhub.app',
      subject: 'Join me on NeedHub',
    );
  }

  void _copyCode() {
    final code = _data?.referralCode ?? '';
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Referral code copied!'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final s = S.current;
    final code = _data?.referralCode ?? '------';
    final stats = _data?.stats;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [NeedHubTokens.forest, NeedHubTokens.forest.withValues(alpha: 0.80)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: _loading
          ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      s.referAFriend,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    if (stats != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${stats.activated}/${stats.total} active',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  s.referralDesc,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                // Code pill
                GestureDetector(
                  onTap: _copyCode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          code,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.copy_rounded, color: Colors.white.withValues(alpha: 0.7), size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _share,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.share_rounded, size: 16, color: NeedHubTokens.forest),
                          const SizedBox(width: 8),
                          Text(
                            s.shareYourCode,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: NeedHubTokens.forest,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (stats != null && stats.pointsEarned > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${stats.pointsEarned} pts earned from referrals so far',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ProfileQrSheet extends StatelessWidget {
  final AuthState auth;
  final NeedHubTokens t;

  const _ProfileQrSheet({required this.auth, required this.t});

  static String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = avatarUrlNotifier.value;
    final name = auth.displayName ?? auth.email ?? 'You';
    final initials = _getInitials(name);

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.muted.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Header info
          Row(
            children: [
              NhAvatar(
                avatarUrl: avatarUrl,
                initials: initials,
                size: 54,
                borderRadius: 18,
                backgroundColor: NeedHubTokens.forest,
                fontSize: 20,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    ValueListenableBuilder<ProfileMe?>(
                      valueListenable: myProfileNotifier,
                      builder: (_, me, __) => Text(
                        me?.username != null ? '@${me!.username}' : auth.email ?? '',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // QR Code Card
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: QrImageView(
                data: 'needhub:profile:${auth.userId}',
                version: QrVersions.auto,
                size: 200,
                gapless: false,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Scan code in real life or share profile link online',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 13,
              color: t.muted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          
          // Actions
          Text(
            'Share via:',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: t.ink,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ShareAppButton(
                icon: Icons.chat_bubble_rounded,
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                onTap: () async {
                  final shareText = 'Add me as a friend on NeedHub! Open the app and scan or look up my ID: needhub:profile:${auth.userId}';
                  final url = 'https://api.whatsapp.com/send?text=${Uri.encodeComponent(shareText)}';
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    await Clipboard.setData(ClipboardData(text: shareText));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied link! Please paste it in WhatsApp.')),
                      );
                    }
                  }
                },
              ),
              _ShareAppButton(
                icon: Icons.photo_camera_rounded,
                label: 'Instagram',
                color: const Color(0xFFE1306C),
                onTap: () async {
                  final shareText = 'Add me as a friend on NeedHub! Open the app and scan or look up my ID: needhub:profile:${auth.userId}';
                  await Clipboard.setData(ClipboardData(text: shareText));
                  final uri = Uri.parse('https://instagram.com');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied link! Opening Instagram...')),
                    );
                  }
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              _ShareAppButton(
                icon: Icons.mail_rounded,
                label: 'Gmail',
                color: const Color(0xFFEA4335),
                onTap: () async {
                  final shareText = 'Add me as a friend on NeedHub! Open the app and scan or look up my ID: needhub:profile:${auth.userId}';
                  final url = 'mailto:?subject=${Uri.encodeComponent('Join me on NeedHub')}&body=${Uri.encodeComponent(shareText)}';
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  } else {
                    await Clipboard.setData(ClipboardData(text: shareText));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied link! Please paste it in your email app.')),
                      );
                    }
                  }
                },
              ),
              _ShareAppButton(
                icon: Icons.content_copy_rounded,
                label: 'Copy Link',
                color: t.muted,
                onTap: () async {
                  final shareText = 'needhub:profile:${auth.userId}';
                  await Clipboard.setData(ClipboardData(text: shareText));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profile link copied to clipboard!')),
                    );
                  }
                },
              ),
              _ShareAppButton(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                color: NeedHubTokens.clay,
                onTap: () {
                  SharePlus.instance.share(
                    ShareParams(
                      text: 'Add me as a friend on NeedHub! Open the app and scan or look up my ID: needhub:profile:${auth.userId}',
                      subject: 'My NeedHub Profile',
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: t.ink,
              side: BorderSide(color: t.muted.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: Text(
              "Scan a Friend's QR",
              style: GoogleFonts.hankenGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const QrScannerScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShareAppButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ShareAppButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: t.ink,
            ),
          ),
        ],
      ),
    );
  }
}
