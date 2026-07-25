import 'package:flutter/foundation.dart';
import 'api_client.dart';

class ProfileMe {
  final String id;
  final String displayName;
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

  const ProfileMe({
    required this.id,
    required this.displayName,
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
  });

  factory ProfileMe.fromJson(Map<String, dynamic> j) {
    final profile = j['profile'] as Map<String, dynamic>? ?? const {};
    final interests = ((profile['interests'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((pi) => (pi['interest'] as Map<String, dynamic>?)?['label'] as String?)
        .whereType<String>()
        .toList();
    final skills = ((profile['skills'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((ps) => (ps['skill'] as Map<String, dynamic>?)?['label'] as String?)
        .whereType<String>()
        .toList();
    return ProfileMe(
      id: j['id'] as String,
      displayName: j['displayName'] as String? ?? '',
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

  Future<void> update({
    String? bio,
    String? gender,
    String? location,
    String? promptSkill,
    String? promptCollab,
    String? promptNeed,
    String? displayName,
  }) async {
    await _api.patch('/profile/me', {
      if (bio != null) 'bio': bio,
      if (gender != null) 'gender': gender,
      if (location != null) 'location': location,
      if (promptSkill != null) 'promptSkill': promptSkill,
      if (promptCollab != null) 'promptCollab': promptCollab,
      if (promptNeed != null) 'promptNeed': promptNeed,
      if (displayName != null) 'displayName': displayName,
    });
  }

  Future<ProfileMe> getById(String userId) async {
    final r = await _api.get('/profile/$userId');
    return ProfileMe.fromJson(r);
  }

  Future<List<Map<String, dynamic>>> pointsLedger({int take = 50}) async {
    return _api.getList('/points/ledger', query: {'take': take});
  }
}

final myProfileNotifier = ValueNotifier<ProfileMe?>(null);
