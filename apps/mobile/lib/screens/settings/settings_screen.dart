import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_strings.dart';
import '../../models/user_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/friends_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';
import '../history/history_screen.dart';
import 'plus_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _hidePreciseLocation = false;

  @override
  void initState() {
    super.initState();
    uiLanguageNotifier.addListener(_onLangChange);
  }

  void _onLangChange() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleOnlineStatus(bool value) async {
    final previous = showOnlineStatusNotifier.value;
    showOnlineStatusNotifier.value = value;
    try {
      await ref.read(profilesApiProvider).update(showOnlineStatus: value);
    } catch (_) {
      showOnlineStatusNotifier.value = previous;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(S.current.error)));
      }
    }
  }

  @override
  void dispose() {
    uiLanguageNotifier.removeListener(_onLangChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;
    final currentTokens = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: t.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: t.rail, width: 1),
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: t.ink,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      s.settings,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),

            // ── Appearance ─────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SectionLabel(label: s.appearance),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.55,
                children: allThemes.map((theme) {
                  final isSelected = theme.key == currentTokens.key;
                  return _ThemeCard(
                    tokens: theme,
                    selected: isSelected,
                    onTap: () {
                      ref
                          .read(themeProvider.notifier)
                          .setTheme(theme.key);
                    },
                  );
                }).toList(),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),

            // ── Language ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SectionLabel(label: s.language.toUpperCase()),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: NeedHubThemes.cardShadow,
                  ),
                  child: ValueListenableBuilder<String>(
                    valueListenable: uiLanguageNotifier,
                    builder: (ctx, currentLang, _) => Column(
                      children: [
                        for (int i = 0; i < kSupportedLanguages.length; i++)
                          Column(
                            children: [
                              InkWell(
                                onTap: () => setUiLanguage(kSupportedLanguages[i]['code']!),
                                borderRadius: i == 0
                                    ? const BorderRadius.vertical(top: Radius.circular(16))
                                    : i == kSupportedLanguages.length - 1
                                        ? const BorderRadius.vertical(bottom: Radius.circular(16))
                                        : BorderRadius.zero,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                                  child: Row(
                                    children: [
                                      Text(
                                        kSupportedLanguages[i]['native']!,
                                        style: GoogleFonts.hankenGrotesk(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: t.ink,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        kSupportedLanguages[i]['name']!,
                                        style: GoogleFonts.hankenGrotesk(
                                          fontSize: 13,
                                          color: t.muted,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (currentLang == kSupportedLanguages[i]['code'])
                                        Icon(Icons.check_rounded, color: NeedHubTokens.clay, size: 18),
                                    ],
                                  ),
                                ),
                              ),
                              if (i < kSupportedLanguages.length - 1)
                                Divider(color: t.rail, height: 1),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),

            // ── Privacy & Alerts ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SectionLabel(label: s.privacyAlerts),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: NeedHubThemes.cardShadow,
                  ),
                  child: Column(
                    children: [
                      _ToggleRow(
                        icon: Icons.notifications_outlined,
                        title: s.notificationsLabel,
                        subtitle: s.alertsWhenResponds,
                        value: _notificationsEnabled,
                        onChanged: (v) =>
                            setState(() => _notificationsEnabled = v),
                        showDivider: true,
                      ),
                      _ToggleRow(
                        icon: Icons.location_off_outlined,
                        title: s.hidePreciseLocation,
                        subtitle: s.showNeighbourhoodOnly,
                        value: _hidePreciseLocation,
                        onChanged: (v) =>
                            setState(() => _hidePreciseLocation = v),
                        showDivider: true,
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: showOnlineStatusNotifier,
                        builder: (_, showOnline, __) => _ToggleRow(
                          icon: Icons.circle_outlined,
                          title: s.showOnlineStatusLabel,
                          subtitle: s.showOnlineStatusSubtitle,
                          value: showOnline,
                          onChanged: _toggleOnlineStatus,
                          showDivider: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),

            // ── Activity ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SectionLabel(label: s.activitySection),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: NeedHubThemes.cardShadow,
                  ),
                  child: Column(
                    children: [
                      _ActionRow(
                        icon: Icons.handshake_outlined,
                        title: s.peopleYouveHelped,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => HistoryScreen(
                                    userId: ref.read(authProvider).userId,
                                  )),
                        ),
                      ),
                      Divider(color: t.rail, height: 1),
                      ValueListenableBuilder<Set<String>>(
                        valueListenable: blockedNotifier,
                        builder: (_, blocked, __) => _ActionRow(
                          icon: Icons.block_rounded,
                          title:
                              '${s.blockedUsers}${blocked.isEmpty ? "" : " (${blocked.length})"}',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const _BlockedListScreen()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),

            // ── NeedHub Plus ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SectionLabel(label: 'NEEDHUB PLUS'),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: NeedHubThemes.cardShadow,
                  ),
                  child: _ActionRow(
                    icon: Icons.star_rounded,
                    title: 'NeedHub Plus',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PlusScreen()),
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),

            // ── Account ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SectionLabel(label: s.accountSection),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: NeedHubThemes.cardShadow,
                  ),
                  child: InkWell(
                    onTap: () async {
                      // Router watches authProvider and will auto-redirect
                      // to /login when the token is cleared — no context.go
                      // needed, avoiding a race where the widget unmounts.
                      await ref.read(authProvider.notifier).logout();
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      child: Row(
                        children: [
                          Icon(Icons.logout_rounded,
                              color: NeedHubTokens.clay, size: 20),
                          const SizedBox(width: 14),
                          Text(
                            s.logOut,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: NeedHubTokens.clay,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

// ── Theme card ────────────────────────────────────────────────────────────────

String _localizedThemeName(String key) {
  switch (key) {
    case 'paper': return S.current.themeNamePaper;
    case 'midnight': return S.current.themeNameMidnight;
    case 'sage': return S.current.themeNameSage;
    case 'linen': return S.current.themeNameLinen;
    case 'slate': return S.current.themeNameSlate;
    case 'blush': return S.current.themeNameBlush;
    case 'sky': return S.current.themeNameSky;
    case 'plum': return S.current.themeNamePlum;
    default: return key;
  }
}

class _ThemeCard extends StatelessWidget {
  final NeedHubTokens tokens;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.tokens,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? NeedHubTokens.forest : tokens.rail,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Swatch area
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tokens.paper,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(17),
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    children: [
                      _ColorSquare(color: NeedHubTokens.forest),
                      const SizedBox(width: 4),
                      _ColorSquare(color: NeedHubTokens.clay),
                    ],
                  ),
                ),
              ),
            ),
            // Name row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _localizedThemeName(tokens.key),
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: tokens.ink,
                      ),
                    ),
                  ),
                  if (selected)
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: NeedHubTokens.forest,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 12,
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

class _ColorSquare extends StatelessWidget {
  final Color color;

  const _ColorSquare({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ── Shared section sub-widgets ────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      label,
      style: GoogleFonts.hankenGrotesk(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: t.muted,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: t.muted2, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 12,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: NeedHubTokens.clay,
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            color: t.rail,
            thickness: 1,
            height: 1,
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: t.muted2, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: t.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

class _BlockedListScreen extends ConsumerStatefulWidget {
  const _BlockedListScreen();

  @override
  ConsumerState<_BlockedListScreen> createState() =>
      _BlockedListScreenState();
}

class _BlockedListScreenState extends ConsumerState<_BlockedListScreen> {
  List<FriendDto> _real = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final api = ref.read(friendsApiProvider);
      final rows = await api.listBlocks();
      if (!mounted) return;
      setState(() {
        _real = rows;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _unblockReal(FriendDto u) async {
    setState(() => _real = _real.where((x) => x.id != u.id).toList());
    blockedUserIdsNotifier.value = {...blockedUserIdsNotifier.value}
      ..remove(u.id);
    blockedNotifier.value = {...blockedNotifier.value}..remove(u.displayName);
    try {
      final api = ref.read(friendsApiProvider);
      await api.unblock(u.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${u.displayName} unblocked')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        backgroundColor: t.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          S.current.blockedUsers,
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.ink,
          ),
        ),
      ),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: blockedNotifier,
        builder: (_, blocked, __) {
          // Real API blocks take precedence; fall back to mock names.
          if (_loaded && _real.isNotEmpty) {
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              itemCount: _real.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final u = _real[i];
                return Container(
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
                        decoration: BoxDecoration(
                          color: t.chip,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: u.avatarUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: Image.network(u.avatarUrl!,
                                    width: 40, height: 40, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Text(
                                        _initials(u.displayName),
                                        style: GoogleFonts.bricolageGrotesque(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: t.muted2))),
                              )
                            : Text(_initials(u.displayName),
                                style: GoogleFonts.bricolageGrotesque(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: t.muted2)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(u.displayName,
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: t.ink)),
                      ),
                      TextButton(
                        onPressed: () => _unblockReal(u),
                        child: Text(S.current.unblock,
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: NeedHubTokens.clay)),
                      ),
                    ],
                  ),
                );
              },
            );
          }

          if (blocked.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 48, color: t.muted2),
                    const SizedBox(height: 12),
                    Text(S.current.noOneIsBlocked,
                        style: GoogleFonts.bricolageGrotesque(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: t.ink)),
                    const SizedBox(height: 6),
                    Text(
                      "Anyone you block will appear here so you can unblock them.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13.5, color: t.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            itemCount: blocked.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final name = blocked.elementAt(i);
              return Container(
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
                      decoration: BoxDecoration(
                        color: t.chip,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initials(name),
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.muted2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.ink,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        unblockUser(name);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$name unblocked')),
                        );
                      },
                      child: Text(S.current.unblock,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: NeedHubTokens.clay)),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
