import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthState {
  final String? token;
  final String? userId;
  final String? displayName;
  final String? email;

  const AuthState({
    this.token,
    this.userId,
    this.displayName,
    this.email,
  });

  bool get isAuthenticated => token != null;

  AuthState copyWith({
    String? token,
    String? userId,
    String? displayName,
    String? email,
    bool clearToken = false,
  }) {
    return AuthState(
      token: clearToken ? null : (token ?? this.token),
      userId: clearToken ? null : (userId ?? this.userId),
      displayName: clearToken ? null : (displayName ?? this.displayName),
      email: clearToken ? null : (email ?? this.email),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'auth_user_id';
  static const _displayNameKey = 'auth_display_name';
  static const _emailKey = 'auth_email';

  /// Call once at app startup to restore persisted session.
  Future<void> init() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null) return;

      final userId = await _storage.read(key: _userIdKey);
      final displayName = await _storage.read(key: _displayNameKey);
      final email = await _storage.read(key: _emailKey);

      state = AuthState(
        token: token,
        userId: userId,
        displayName: displayName,
        email: email,
      );
    } catch (_) {
      // If secure storage fails on first run, stay logged out
    }
  }

  /// Persist a successful login/signup to secure storage and update state.
  Future<void> login({
    required String token,
    required String userId,
    String? displayName,
    String? email,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userIdKey, value: userId);
    if (displayName != null) {
      await _storage.write(key: _displayNameKey, value: displayName);
    }
    if (email != null) {
      await _storage.write(key: _emailKey, value: email);
    }

    state = AuthState(
      token: token,
      userId: userId,
      displayName: displayName,
      email: email,
    );
  }

  /// Clear all auth data and return to the logged-out state.
  Future<void> logout() async {
    await _storage.deleteAll();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
