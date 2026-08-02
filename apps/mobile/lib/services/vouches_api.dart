import 'api_client.dart';

/// One person who vouched for a skill, as shown on a profile. Mirrors the
/// server's SkillVouchDisplay shape (see lib/vouching.ts) — note there is no
/// credibility weight or suspicious flag anywhere in this file: the server
/// never sends them, by design.
class RecentVoucher {
  final String voucherId;
  final String voucherName;
  final bool verified;
  final String? testimonial;
  final DateTime createdAt;

  const RecentVoucher({
    required this.voucherId,
    required this.voucherName,
    required this.verified,
    this.testimonial,
    required this.createdAt,
  });

  factory RecentVoucher.fromJson(Map<String, dynamic> j) => RecentVoucher(
        voucherId: j['voucherId'] as String? ?? '',
        voucherName: j['voucherName'] as String? ?? 'Someone',
        verified: j['verified'] as bool? ?? false,
        testimonial: j['testimonial'] as String?,
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Vouch summary for one skill on a profile — how many vouches, how many are
/// verified, and a handful of recent testimonials.
class SkillVouchSummary {
  final String skillId;
  final String label;
  final int vouchCount;
  final int verifiedVouchCount;
  final List<RecentVoucher> recentVouchers;

  const SkillVouchSummary({
    required this.skillId,
    required this.label,
    required this.vouchCount,
    required this.verifiedVouchCount,
    required this.recentVouchers,
  });

  factory SkillVouchSummary.fromJson(Map<String, dynamic> j) => SkillVouchSummary(
        skillId: j['skillId'] as String? ?? '',
        label: j['label'] as String? ?? '',
        vouchCount: (j['vouchCount'] as num?)?.toInt() ?? 0,
        verifiedVouchCount: (j['verifiedVouchCount'] as num?)?.toInt() ?? 0,
        recentVouchers: ((j['recentVouchers'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => RecentVoucher.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );

  /// Parses the `skillVouches` object keyed by skillId from a profile
  /// response. A skill with zero vouches simply has no entry — see
  /// fetchSkillVouchSummaries in lib/vouching.ts.
  static Map<String, SkillVouchSummary> mapFrom(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, SkillVouchSummary>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is Map) {
        out[entry.key as String] =
            SkillVouchSummary.fromJson(Map<String, dynamic>.from(value));
      }
    }
    return out;
  }
}

/// A vouch you gave, for managing (edit testimonial / withdraw) — from
/// GET /vouches/given.
class MyVouch {
  final String id;
  final String voucheeId;
  final String voucheeName;
  final String skillId;
  final String skillLabel;
  final String? testimonial;
  final bool verified;
  final DateTime createdAt;

  const MyVouch({
    required this.id,
    required this.voucheeId,
    required this.voucheeName,
    required this.skillId,
    required this.skillLabel,
    this.testimonial,
    required this.verified,
    required this.createdAt,
  });

  factory MyVouch.fromJson(Map<String, dynamic> j) {
    final vouchee = j['vouchee'] as Map<String, dynamic>? ?? const {};
    final skill = j['skill'] as Map<String, dynamic>? ?? const {};
    return MyVouch(
      id: j['id'] as String? ?? '',
      voucheeId: j['voucheeId'] as String? ?? vouchee['id'] as String? ?? '',
      voucheeName: vouchee['displayName'] as String? ?? 'Someone',
      skillId: j['skillId'] as String? ?? '',
      skillLabel: skill['label'] as String? ?? '',
      testimonial: j['testimonial'] as String?,
      verified: j['verified'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// One of the vouchee's own declared skills, suggested as likely
/// demonstrated on a specific completed Need — assistance only. Selecting
/// one still requires an explicit vouch submission; nothing is created just
/// by fetching suggestions.
class SuggestedSkill {
  final String id;
  final String label;

  const SuggestedSkill({required this.id, required this.label});

  factory SuggestedSkill.fromJson(Map<String, dynamic> j) => SuggestedSkill(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
      );
}

class VouchesApi {
  final ApiClient _api;
  VouchesApi(this._api);

  /// Creates a vouch. Throws on the server's 409 if this skill was already
  /// vouched for by the caller — the UI should offer edit instead in that
  /// case (see [given]).
  Future<void> create({
    required String voucheeId,
    required String skillId,
    String? testimonial,
  }) async {
    await _api.post('/vouches', {
      'voucheeId': voucheeId,
      'skillId': skillId,
      if (testimonial != null && testimonial.trim().isNotEmpty)
        'testimonial': testimonial.trim(),
    });
  }

  Future<void> edit(String vouchId, {String? testimonial}) async {
    await _api.patch('/vouches/$vouchId', {
      'testimonial':
          (testimonial != null && testimonial.trim().isNotEmpty)
              ? testimonial.trim()
              : null,
    });
  }

  Future<void> withdraw(String vouchId) async {
    await _api.delete('/vouches/$vouchId');
  }

  /// Vouches the caller has given, for a "manage my vouches" view.
  Future<List<MyVouch>> given() async {
    final res = await _api.get('/vouches/given');
    final list = (res['vouches'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => MyVouch.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// AI-assisted suggestions for a specific completed Need — the caller must
  /// have actually completed it with [voucheeId], or the server rejects the
  /// request. Suggestion only; never creates a vouch.
  Future<List<SuggestedSkill>> suggest({
    required String needId,
    required String voucheeId,
  }) async {
    final res = await _api
        .get('/vouches/suggest?needId=$needId&voucheeId=$voucheeId');
    final list = (res['suggestedSkills'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => SuggestedSkill.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
}
