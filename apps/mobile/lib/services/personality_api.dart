import 'package:flutter/foundation.dart';
import 'api_client.dart';

/// Numeric personality traits, each 0–100. Used both for display and for the
/// cosine-similarity match % calculation on the Connect surface.
class PersonalityTraits {
  final int openness;
  final int conscientiousness;
  final int extraversion;
  final int agreeableness;
  final int emotionalStability;

  const PersonalityTraits({
    required this.openness,
    required this.conscientiousness,
    required this.extraversion,
    required this.agreeableness,
    required this.emotionalStability,
  });

  factory PersonalityTraits.fromJson(Map<String, dynamic> j) => PersonalityTraits(
        openness: (j['openness'] as num?)?.toInt() ?? 50,
        conscientiousness: (j['conscientiousness'] as num?)?.toInt() ?? 50,
        extraversion: (j['extraversion'] as num?)?.toInt() ?? 50,
        agreeableness: (j['agreeableness'] as num?)?.toInt() ?? 50,
        emotionalStability: (j['emotionalStability'] as num?)?.toInt() ?? 50,
      );

  List<int> get vector => [
        openness,
        conscientiousness,
        extraversion,
        agreeableness,
        emotionalStability,
      ];
}

class PersonalityProfile {
  final PersonalityTraits traits;
  final String nickname;
  final String summary;
  final List<String> vibeTags;

  const PersonalityProfile({
    required this.traits,
    required this.nickname,
    required this.summary,
    required this.vibeTags,
  });

  factory PersonalityProfile.fromJson(Map<String, dynamic> j) => PersonalityProfile(
        traits: PersonalityTraits.fromJson(
            (j['traits'] as Map?)?.cast<String, dynamic>() ?? const {}),
        nickname: j['nickname'] as String? ?? 'The NeedHubber',
        summary: j['summary'] as String? ?? '',
        vibeTags: ((j['vibeTags'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class PersonalityApi {
  final ApiClient _api;
  PersonalityApi(this._api);

  /// Submit the 10-question quiz. Returns the Lyzr-generated profile.
  Future<PersonalityProfile> submit(List<String> answers) async {
    if (answers.length != 10) {
      throw ArgumentError('Personality quiz requires exactly 10 answers');
    }
    final r = await _api.post('/profile/me/personality', {'answers': answers});
    return PersonalityProfile.fromJson(r);
  }
}

/// Compute a match % (0–100) between two personality trait vectors using
/// normalized inverse-distance. Higher = more similar.
int personalityMatchPercent(PersonalityTraits a, PersonalityTraits b) {
  final av = a.vector;
  final bv = b.vector;
  // Manhattan distance across 5 dims of range 0-100 → max 500.
  var dist = 0;
  for (var i = 0; i < av.length; i++) {
    dist += (av[i] - bv[i]).abs();
  }
  final normalized = (1 - (dist / 500)).clamp(0.0, 1.0);
  return (normalized * 100).round();
}

/// Fallback: compute a compatibility % based on interest overlap. Used when
/// one or both users haven't taken the personality quiz.
int interestOverlapPercent({
  required List<String> myInterests,
  required List<String> theirInterests,
  String? theirBio,
}) {
  final mine = myInterests.map((s) => s.toLowerCase().trim()).toSet();
  final theirs = theirInterests.map((s) => s.toLowerCase().trim()).toSet();
  if (mine.isEmpty || theirs.isEmpty) return 30; // neutral baseline
  final overlap = mine.intersection(theirs).length;
  final union = mine.union(theirs).length;
  final jaccard = union == 0 ? 0.0 : overlap / union;
  // Nudge upward when the other person has a bio (means richer profile).
  final bioBonus = (theirBio != null && theirBio.trim().length > 20) ? 0.05 : 0.0;
  return ((jaccard + bioBonus) * 100).clamp(15, 92).round();
}

/// The current user's personality profile, hydrated on profile fetch.
/// `null` when the user hasn't taken the quiz.
final myPersonalityNotifier = ValueNotifier<PersonalityProfile?>(null);
