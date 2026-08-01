import 'api_client.dart';

class TranslateApi {
  final ApiClient _client;
  TranslateApi(this._client);

  /// Returns the translated text, or [text] on any error (silent fallback).
  Future<String> translate(String text, String targetLang) async {
    if (targetLang == 'en' || text.trim().isEmpty) return text;
    try {
      final res = await _client.post('/translate', {
        'text': text,
        'targetLang': targetLang,
      });
      final translated = res['translated'];
      if (translated is String && translated.isNotEmpty) return translated;
      return text;
    } catch (_) {
      return text;
    }
  }
}

final _globalTranslateApi = TranslateApi(ApiClient());

TranslateApi get globalTranslateApi => _globalTranslateApi;
