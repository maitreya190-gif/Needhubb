import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/auth.dart';
import 'api_client.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.read(apiClientProvider)),
);

class AuthService {
  final ApiClient _client;

  AuthService(this._client);

  Future<SignupResponse> signup({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final data = await _client.post('/auth/signup', {
      'email': email,
      'password': password,
      'displayName': displayName,
    });
    return SignupResponse.fromJson(data);
  }

  Future<AuthResponse> verifyEmail({
    required String userId,
    required String code,
  }) async {
    final data = await _client.post('/auth/verify-email', {
      'userId': userId,
      'code': code,
    });
    return AuthResponse.fromJson(data);
  }

  Future<void> resendOtp({required String userId}) async {
    await _client.post('/auth/resend-otp', {'userId': userId});
  }

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final data = await _client.post('/auth/login', {
      'email': email,
      'password': password,
    });
    return AuthResponse.fromJson(data);
  }

  Future<UserProfile> getMe() async {
    final data = await _client.get('/auth/me');
    return UserProfile.fromJson(data);
  }
}
