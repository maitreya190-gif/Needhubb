import 'package:flutter/material.dart';

class NeedHubTokens extends ThemeExtension<NeedHubTokens> {
  final String key;
  final String displayName;
  final Color paper;
  final Color card;
  final Color ink;
  final Color ink2;
  final Color muted;
  final Color muted2;
  final Color muted3;
  final Color muted4;
  final Color muted5;
  final Color rail;
  final Color rail2;
  final Color chip;
  final Color surfaceDark;
  final Color onDark;
  final Color onDarkMuted;
  final Color onDarkMuted2;
  final Color nav;
  final bool isDark;

  // Brand colors — never themed
  static const Color forest = Color(0xFF1E6B4E);
  static const Color ochre = Color(0xFFE0971C);
  static const Color clay = Color(0xFFE1553B);

  // Earn category tints
  static const Color earnTutoringTint = Color(0xFFE0971C);
  static const Color earnTaskTint = Color(0xFFC46A1E);
  static const Color earnGigTint = Color(0xFFB8541E);
  static const Color earnDevTint = Color(0xFF7A5AA8);
  static const Color earnResaleTint = Color(0xFF7A8A1E);

  const NeedHubTokens({
    required this.key,
    required this.displayName,
    required this.paper,
    required this.card,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.muted2,
    required this.muted3,
    required this.muted4,
    required this.muted5,
    required this.rail,
    required this.rail2,
    required this.chip,
    required this.surfaceDark,
    required this.onDark,
    required this.onDarkMuted,
    required this.onDarkMuted2,
    required this.nav,
    required this.isDark,
  });

  @override
  NeedHubTokens copyWith({
    String? key,
    String? displayName,
    Color? paper,
    Color? card,
    Color? ink,
    Color? ink2,
    Color? muted,
    Color? muted2,
    Color? muted3,
    Color? muted4,
    Color? muted5,
    Color? rail,
    Color? rail2,
    Color? chip,
    Color? surfaceDark,
    Color? onDark,
    Color? onDarkMuted,
    Color? onDarkMuted2,
    Color? nav,
    bool? isDark,
  }) {
    return NeedHubTokens(
      key: key ?? this.key,
      displayName: displayName ?? this.displayName,
      paper: paper ?? this.paper,
      card: card ?? this.card,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      muted: muted ?? this.muted,
      muted2: muted2 ?? this.muted2,
      muted3: muted3 ?? this.muted3,
      muted4: muted4 ?? this.muted4,
      muted5: muted5 ?? this.muted5,
      rail: rail ?? this.rail,
      rail2: rail2 ?? this.rail2,
      chip: chip ?? this.chip,
      surfaceDark: surfaceDark ?? this.surfaceDark,
      onDark: onDark ?? this.onDark,
      onDarkMuted: onDarkMuted ?? this.onDarkMuted,
      onDarkMuted2: onDarkMuted2 ?? this.onDarkMuted2,
      nav: nav ?? this.nav,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  NeedHubTokens lerp(NeedHubTokens? other, double t) {
    if (other == null) return this;
    return NeedHubTokens(
      key: t < 0.5 ? key : other.key,
      displayName: t < 0.5 ? displayName : other.displayName,
      paper: Color.lerp(paper, other.paper, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      muted2: Color.lerp(muted2, other.muted2, t)!,
      muted3: Color.lerp(muted3, other.muted3, t)!,
      muted4: Color.lerp(muted4, other.muted4, t)!,
      muted5: Color.lerp(muted5, other.muted5, t)!,
      rail: Color.lerp(rail, other.rail, t)!,
      rail2: Color.lerp(rail2, other.rail2, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      surfaceDark: Color.lerp(surfaceDark, other.surfaceDark, t)!,
      onDark: Color.lerp(onDark, other.onDark, t)!,
      onDarkMuted: Color.lerp(onDarkMuted, other.onDarkMuted, t)!,
      onDarkMuted2: Color.lerp(onDarkMuted2, other.onDarkMuted2, t)!,
      nav: Color.lerp(nav, other.nav, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }

}

// ── 8 theme instances (separate class to avoid name collision with the
//    `paper` field on NeedHubTokens) ─────────────────────────────────────────
class NeedHubThemes {
  NeedHubThemes._();

  static const NeedHubTokens paper = NeedHubTokens(
    key: 'paper',
    displayName: 'Paper',
    paper: Color(0xFFF4EDDF),
    card: Color(0xFFFBF7EE),
    ink: Color(0xFF211E17),
    ink2: Color(0xFF3A352B),
    muted: Color(0xFF8A7F6D),
    muted2: Color(0xFF6E6455),
    muted3: Color(0xFF7A6F5E),
    muted4: Color(0xFF5A5142),
    muted5: Color(0xFFA89D8A),
    rail: Color(0xFFE7DCC6),
    rail2: Color(0xFFD9CCB2),
    chip: Color(0xFFEEE4D0),
    surfaceDark: Color(0xFF211E17),
    onDark: Color(0xFFF4EDDF),
    onDarkMuted: Color(0xFFA99F8C),
    onDarkMuted2: Color(0xFFC7BDA9),
    nav: Color(0xF0FBF7EE), // rgba(251,247,238,.94) → alpha 0xF0
    isDark: false,
  );

  static const NeedHubTokens midnight = NeedHubTokens(
    key: 'midnight',
    displayName: 'Midnight',
    paper: Color(0xFF0D1321),
    card: Color(0xFF1D2D44),
    ink: Color(0xFFF0EBD8),
    ink2: Color(0xFFE2E8F1),
    muted: Color(0xFF93A4BA),
    muted2: Color(0xFFAAB8CA),
    muted3: Color(0xFF8394A9),
    muted4: Color(0xFFB9C5D4),
    muted5: Color(0xFF748CAB),
    rail: Color(0xFF24344F),
    rail2: Color(0xFF2F4463),
    chip: Color(0xFF22344F),
    surfaceDark: Color(0xFF080D18),
    onDark: Color(0xFFF0EBD8),
    onDarkMuted: Color(0xFF93A4BA),
    onDarkMuted2: Color(0xFFAEBCCD),
    nav: Color(0xEB0B101C), // rgba(11,16,28,.92) → alpha 0xEB
    isDark: true,
  );

  static const NeedHubTokens sage = NeedHubTokens(
    key: 'sage',
    displayName: 'Sage',
    paper: Color(0xFFE1EADE),
    card: Color(0xFFEFF5EC),
    ink: Color(0xFF1B2A21),
    ink2: Color(0xFF30413A),
    muted: Color(0xFF788A7B),
    muted2: Color(0xFF596D60),
    muted3: Color(0xFF67796D),
    muted4: Color(0xFF46584D),
    muted5: Color(0xFF91A394),
    rail: Color(0xFFD0DBC9),
    rail2: Color(0xFFBECDB5),
    chip: Color(0xFFD6E2CF),
    surfaceDark: Color(0xFF1B2A21),
    onDark: Color(0xFFE8F1E4),
    onDarkMuted: Color(0xFF96A798),
    onDarkMuted2: Color(0xFFBECCBB),
    nav: Color(0xF0EFF5EC), // rgba(239,245,236,.94) → alpha 0xF0
    isDark: false,
  );

  static const NeedHubTokens linen = NeedHubTokens(
    key: 'linen',
    displayName: 'Linen',
    paper: Color(0xFFE6E3DB),
    card: Color(0xFFF3F1EB),
    ink: Color(0xFF272420),
    ink2: Color(0xFF3D3932),
    muted: Color(0xFF898479),
    muted2: Color(0xFF6A655B),
    muted3: Color(0xFF787369),
    muted4: Color(0xFF565248),
    muted5: Color(0xFFA29D92),
    rail: Color(0xFFD8D4CA),
    rail2: Color(0xFFC9C4B9),
    chip: Color(0xFFE0DCD1),
    surfaceDark: Color(0xFF272420),
    onDark: Color(0xFFEFECE5),
    onDarkMuted: Color(0xFFA5A093),
    onDarkMuted2: Color(0xFFC6C1B6),
    nav: Color(0xF0F3F1EB), // rgba(243,241,235,.94) → alpha 0xF0
    isDark: false,
  );

  static const NeedHubTokens slate = NeedHubTokens(
    key: 'slate',
    displayName: 'Slate',
    paper: Color(0xFF191C21),
    card: Color(0xFF252A31),
    ink: Color(0xFFEAECEF),
    ink2: Color(0xFFDCDFE4),
    muted: Color(0xFF8B929C),
    muted2: Color(0xFFA0A7B0),
    muted3: Color(0xFF7E858F),
    muted4: Color(0xFFB0B6BE),
    muted5: Color(0xFF6C737D),
    rail: Color(0xFF2D333B),
    rail2: Color(0xFF3A414A),
    chip: Color(0xFF2B313A),
    surfaceDark: Color(0xFF101317),
    onDark: Color(0xFFEAECEF),
    onDarkMuted: Color(0xFF8B929C),
    onDarkMuted2: Color(0xFFAAB1BA),
    nav: Color(0xEB191C21), // rgba(25,28,33,.92) → alpha 0xEB
    isDark: true,
  );

  static const NeedHubTokens blush = NeedHubTokens(
    key: 'blush',
    displayName: 'Blush',
    paper: Color(0xFFF0E1DD),
    card: Color(0xFFFAEFEB),
    ink: Color(0xFF2C201E),
    ink2: Color(0xFF43332F),
    muted: Color(0xFF9C837C),
    muted2: Color(0xFF7B655F),
    muted3: Color(0xFF8A726B),
    muted4: Color(0xFF614E49),
    muted5: Color(0xFFB39C95),
    rail: Color(0xFFE6D3CD),
    rail2: Color(0xFFDAC2BB),
    chip: Color(0xFFECDBD5),
    surfaceDark: Color(0xFF2C201E),
    onDark: Color(0xFFF6E9E4),
    onDarkMuted: Color(0xFFB39C95),
    onDarkMuted2: Color(0xFFD1C0BA),
    nav: Color(0xF0FAEFEB), // rgba(250,239,235,.94) → alpha 0xF0
    isDark: false,
  );

  static const NeedHubTokens sky = NeedHubTokens(
    key: 'sky',
    displayName: 'Sky',
    paper: Color(0xFFDDE6EC),
    card: Color(0xFFEDF3F7),
    ink: Color(0xFF1A2730),
    ink2: Color(0xFF2E3E49),
    muted: Color(0xFF748592),
    muted2: Color(0xFF576976),
    muted3: Color(0xFF667783),
    muted4: Color(0xFF45555F),
    muted5: Color(0xFF8E9DA9),
    rail: Color(0xFFCDD9E1),
    rail2: Color(0xFFBBCAD4),
    chip: Color(0xFFD5E1E9),
    surfaceDark: Color(0xFF1A2730),
    onDark: Color(0xFFE8F0F5),
    onDarkMuted: Color(0xFF93A2AE),
    onDarkMuted2: Color(0xFFBECCD5),
    nav: Color(0xF0EDF3F7), // rgba(237,243,247,.94) → alpha 0xF0
    isDark: false,
  );

  static const NeedHubTokens plum = NeedHubTokens(
    key: 'plum',
    displayName: 'Plum',
    paper: Color(0xFF221826),
    card: Color(0xFF2E2233),
    ink: Color(0xFFEFE7F0),
    ink2: Color(0xFFE0D4E2),
    muted: Color(0xFF9D8AA3),
    muted2: Color(0xFFB2A2B7),
    muted3: Color(0xFF8F7D96),
    muted4: Color(0xFFC0B3C4),
    muted5: Color(0xFF7C6B83),
    rail: Color(0xFF372A3D),
    rail2: Color(0xFF443549),
    chip: Color(0xFF352A3B),
    surfaceDark: Color(0xFF160F1A),
    onDark: Color(0xFFEFE7F0),
    onDarkMuted: Color(0xFF9D8AA3),
    onDarkMuted2: Color(0xFFBCAAC1),
    nav: Color(0xEB221826), // rgba(34,24,38,.92) → alpha 0xEB
    isDark: true,
  );

  static const List<NeedHubTokens> all = [
    paper,
    midnight,
    sage,
    linen,
    slate,
    blush,
    sky,
    plum,
  ];

  static NeedHubTokens fromKey(String key) {
    return all.firstWhere(
      (t) => t.key == key,
      orElse: () => paper,
    );
  }

  // Card shadow (warm, soft)
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x1A281E0F),
      blurRadius: 16,
      offset: Offset(0, 6),
      spreadRadius: -12,
    ),
  ];
}

// BuildContext extension for convenient token access
extension NeedHubTokensX on BuildContext {
  NeedHubTokens get tokens =>
      Theme.of(this).extension<NeedHubTokens>() ?? NeedHubThemes.blush;
}
