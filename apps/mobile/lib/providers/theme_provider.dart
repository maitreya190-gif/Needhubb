import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/tokens.dart';

class ThemeNotifier extends StateNotifier<NeedHubTokens> {
  ThemeNotifier() : super(NeedHubThemes.blush) {
    _loadSavedTheme();
  }

  static const _prefKey = 'nh_theme';

  Future<void> _loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString(_prefKey) ?? 'blush';
      state = NeedHubThemes.fromKey(key);
    } catch (_) {
      state = NeedHubThemes.blush;
    }
  }

  Future<void> setTheme(String key) async {
    state = NeedHubThemes.fromKey(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, key);
    } catch (_) {
      // persistence failure is non-fatal
    }
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, NeedHubTokens>(
  (ref) => ThemeNotifier(),
);

/// All 8 available themes, for display in the settings screen.
const allThemes = NeedHubThemes.all;
