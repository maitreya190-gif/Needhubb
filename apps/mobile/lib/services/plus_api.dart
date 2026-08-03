import 'api_client.dart';

DateTime? _parseDate(dynamic v) {
  if (v is! String || v.trim().isEmpty) return null;
  return DateTime.tryParse(v)?.toLocal();
}

class PlusBenefits {
  final bool needBoost;
  final bool chitchatBoost;
  final bool premiumBadge;
  final bool analytics;
  final bool aiInsights;
  final bool earlyAccess;
  final bool prioritySupport;

  const PlusBenefits({
    this.needBoost = false,
    this.chitchatBoost = false,
    this.premiumBadge = false,
    this.analytics = false,
    this.aiInsights = false,
    this.earlyAccess = false,
    this.prioritySupport = false,
  });

  factory PlusBenefits.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const PlusBenefits();
    return PlusBenefits(
      needBoost: j['needBoost'] as bool? ?? false,
      chitchatBoost: j['chitchatBoost'] as bool? ?? false,
      premiumBadge: j['premiumBadge'] as bool? ?? false,
      analytics: j['analytics'] as bool? ?? false,
      aiInsights: j['aiInsights'] as bool? ?? false,
      earlyAccess: j['earlyAccess'] as bool? ?? false,
      prioritySupport: j['prioritySupport'] as bool? ?? false,
    );
  }
}

class PlusStatus {
  final bool active;
  final String status;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final int priceMonthlyPaise;
  final PlusBenefits benefits;

  const PlusStatus({
    required this.active,
    required this.status,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.priceMonthlyPaise = 5000,
    this.benefits = const PlusBenefits(),
  });

  factory PlusStatus.fromJson(Map<String, dynamic> j) => PlusStatus(
        active: j['active'] as bool? ?? false,
        status: j['status'] as String? ?? 'PENDING',
        currentPeriodEnd: _parseDate(j['currentPeriodEnd']),
        cancelAtPeriodEnd: j['cancelAtPeriodEnd'] as bool? ?? false,
        priceMonthlyPaise: (j['priceMonthlyPaise'] as num?)?.toInt() ?? 5000,
        benefits: PlusBenefits.fromJson(j['benefits'] as Map<String, dynamic>?),
      );

  double get priceRupees => priceMonthlyPaise / 100;
}

class PlusPaymentIntent {
  final String paymentId;
  final int amountPaise;
  final String currency;
  final String action;
  final String? instructions;
  final String? upiDeepLink;

  const PlusPaymentIntent({
    required this.paymentId,
    required this.amountPaise,
    required this.currency,
    required this.action,
    this.instructions,
    this.upiDeepLink,
  });

  factory PlusPaymentIntent.fromJson(Map<String, dynamic> j) => PlusPaymentIntent(
        paymentId: j['paymentId'] as String? ?? '',
        amountPaise: (j['amountPaise'] as num?)?.toInt() ?? 0,
        currency: j['currency'] as String? ?? 'INR',
        action: j['action'] as String? ?? 'manual_instructions',
        instructions: j['instructions'] as String?,
        upiDeepLink: j['upiDeepLink'] as String?,
      );
}

class PlusPaymentConfirmResult {
  final String status;
  final bool selfReported;
  final DateTime? currentPeriodEnd;

  const PlusPaymentConfirmResult({required this.status, this.selfReported = false, this.currentPeriodEnd});

  factory PlusPaymentConfirmResult.fromJson(Map<String, dynamic> j) => PlusPaymentConfirmResult(
        status: j['status'] as String? ?? 'awaiting_confirmation',
        selfReported: j['selfReported'] as bool? ?? false,
        currentPeriodEnd: _parseDate(j['currentPeriodEnd']),
      );

  bool get activated => status == 'activated';
}

class PlusAnalytics {
  final int windowDays;
  final int profileViews;
  final int needViews;
  final int reach;
  final int shares;
  final int offersReceived;
  final int reviewsReceived;
  final int vouchesReceived;
  final double? responseRate;
  final List<({String day, int count})> dailyViews;
  final double? trendDirection;
  final bool insufficientTrendData;

  const PlusAnalytics({
    this.windowDays = 7,
    this.profileViews = 0,
    this.needViews = 0,
    this.reach = 0,
    this.shares = 0,
    this.offersReceived = 0,
    this.reviewsReceived = 0,
    this.vouchesReceived = 0,
    this.responseRate,
    this.dailyViews = const [],
    this.trendDirection,
    this.insufficientTrendData = true,
  });

  factory PlusAnalytics.fromJson(Map<String, dynamic> j) {
    final engagement = j['engagement'] as Map<String, dynamic>? ?? const {};
    final trend = j['trend'] as Map<String, dynamic>? ?? const {};
    final dailyRaw = (trend['dailyViews'] as List?) ?? const [];
    return PlusAnalytics(
      windowDays: (j['windowDays'] as num?)?.toInt() ?? 7,
      profileViews: (j['profileViews'] as num?)?.toInt() ?? 0,
      needViews: (j['needViews'] as num?)?.toInt() ?? 0,
      reach: (j['reach'] as num?)?.toInt() ?? 0,
      shares: (j['shares'] as num?)?.toInt() ?? 0,
      offersReceived: (engagement['offersReceived'] as num?)?.toInt() ?? 0,
      reviewsReceived: (engagement['reviewsReceived'] as num?)?.toInt() ?? 0,
      vouchesReceived: (engagement['vouchesReceived'] as num?)?.toInt() ?? 0,
      responseRate: (j['responseRate'] as num?)?.toDouble(),
      dailyViews: dailyRaw
          .whereType<Map<String, dynamic>>()
          .map((d) => (day: d['day'] as String? ?? '', count: (d['count'] as num?)?.toInt() ?? 0))
          .toList(),
      trendDirection: (trend['direction'] as num?)?.toDouble(),
      insufficientTrendData: trend['insufficientData'] as bool? ?? true,
    );
  }
}

class PlusInsights {
  final bool insufficientData;
  final List<String> insights;

  const PlusInsights({this.insufficientData = true, this.insights = const []});

  factory PlusInsights.fromJson(Map<String, dynamic> j) => PlusInsights(
        insufficientData: j['insufficientData'] as bool? ?? true,
        insights: ((j['insights'] as List?) ?? const []).whereType<String>().toList(),
      );
}

class PlusPayoutField {
  final String key;
  final String label;
  final String type;
  final bool required;

  const PlusPayoutField({required this.key, required this.label, required this.type, this.required = true});

  factory PlusPayoutField.fromJson(Map<String, dynamic> j) => PlusPayoutField(
        key: j['key'] as String? ?? '',
        label: j['label'] as String? ?? '',
        type: j['type'] as String? ?? 'text',
        required: j['required'] as bool? ?? true,
      );
}

class PlusRewardOffer {
  final String key;
  final String kind;
  final String title;
  final String description;
  final int pointsCost;
  final int rewardValuePaise;
  final int minVerifiedPoints;
  final List<PlusPayoutField> payoutFields;
  final bool alreadyClaimed;
  final bool eligible;
  final String? ineligibleReason;

  const PlusRewardOffer({
    required this.key,
    required this.kind,
    required this.title,
    required this.description,
    required this.pointsCost,
    required this.rewardValuePaise,
    required this.minVerifiedPoints,
    this.payoutFields = const [],
    this.alreadyClaimed = false,
    this.eligible = false,
    this.ineligibleReason,
  });

  factory PlusRewardOffer.fromJson(Map<String, dynamic> j) => PlusRewardOffer(
        key: j['key'] as String? ?? '',
        kind: j['kind'] as String? ?? 'CASHBACK',
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        pointsCost: (j['pointsCost'] as num?)?.toInt() ?? 0,
        rewardValuePaise: (j['rewardValuePaise'] as num?)?.toInt() ?? 0,
        minVerifiedPoints: (j['minVerifiedPoints'] as num?)?.toInt() ?? 0,
        payoutFields: ((j['payoutFields'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PlusPayoutField.fromJson)
            .toList(),
        alreadyClaimed: j['alreadyClaimed'] as bool? ?? false,
        eligible: j['eligible'] as bool? ?? false,
        ineligibleReason: j['reason'] as String?,
      );

  double get rewardValueRupees => rewardValuePaise / 100;
}

class PlusRewardsCatalog {
  final int verifiedPoints;
  final int spendableBalance;
  final List<PlusRewardOffer> offers;

  const PlusRewardsCatalog({this.verifiedPoints = 0, this.spendableBalance = 0, this.offers = const []});

  factory PlusRewardsCatalog.fromJson(Map<String, dynamic> j) => PlusRewardsCatalog(
        verifiedPoints: (j['verifiedPoints'] as num?)?.toInt() ?? 0,
        spendableBalance: (j['spendableBalance'] as num?)?.toInt() ?? 0,
        offers: ((j['offers'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PlusRewardOffer.fromJson)
            .toList(),
      );
}

class PlusRewardClaim {
  final String id;
  final String offerTitle;
  final String kind;
  final String status;
  final int pointsSpent;
  final int rewardValuePaise;
  final String? payoutRef;
  final DateTime createdAt;
  final DateTime? processedAt;

  const PlusRewardClaim({
    required this.id,
    required this.offerTitle,
    required this.kind,
    required this.status,
    required this.pointsSpent,
    required this.rewardValuePaise,
    this.payoutRef,
    required this.createdAt,
    this.processedAt,
  });

  factory PlusRewardClaim.fromJson(Map<String, dynamic> j) => PlusRewardClaim(
        id: j['id'] as String? ?? '',
        offerTitle: j['offerTitle'] as String? ?? '',
        kind: j['kind'] as String? ?? 'CASHBACK',
        status: j['status'] as String? ?? 'PENDING',
        pointsSpent: (j['pointsSpent'] as num?)?.toInt() ?? 0,
        rewardValuePaise: (j['rewardValuePaise'] as num?)?.toInt() ?? 0,
        payoutRef: j['payoutRef'] as String?,
        createdAt: _parseDate(j['createdAt']) ?? DateTime.now(),
        processedAt: _parseDate(j['processedAt']),
      );
}

class PlusApi {
  final ApiClient _api;
  PlusApi(this._api);

  Future<PlusStatus> status() async => PlusStatus.fromJson(await _api.get('/plus/status'));

  Future<PlusPaymentIntent> subscribe() async =>
      PlusPaymentIntent.fromJson(await _api.post('/plus/subscribe', const {}));

  Future<PlusPaymentConfirmResult> confirmPayment(
    String paymentId, {
    required bool? selfReportedSuccess,
    String? reference,
  }) async {
    final r = await _api.post('/plus/payments/$paymentId/confirm', {
      if (selfReportedSuccess != null) 'selfReportedSuccess': selfReportedSuccess,
      if (reference != null) 'reference': reference,
    });
    return PlusPaymentConfirmResult.fromJson(r);
  }

  Future<void> cancel() => _api.post('/plus/cancel', const {});

  Future<PlusAnalytics> analytics({String window = '7d'}) async {
    final r = await _api.get('/plus/analytics?window=$window');
    return PlusAnalytics.fromJson(r);
  }

  Future<PlusInsights> insights() async => PlusInsights.fromJson(await _api.get('/plus/insights'));

  Future<PlusRewardsCatalog> rewards() async => PlusRewardsCatalog.fromJson(await _api.get('/plus/rewards'));

  Future<Map<String, dynamic>> claimReward(String offerKey, Map<String, String> payoutDetails) =>
      _api.post('/plus/rewards/$offerKey/claim', {'payoutDetails': payoutDetails});

  Future<List<PlusRewardClaim>> myRewards() async {
    final res = await _api.getList('/plus/rewards/mine');
    return res.map(PlusRewardClaim.fromJson).toList();
  }

  /// Fire-and-forget share tracking — never surfaces an error to the caller.
  Future<void> recordShare({required String targetType, required String targetId, required String ownerId}) async {
    try {
      await _api.post('/plus/events/share', {'targetType': targetType, 'targetId': targetId, 'ownerId': ownerId});
    } catch (_) {}
  }
}
