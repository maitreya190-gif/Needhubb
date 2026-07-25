import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

class AppTheme {
  AppTheme._();

  static ThemeData forTokens(NeedHubTokens t) {
    final brightness = t.isDark ? Brightness.dark : Brightness.light;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: NeedHubTokens.clay,
      onPrimary: Colors.white,
      primaryContainer: NeedHubTokens.clay.withValues(alpha: 0.15),
      onPrimaryContainer: NeedHubTokens.clay,
      secondary: NeedHubTokens.forest,
      onSecondary: Colors.white,
      secondaryContainer: NeedHubTokens.forest.withValues(alpha: 0.15),
      onSecondaryContainer: NeedHubTokens.forest,
      tertiary: NeedHubTokens.ochre,
      onTertiary: Colors.white,
      tertiaryContainer: NeedHubTokens.ochre.withValues(alpha: 0.15),
      onTertiaryContainer: NeedHubTokens.ochre,
      error: const Color(0xFFE0392B),
      onError: Colors.white,
      errorContainer: const Color(0xFFFFDAD6),
      onErrorContainer: const Color(0xFF410002),
      surface: t.paper,
      onSurface: t.ink,
      surfaceContainerHighest: t.card,
      onSurfaceVariant: t.muted,
      outline: t.rail,
      outlineVariant: t.rail2,
      shadow: t.surfaceDark,
      scrim: t.surfaceDark,
      inverseSurface: t.surfaceDark,
      onInverseSurface: t.onDark,
      inversePrimary: t.onDark,
    );

    final displayTextTheme = GoogleFonts.bricolageGrotesqueTextTheme().copyWith(
      displayLarge: GoogleFonts.bricolageGrotesque(
        fontSize: 57,
        fontWeight: FontWeight.w800,
        color: t.ink,
      ),
      displayMedium: GoogleFonts.bricolageGrotesque(
        fontSize: 45,
        fontWeight: FontWeight.w800,
        color: t.ink,
      ),
      displaySmall: GoogleFonts.bricolageGrotesque(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: t.ink,
      ),
      headlineLarge: GoogleFonts.bricolageGrotesque(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: t.ink,
      ),
      headlineMedium: GoogleFonts.bricolageGrotesque(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: t.ink,
      ),
      headlineSmall: GoogleFonts.bricolageGrotesque(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: t.ink,
      ),
      titleLarge: GoogleFonts.bricolageGrotesque(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: t.ink,
      ),
      titleMedium: GoogleFonts.hankenGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: t.ink,
      ),
      titleSmall: GoogleFonts.hankenGrotesk(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: t.ink,
      ),
      bodyLarge: GoogleFonts.hankenGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: t.ink,
      ),
      bodyMedium: GoogleFonts.hankenGrotesk(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: t.ink,
      ),
      bodySmall: GoogleFonts.hankenGrotesk(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: t.muted,
      ),
      labelLarge: GoogleFonts.hankenGrotesk(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: t.ink,
      ),
      labelMedium: GoogleFonts.hankenGrotesk(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: t.muted,
      ),
      labelSmall: GoogleFonts.hankenGrotesk(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: t.muted,
        letterSpacing: 0.5,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: t.paper,
      textTheme: displayTextTheme,

      // Card theme
      cardTheme: CardThemeData(
        color: t.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        shadowColor: t.surfaceDark.withValues(alpha: 0.10),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: t.paper,
        foregroundColor: t.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.bricolageGrotesque(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: t.ink,
        ),
        iconTheme: IconThemeData(color: t.ink),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: t.rail, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: t.rail, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: NeedHubTokens.clay, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE0392B), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE0392B), width: 1.5),
        ),
        labelStyle: GoogleFonts.hankenGrotesk(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: t.muted2,
          letterSpacing: 0.7,
        ),
        hintStyle: GoogleFonts.hankenGrotesk(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: t.muted,
        ),
      ),

      // Elevated button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.surfaceDark,
          foregroundColor: t.onDark,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.bricolageGrotesque(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
        ),
      ),

      // Outlined button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.ink,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: t.rail, width: 1.5),
          textStyle: GoogleFonts.bricolageGrotesque(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: t.rail,
        thickness: 1,
        space: 24,
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return t.muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return NeedHubTokens.clay;
          return t.rail;
        }),
      ),

      // Icon
      iconTheme: IconThemeData(color: t.ink, size: 22),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: t.chip,
        selectedColor: NeedHubTokens.clay,
        side: BorderSide(color: t.rail, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        labelStyle: GoogleFonts.hankenGrotesk(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: t.muted2,
        ),
        selectedShadowColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),

      extensions: [t],
    );
  }
}
