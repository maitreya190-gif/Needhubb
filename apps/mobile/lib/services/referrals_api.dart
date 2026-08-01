import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

final referralsApiProvider = Provider<ReferralsApi>(
  (ref) => ReferralsApi(ref.read(apiClientProvider)),
);

class ReferralStats {
  final int total;
  final int activated;
  final int pointsEarned;
  const ReferralStats({required this.total, required this.activated, required this.pointsEarned});
  factory ReferralStats.fromJson(Map<String, dynamic> j) => ReferralStats(
        total: j['total'] as int? ?? 0,
        activated: j['activated'] as int? ?? 0,
        pointsEarned: j['pointsEarned'] as int? ?? 0,
      );
}

class ReferralEntry {
  final String id;
  final String refereeName;
  final String status;
  final DateTime joinedAt;
  const ReferralEntry({required this.id, required this.refereeName, required this.status, required this.joinedAt});
  factory ReferralEntry.fromJson(Map<String, dynamic> j) => ReferralEntry(
        id: j['id'] as String,
        refereeName: j['refereeName'] as String? ?? 'Unknown',
        status: j['status'] as String? ?? 'PENDING',
        joinedAt: DateTime.tryParse(j['joinedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class ReferralMe {
  final String? referralCode;
  final ReferralStats stats;
  final List<ReferralEntry> referrals;
  const ReferralMe({required this.referralCode, required this.stats, required this.referrals});
  factory ReferralMe.fromJson(Map<String, dynamic> j) => ReferralMe(
        referralCode: j['referralCode'] as String?,
        stats: ReferralStats.fromJson(j['stats'] as Map<String, dynamic>? ?? {}),
        referrals: ((j['referrals'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(ReferralEntry.fromJson)
            .toList(),
      );
}

class ReferralsApi {
  final ApiClient _client;
  ReferralsApi(this._client);

  Future<ReferralMe> me() async {
    final data = await _client.get('/referrals/me');
    return ReferralMe.fromJson(data as Map<String, dynamic>);
  }
}
