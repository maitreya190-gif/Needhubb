import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/person.dart';
import '../../models/user_state.dart';
import '../../providers/auth_provider.dart';
import '../../services/friends_api.dart';
import '../../services/profiles_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_avatar.dart';
import '../../widgets/nh_report_sheet.dart';
import '../history/history_screen.dart';

class PersonScreen extends ConsumerStatefulWidget {
  final String name;
  final String initials;
  final Color avatarColor;
  final String? location;
  final String? subtitle;
  /// When provided, real profile data is fetched from GET /profile/:userId
  /// and merges over the mock lookup — the mock stays as a fallback so the
  /// UI is never empty while the network call is inflight.
  final String? avatarUrl;
  final String? userId;

  const PersonScreen({
    super.key,
    required this.name,
    required this.initials,
    required this.avatarColor,
    this.avatarUrl,
    this.location,
    this.subtitle,
    this.userId,
  });

  static Route<void> route({
    required String name,
    required String initials,
    required Color avatarColor,
    String? avatarUrl,
    String? location,
    String? subtitle,
    String? userId,
  }) {
    return MaterialPageRoute(
      builder: (_) => PersonScreen(
        name: name,
        initials: initials,
        avatarColor: avatarColor,
        avatarUrl: avatarUrl,
        location: location,
        subtitle: subtitle,
        userId: userId,
      ),
    );
  }

  @override
  ConsumerState<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends ConsumerState<PersonScreen> {
  Person? _real;

  @override
  void initState() {
    super.initState();
    if (widget.userId != null) Future.microtask(_hydrate);
  }

  Future<void> _hydrate() async {
    try {
      final api = ref.read(profilesApiProvider);
      final me = await api.getById(widget.userId!);
      if (!mounted) return;
      setState(() => _real = _toPerson(me, widget.avatarColor));
    } catch (_) {/* keep the mock fallback */}
  }

  static Person _toPerson(ProfileMe m, Color color) {
    return Person(
      id: m.id,
      name: m.displayName,
      initials: _initialsOf(m.displayName),
      avatarColor: color,
      avatarUrl: m.avatarUrl,
      location: m.locationText ?? 'Nearby',
      distanceKm: 0,
      interests: m.interestLabels,
      skills: m.skillLabels,
      myInterests: customInterestsNotifier.value,
      promptQ1: 'What I bring',
      promptA1: m.promptSkill ?? '—',
      promptQ2: "What I'm looking for",
      promptA2: m.promptNeed ?? '—',
      promptQ3: 'Ideal collab',
      promptA3: m.promptCollab ?? '—',
      reviewCount: 0,
      points: m.pointsTotal,
    );
  }

  static String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  // Shortcut aliases so the existing build() body reads unchanged.
  String get name => widget.name;
  String get initials => widget.initials;
  Color get avatarColor => widget.avatarColor;
  String? get location => widget.location;
  String? get subtitle => widget.subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Prefer real profile hydrated from API; fall back to the mock lookup.
    final person = _real ?? mockPersonLookup[name];
    return Scaffold(
      backgroundColor: t.paper,
      body: CustomScrollView(
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back + Report row
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => NhReportSheet.open(
                            context,
                            targetName: name,
                            targetType: widget.userId != null ? 'USER' : null,
                            targetId: widget.userId,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.flag_outlined,
                                    size: 14, color: t.onDark),
                                const SizedBox(width: 5),
                                Text(
                                  'Report',
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
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Avatar + name
                    Row(
                      children: [
                        NhAvatar(
                          avatarUrl: person?.avatarUrl ?? widget.avatarUrl ?? mockPersonLookup[name]?.avatarUrl,
                          initials: initials,
                          size: 70,
                          borderRadius: 22,
                          backgroundColor: avatarColor,
                          fontSize: 26,
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.bricolageGrotesque(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: t.onDark,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle!,
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 12.5,
                                    color: t.onDarkMuted,
                                  ),
                                ),
                              ],
                              if (location != null) ...[
                                Text(
                                  location!,
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 12,
                                    color: t.onDarkMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Incoming friend request decision banner
                    ValueListenableBuilder<List<FriendRequestDto>>(
                      valueListenable: friendRequestsInboxNotifier,
                      builder: (context, inbox, _) {
                        FriendRequestDto? matchingReq;
                        for (final r in inbox) {
                          if ((widget.userId != null && (r.fromUserId == widget.userId || r.id == widget.userId)) ||
                              (r.otherDisplayName != null && r.otherDisplayName!.toLowerCase() == name.toLowerCase())) {
                            matchingReq = r;
                            break;
                          }
                        }

                        if (matchingReq != null) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: NeedHubTokens.forest.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: NeedHubTokens.forest, width: 1.5),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.person_add_rounded, color: NeedHubTokens.forest, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$name sent you a friend request!',
                                        style: GoogleFonts.hankenGrotesk(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () async {
                                          try {
                                            final api = ref.read(friendsApiProvider);
                                            await acceptFriendRequest(matchingReq!.id, api);
                                            addFriend(name);
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Accepted friend request from $name!')),
                                              );
                                            }
                                          } catch (_) {
                                            addFriend(name);
                                          }
                                        },
                                        icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                                        label: const Text('Accept Request'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: NeedHubTokens.forest,
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size.fromHeight(38),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () async {
                                          try {
                                            final api = ref.read(friendsApiProvider);
                                            await declineFriendRequest(matchingReq!.id, api);
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Friend request declined.')),
                                              );
                                            }
                                          } catch (_) {}
                                        },
                                        icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                                        label: const Text('Decline'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white70,
                                          minimumSize: const Size.fromHeight(38),
                                          side: const BorderSide(color: Colors.white30),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),

                    // Friend + block status row
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: blockedNotifier,
                      builder: (_, blocked, __) {
                        final isBlocked = blocked.contains(name);
                        return ValueListenableBuilder<Set<String>>(
                          valueListenable: friendsNotifier,
                          builder: (_, friends, __) {
                            final isFriend = friends.contains(name);
                            return Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: isBlocked
                                        ? null
                                        : () {
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
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    label: Text(
                                      isFriend
                                          ? 'Remove friend'
                                          : 'Add friend',
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(42),
                                      side: BorderSide(
                                          color: Colors.white
                                              .withValues(alpha: 0.30),
                                          width: 1.5),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      if (isBlocked) {
                                        unblockUser(name);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(
                                                    '$name unblocked')));
                                      } else {
                                        blockUser(name);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(
                                                    '$name blocked')));
                                      }
                                    },
                                    icon: Icon(
                                      isBlocked
                                          ? Icons.lock_open_rounded
                                          : Icons.block_rounded,
                                      size: 16,
                                      color: isBlocked
                                          ? Colors.white
                                          : Colors.red.shade200,
                                    ),
                                    label: Text(
                                      isBlocked ? 'Unblock' : 'Block',
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: isBlocked
                                            ? Colors.white
                                            : Colors.red.shade200,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(42),
                                      side: BorderSide(
                                          color: (isBlocked
                                                  ? Colors.white
                                                  : Colors.red.shade200)
                                              .withValues(alpha: 0.35),
                                          width: 1.5),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Body
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Impact
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: t.surfaceDark,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RELIABILITY POINTS',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                            color: t.onDarkMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          person != null ? '${person.points}' : '—',
                          style: GoogleFonts.bricolageGrotesque(
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            color: NeedHubTokens.clay,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            GestureDetector(
                              onTap: person != null && person.reviewCount > 0
                                  ? () {
                                      final myId = ref.read(authProvider).userId;
                                      final isOwn = widget.userId != null && widget.userId == myId;
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => HistoryScreen(
                                            userId: widget.userId,
                                            isOwnProfile: isOwn,
                                            personName: widget.name,
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                              child: _MiniStat(
                                label: 'reviews',
                                value: person != null
                                    ? '${person.reviewCount}'
                                    : '0',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1),
                  const SizedBox(height: 22),

                  // ── Past Work & Ratings ────────────────────────────────────
                  Row(
                    children: [
                      Text(
                        'PAST WORK & RATINGS',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: t.muted2,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Ratings only',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: NeedHubTokens.clay,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      final myId = myProfileNotifier.value?.id;
                      final isOwn = widget.userId != null && widget.userId == myId;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HistoryScreen(
                            isOwnProfile: isOwn,
                            personName: name,
                            userId: widget.userId,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
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
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: NeedHubTokens.ochre.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.star_rounded,
                                  color: NeedHubTokens.ochre,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Past Work History',
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: t.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '5 completed tasks • 4.8 ★ average',
                                      style: GoogleFonts.hankenGrotesk(
                                          fontSize: 12, color: t.muted),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  size: 20, color: t.muted2),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: t.chip,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.lock_outline_rounded,
                                    size: 13, color: t.muted2),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Written feedback comments are private to profile owner',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 11.5,
                                      color: t.muted2,
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
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1),
                  const SizedBox(height: 22),

                  // Certificates placeholder
                  Text(
                    'CERTIFICATES',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.muted2,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: t.chip,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_outlined,
                            size: 18, color: t.muted2),
                        const SizedBox(width: 10),
                        Text(
                          'No certificates added yet',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 13, color: t.muted2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1),
                  const SizedBox(height: 22),

                  // Interests
                  Text(
                    'INTERESTS',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.muted2,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (person != null && person.interests.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: person.interests
                          .map((i) => _MiniChip(
                              label: i, color: NeedHubTokens.forest, t: t))
                          .toList(),
                    )
                  else
                    Text(
                      'No interests listed yet',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13, color: t.muted2),
                    ),
                  const SizedBox(height: 20),

                  // Skills
                  Text(
                    'SKILLS',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.muted2,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (person != null && person.skills.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: person.skills
                          .map((s) => _MiniChip(
                              label: s, color: NeedHubTokens.ochre, t: t))
                          .toList(),
                    )
                  else
                    Text(
                      'No skills listed yet',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13, color: t.muted2),
                    ),
                  const SizedBox(height: 24),
                  Divider(color: t.rail, height: 1),
                  const SizedBox(height: 22),

                  // About me prompts
                  Text(
                    'ABOUT $name',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.muted2,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (person != null) ...[
                    _PromptCard(q: person.promptQ1, a: person.promptA1, t: t),
                    const SizedBox(height: 10),
                    _PromptCard(q: person.promptQ2, a: person.promptA2, t: t),
                    const SizedBox(height: 10),
                    _PromptCard(q: person.promptQ3, a: person.promptA3, t: t),
                  ] else
                    Text(
                      'Nothing shared yet.',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13, color: t.muted2),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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


class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  final NeedHubTokens t;
  const _MiniChip({required this.label, required this.color, required this.t});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
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

class _PromptCard extends StatelessWidget {
  final String q;
  final String a;
  final NeedHubTokens t;
  const _PromptCard({required this.q, required this.a, required this.t});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
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
    );
  }
}
