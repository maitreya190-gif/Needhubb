import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// UI language — drives all localised string rendering
final uiLanguageNotifier = ValueNotifier<String>('en');

// Feed language — drives card-level translation
final feedLanguageNotifier = ValueNotifier<String>('en');

// Translation cache: needId → langCode → translated title
final Map<String, Map<String, String>> translationCache = {};

void setUiLanguage(String code) {
  uiLanguageNotifier.value = code;
  _persist('ui_lang', code);
  // Sync feed language so all need cards auto-translate when user picks a language
  feedLanguageNotifier.value = code;
  _persist('feed_lang', code);
}

void setFeedLanguage(String code) {
  feedLanguageNotifier.value = code;
  _persist('feed_lang', code);
}

Future<void> loadLanguagePreference() async {
  final prefs = await SharedPreferences.getInstance();
  final ui = prefs.getString('ui_lang') ?? 'en';
  final feed = prefs.getString('feed_lang') ?? 'en';
  uiLanguageNotifier.value = ui;
  feedLanguageNotifier.value = feed;
}

Future<void> _persist(String key, String value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, value);
}
