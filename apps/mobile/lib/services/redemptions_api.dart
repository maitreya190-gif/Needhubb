import 'api_client.dart';

class RedemptionItem {
  final String id;
  final String title;
  final String description;
  final String? imageUrl;
  final int pointsCost;
  final int stock;

  const RedemptionItem({
    required this.id,
    required this.title,
    required this.description,
    this.imageUrl,
    required this.pointsCost,
    required this.stock,
  });

  factory RedemptionItem.fromJson(Map<String, dynamic> j) => RedemptionItem(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        pointsCost: (j['pointsCost'] as int?) ?? 0,
        stock: (j['stock'] as int?) ?? -1,
      );
}

class RedemptionResult {
  final String code;
  final int newBalance;
  final RedemptionItem item;
  const RedemptionResult({
    required this.code,
    required this.newBalance,
    required this.item,
  });
}

class MyRedemption {
  final String id;
  final String code;
  final String status;
  final DateTime createdAt;
  final RedemptionItem item;

  const MyRedemption({
    required this.id,
    required this.code,
    required this.status,
    required this.createdAt,
    required this.item,
  });

  factory MyRedemption.fromJson(Map<String, dynamic> j) => MyRedemption(
        id: j['id'] as String,
        code: j['code'] as String? ?? '',
        status: j['status'] as String? ?? 'PENDING',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        item: RedemptionItem.fromJson(
            (j['item'] as Map<String, dynamic>?) ?? const {}),
      );
}

class RedemptionsApi {
  final ApiClient _api;
  RedemptionsApi(this._api);

  Future<List<RedemptionItem>> catalog() async {
    final res = await _api.getList('/redemptions/catalog');
    return res.map(RedemptionItem.fromJson).toList();
  }

  Future<RedemptionResult> redeem(String itemId) async {
    final r = await _api.post('/redemptions/$itemId/redeem', const {});
    final red = r['redemption'] as Map<String, dynamic>;
    final item = RedemptionItem.fromJson(r['item'] as Map<String, dynamic>);
    return RedemptionResult(
      code: red['code'] as String,
      newBalance: (r['newBalance'] as int?) ?? 0,
      item: item,
    );
  }

  Future<List<MyRedemption>> mine() async {
    final res = await _api.getList('/redemptions/mine');
    return res.map(MyRedemption.fromJson).toList();
  }
}
