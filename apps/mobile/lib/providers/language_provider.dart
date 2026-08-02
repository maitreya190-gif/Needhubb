import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';

const List<Map<String, String>> kSupportedLanguages = [
  {'code': 'en', 'name': 'English', 'native': 'English'},
  {'code': 'hi', 'name': 'Hindi', 'native': 'हिंदी'},
  {'code': 'bn', 'name': 'Bengali', 'native': 'বাংলা'},
  {'code': 'te', 'name': 'Telugu', 'native': 'తెలుగు'},
  {'code': 'mr', 'name': 'Marathi', 'native': 'मराठी'},
  {'code': 'ta', 'name': 'Tamil', 'native': 'தமிழ்'},
  {'code': 'gu', 'name': 'Gujarati', 'native': 'ગુજરાતી'},
  {'code': 'kn', 'name': 'Kannada', 'native': 'ಕನ್ನಡ'},
];

// STT locale IDs per language code — used by speech_to_text
const Map<String, String> kLangLocaleIds = {
  'en': 'en_IN',
  'hi': 'hi_IN',
  'bn': 'bn_IN',
  'te': 'te_IN',
  'mr': 'mr_IN',
  'ta': 'ta_IN',
  'gu': 'gu_IN',
  'kn': 'kn_IN',
};

/// ValueNotifier subclass that exposes a public refresh() to force listeners
/// to re-run without changing the value. Used to trigger a UI rebuild after
/// the Groq translation cache finishes loading in the background.
class _LangNotifier extends ValueNotifier<String> {
  _LangNotifier(super.value);
  void refresh() => notifyListeners();
}

// UI language — drives all localised string rendering
final _LangNotifier uiLanguageNotifier = _LangNotifier('en');

// Feed language — drives card-level translation
final feedLanguageNotifier = ValueNotifier<String>('en');

// Translation cache: needId → langCode → translated title
final Map<String, Map<String, String>> translationCache = {};

/// Set UI language optimistically — flip the notifiers IMMEDIATELY so the
/// UI reflects the chosen language (with English fallback for uncached
/// keys), then load Groq translations in the background. When translations
/// arrive, call refresh() to force a rebuild.
Future<void> setUiLanguage(String code) async {
  feedLanguageNotifier.value = code;
  uiLanguageNotifier.value = code;
  _persist('feed_lang', code);
  _persist('ui_lang', code);
  // Background: pull translations and re-render when they arrive.
  await S.loadTranslations(code);
  uiLanguageNotifier.refresh();
}

void setFeedLanguage(String code) {
  feedLanguageNotifier.value = code;
  _persist('feed_lang', code);
}

Future<void> loadLanguagePreference() async {
  final prefs = await SharedPreferences.getInstance();
  final ui = prefs.getString('ui_lang') ?? 'en';
  final feed = prefs.getString('feed_lang') ?? 'en';
  feedLanguageNotifier.value = feed;
  // Load translations before setting ui notifier so UI renders in right language
  if (ui != 'en') {
    await S.loadTranslations(ui);
  }
  uiLanguageNotifier.value = ui;
}

Future<void> _persist(String key, String value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, value);
}
