import 'package:flutter/foundation.dart';
import 'api_client.dart';

class MyCertificate {
  final String id;
  final String type;
  final String? description;
  final String status;
  final String fileUrl;
  final DateTime createdAt;

  const MyCertificate({
    required this.id,
    required this.type,
    required this.description,
    required this.status,
    required this.fileUrl,
    required this.createdAt,
  });

  factory MyCertificate.fromJson(Map<String, dynamic> j) => MyCertificate(
        id: j['id'] as String,
        type: j['type'] as String? ?? 'OTHER',
        description: j['description'] as String?,
        status: j['status'] as String? ?? 'PENDING_REVIEW',
        fileUrl: j['fileUrl'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  /// Human title — description usually holds `Title — Org` from the sheet.
  String get title {
    final d = description?.trim();
    if (d == null || d.isEmpty) return _prettyType(type);
    final dash = d.indexOf('—');
    if (dash > 0) return d.substring(0, dash).trim();
    return d;
  }

  String get subtitle {
    final d = description?.trim();
    if (d == null || d.isEmpty) return '';
    final dash = d.indexOf('—');
    if (dash > 0 && dash < d.length - 1) return d.substring(dash + 1).trim();
    return '';
  }

  static String _prettyType(String t) =>
      t.split('_').map((s) => s.isEmpty ? s : s[0] + s.substring(1).toLowerCase()).join(' ');
}

class MyAchievement {
  final String id;
  final String title;
  final String? description;
  final String category;
  final String status;
  final String? fileUrl;
  final DateTime createdAt;

  const MyAchievement({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.status,
    required this.fileUrl,
    required this.createdAt,
  });

  factory MyAchievement.fromJson(Map<String, dynamic> j) => MyAchievement(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        description: j['description'] as String?,
        category: j['category'] as String? ?? 'AWARD',
        status: j['status'] as String? ?? 'PENDING_REVIEW',
        fileUrl: j['fileUrl'] as String?,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class UploadsApi {
  final ApiClient _api;
  UploadsApi(this._api);

  Future<List<MyCertificate>> myCertificates() async {
    final res = await _api.getList('/certificates/mine');
    return res.map(MyCertificate.fromJson).toList();
  }

  Future<List<MyAchievement>> myAchievements() async {
    final res = await _api.getList('/achievements/mine');
    return res.map(MyAchievement.fromJson).toList();
  }
}

final myCertificatesNotifier = ValueNotifier<List<MyCertificate>>(const []);
final myAchievementsNotifier = ValueNotifier<List<MyAchievement>>(const []);
