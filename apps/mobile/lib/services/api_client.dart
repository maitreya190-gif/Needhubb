import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Injected at build time via --dart-define. Falls back to the Android emulator
// alias for local dev so `flutter run` on an emulator still Just Works.
//   flutter run --dart-define=API_URL=http://10.0.2.2:3000
//   flutter build web --dart-define=API_URL=https://needhub-api.up.railway.app
const _baseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:3000',
);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  final Dio _dio;
  static const _storage = FlutterSecureStorage();

  ApiClient()
      : _dio = Dio(BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'auth_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  Future<Map<String, dynamic>> get(String path) async {
    final res = await _dio.get<Map<String, dynamic>>(path);
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> getList(String path,
      {Map<String, dynamic>? query}) async {
    final res = await _dio.get<List<dynamic>>(path, queryParameters: query);
    return (res.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> post(
      String path, Map<String, dynamic> body) async {
    final res = await _dio.post<Map<String, dynamic>>(path, data: body);
    return res.data ?? {};
  }

  /// Typed POST that returns [T] by applying [fromJson] to the response map.
  Future<T> postTyped<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final data = await post(path, body);
    return fromJson(data);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final res = await _dio.delete<Map<String, dynamic>>(path);
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> patch(
      String path, Map<String, dynamic> body) async {
    final res = await _dio.patch<Map<String, dynamic>>(path, data: body);
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> postForm(String path, FormData form) async {
    final res = await _dio.post<Map<String, dynamic>>(
      path,
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    return res.data ?? {};
  }
}
