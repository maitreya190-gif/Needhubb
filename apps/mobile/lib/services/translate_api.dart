import 'package:dio/dio.dart';

const String _kApiBase = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://needhubapi-production.up.railway.app',
);

final _dio = Dio(BaseOptions(
  baseUrl: _kApiBase,
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 20),
));

/// Translate a single string. Falls back to [text] on any error.
Future<String> translateText(String text, String targetLang) async {
  if (targetLang == 'en' || text.trim().isEmpty) return text;
  try {
    final res = await _dio.post<Map<String, dynamic>>(
      '/translate',
      data: {'text': text, 'targetLang': targetLang},
    );
    final translated = res.data?['translated'];
    if (translated is String && translated.isNotEmpty) return translated;
  } catch (_) {}
  return text;
}

/// Batch-translate a list of strings in one Groq call.
/// Returns a list of the same length; falls back to originals on error.
Future<List<String>> translateBatch(List<String> texts, String targetLang) async {
  if (targetLang == 'en' || texts.isEmpty) return texts;
  try {
    final res = await _dio.post<Map<String, dynamic>>(
      '/translate/batch',
      data: {'texts': texts, 'targetLang': targetLang},
    );
    final raw = res.data?['translations'];
    if (raw is List && raw.length == texts.length) {
      return raw.map((e) => e is String ? e : '').toList();
    }
  } catch (_) {}
  return texts;
}

// Legacy wrapper for existing code that uses TranslateApi class
class TranslateApi {
  Future<String> translate(String text, String targetLang) =>
      translateText(text, targetLang);
}

final globalTranslateApi = TranslateApi();
