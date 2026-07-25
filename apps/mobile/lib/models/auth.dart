class SignupResponse {
  final String userId;
  final bool requiresVerification;

  const SignupResponse({required this.userId, required this.requiresVerification});

  factory SignupResponse.fromJson(Map<String, dynamic> json) => SignupResponse(
        userId: json['userId'] as String,
        requiresVerification: json['requiresVerification'] as bool? ?? true,
      );
}

class AuthResponse {
  final String token;
  final String userId;

  const AuthResponse({
    required this.token,
    required this.userId,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return AuthResponse(
      token: json['token'] as String,
      userId: user?['id'] as String? ?? json['userId'] as String,
    );
  }
}

class UserProfile {
  final String id;
  final String email;
  final String displayName;
  final int verificationLevel;
  final String createdAt;
  final String? bio;
  final String? locationText;
  final int pointsTotal;

  const UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.verificationLevel,
    required this.createdAt,
    this.bio,
    this.locationText,
    required this.pointsTotal,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String,
      verificationLevel: json['verificationLevel'] as int? ?? 0,
      createdAt: json['createdAt'] as String,
      bio: profile?['bio'] as String?,
      locationText: profile?['locationText'] as String?,
      pointsTotal: profile?['pointsTotal'] as int? ?? 0,
    );
  }
}
