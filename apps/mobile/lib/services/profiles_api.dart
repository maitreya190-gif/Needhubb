import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'personality_api.dart';

/// An earned badge, exactly as the server computed it.
///
/// The server derives these from real facts (verifications, completed needs,
/// reviews) — the client never decides whether a badge is earned, it only
/// renders what it is told. That is deliberate: the previous version hardcoded
/// a list here and showed every new user three badges they had not earned.
class ProfileBadge {
  final String id;
  final String label;

  /// What it takes to earn — shown on locked badges as the goal.
  final String description;

  /// 'verification' | 'helping' | 'quality' | 'community'
  final String group;
  final bool earned;

  const ProfileBadge({
    required this.id,
    required this.label,
    required this.description,
    required this.group,
    required this.earned,
  });

  factory ProfileBadge.fromJson(Map<String, dynamic> j) => ProfileBadge(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        description: j['description'] as String? ?? '',
        group: j['group'] as String? ?? 'other',
        earned: j['earned'] as bool? ?? false,
      );

  static List<ProfileBadge> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => ProfileBadge.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
}

class ProfileMe {
  final String id;
  final String displayName;
  final String? username;
  final String? email;
  final String? bio;
  final String? gender;
  final String? locationText;
  final double? lat;
  final double? lng;
  final String? avatarUrl;
  final String? promptSkill;
  final String? promptCollab;
  final String? promptNeed;
  final int pointsTotal;
  final List<String> interestLabels;
  final List<String> skillLabels;
  final DateTime? faceVerifiedAt;
  final DateTime? emailVerifiedAt;
  final DateTime? phoneVerifiedAt;
  final String? phone;
  final int trustScore;
  final PersonalityTraits? personalityTraits;
  final String? personalityNickname;
  final String? personalitySummary;
  final List<String> personalityVibeTags;

  /// Every badge with its earned state — locked ones included, so the profile
  /// can show what is still available rather than silently omitting it.
  final List<ProfileBadge> badges;

  /// Needs completed for other people, and posted needs that reached
  /// completion. Shown alongside the badges as the raw numbers behind them.
  final int helpedNeedCount;
  final int fulfilledPostedCount;

  const ProfileMe({
    required this.id,
    required this.displayName,
    this.username,
    this.email,
    this.bio,
    this.gender,
    this.locationText,
    this.lat,
    this.lng,
    this.avatarUrl,
    this.promptSkill,
    this.promptCollab,
    this.promptNeed,
    required this.pointsTotal,
    required this.interestLabels,
    required this.skillLabels,
    this.faceVerifiedAt,
    this.emailVerifiedAt,
    this.phoneVerifiedAt,
    this.phone,
    this.trustScore = 0,
    this.personalityTraits,
    this.personalityNickname,
    this.personalitySummary,
    this.personalityVibeTags = const [],
    this.badges = const [],
    this.helpedNeedCount = 0,
    this.fulfilledPostedCount = 0,
  });

  bool get hasPersonality => personalityTraits != null;

  List<ProfileBadge> get earnedBadges =>
      badges.where((b) => b.earned).toList(growable: false);

  PersonalityProfile? get personalityProfile => personalityTraits == null
      ? null
      : PersonalityProfile(
          traits: personalityTraits!,
          nickname: personalityNickname ?? 'The NeedHubber',
          summary: personalitySummary ?? '',
          vibeTags: personalityVibeTags,
        );

  factory ProfileMe.fromJson(Map<String, dynamic> j) {
    final profile = j['profile'] is Map<String, dynamic>
        ? j['profile'] as Map<String, dynamic>
        : j;

    final interestsList = profile['interests'] as List? ?? j['interests'] as List? ?? [];
    final interests = interestsList
        .map((pi) {
          if (pi is Map<String, dynamic>) {
            if (pi['interest'] is Map<String, dynamic>) {
              return (pi['interest'] as Map<String, dynamic>)['label'] as String?;
            }
            return pi['label'] as String?;
          }
          if (pi is String) return pi;
          return null;
        })
        .whereType<String>()
        .toList();

    final skillsList = profile['skills'] as List? ?? j['skills'] as List? ?? [];
    final skills = skillsList
        .map((ps) {
          if (ps is Map<String, dynamic>) {
            if (ps['skill'] is Map<String, dynamic>) {
              return (ps['skill'] as Map<String, dynamic>)['label'] as String?;
            }
            return ps['label'] as String?;
          }
          if (ps is String) return ps;
          return null;
        })
        .whereType<String>()
        .toList();

    final faceVerifiedAtStr = profile['faceVerifiedAt'] as String?;
    final faceVerifiedAt = faceVerifiedAtStr != null
        ? DateTime.tryParse(faceVerifiedAtStr)
        : null;

    // email/phone verifiedAt + trustScore live on the User row, not the
    // nested Profile — read from `j` directly (see apps/api profiles.router.ts).
    final emailVerifiedAtStr = j['emailVerifiedAt'] as String?;
    final emailVerifiedAt = emailVerifiedAtStr != null
        ? DateTime.tryParse(emailVerifiedAtStr)
        : null;
    final phoneVerifiedAtStr = j['phoneVerifiedAt'] as String?;
    final phoneVerifiedAt = phoneVerifiedAtStr != null
        ? DateTime.tryParse(phoneVerifiedAtStr)
        : null;

    // Personality data is defensive-parsed — a bad row must never crash
    // the whole ProfileMe factory because every screen listens to the
    // profile notifier and would red-screen on a single throw.
    PersonalityTraits? personalityTraits;
    try {
      final traitsRaw = profile['personalityTraits'];
      if (traitsRaw is Map) {
        personalityTraits = PersonalityTraits.fromJson(
            traitsRaw.cast<String, dynamic>());
      }
    } catch (e) {
      debugPrint('[ProfileMe] personalityTraits parse failed: $e');
    }
    List<String> personalityVibeTags = const [];
    try {
      final vibeTagsRaw = profile['personalityVibeTags'];
      if (vibeTagsRaw is List) {
        personalityVibeTags =
            vibeTagsRaw.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      }
    } catch (e) {
      debugPrint('[ProfileMe] personalityVibeTags parse failed: $e');
    }

    return ProfileMe(
      id: (j['id'] as String?) ?? (profile['id'] as String?) ?? '',
      displayName: (j['displayName'] as String?) ?? (j['name'] as String?) ?? '',
      username: j['username'] as String?,
      email: j['email'] as String?,
      bio: profile['bio'] as String?,
      gender: profile['gender'] as String?,
      locationText: profile['locationText'] as String?,
      lat: (profile['lat'] as num?)?.toDouble(),
      lng: (profile['lng'] as num?)?.toDouble(),
      avatarUrl: profile['avatarUrl'] as String?,
      promptSkill: profile['promptSkill'] as String?,
      promptCollab: profile['promptCollab'] as String?,
      promptNeed: profile['promptNeed'] as String?,
      pointsTotal: (profile['pointsTotal'] as int?) ?? 0,
      interestLabels: interests,
      skillLabels: skills,
      faceVerifiedAt: faceVerifiedAt,
      emailVerifiedAt: emailVerifiedAt,
      phoneVerifiedAt: phoneVerifiedAt,
      phone: j['phone'] as String?,
      trustScore: (j['trustScore'] as num?)?.toInt() ?? 0,
      personalityTraits: personalityTraits,
      personalityNickname: profile['personalityNickname'] as String?,
      personalitySummary: profile['personalitySummary'] as String?,
      personalityVibeTags: personalityVibeTags,
      badges: ProfileBadge.listFrom(j['badges']),
      helpedNeedCount: (j['helpedNeedCount'] as num?)?.toInt() ?? 0,
      fulfilledPostedCount: (j['fulfilledPostedCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ProfilesApi {
  final ApiClient _api;
  ProfilesApi(this._api);

  Future<ProfileMe> me() async {
    final r = await _api.get('/profile/me');
    return ProfileMe.fromJson(r);
  }

  Future<ProfileMe> update({
    String? bio,
    String? gender,
    String? location,
    double? lat,
    double? lng,
    String? promptSkill,
    String? promptCollab,
    String? promptNeed,
    String? displayName,
    List<String>? interests,
    List<String>? skills,
  }) async {
    final r = await _api.patch('/profile/me', {
      if (bio != null) 'bio': bio,
      if (gender != null) 'gender': gender,
      if (location != null) 'location': location,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (promptSkill != null) 'promptSkill': promptSkill,
      if (promptCollab != null) 'promptCollab': promptCollab,
      if (promptNeed != null) 'promptNeed': promptNeed,
      if (displayName != null) 'displayName': displayName,
      if (interests != null) 'interests': interests,
      if (skills != null) 'skills': skills,
    });
    return ProfileMe.fromJson(r);
  }

  Future<ProfileMe> getById(String userId) async {
    final r = await _api.get('/profile/$userId');
    return ProfileMe.fromJson(r);
  }

  Future<List<Map<String, dynamic>>> pointsLedger({int take = 50}) async {
    return _api.getList('/points/ledger', query: {'take': take});
  }

  /// Trust Score, step 2: send a 6-digit OTP to [phone] (E.164, e.g. +919876543210).
  /// Returns `devOtp` when the server's dev-bypass is on, so the UI can auto-fill it.
  Future<Map<String, dynamic>> sendPhoneOtp(String phone) async {
    return _api.post('/profile/me/phone/send-otp', {'phone': phone});
  }

  /// Verifies the 6-digit code and marks the phone verified server-side.
  Future<Map<String, dynamic>> verifyPhoneOtp(String code) async {
    return _api.post('/profile/me/phone/verify-otp', {'code': code});
  }
}

final myProfileNotifier = ValueNotifier<ProfileMe?>(null);
