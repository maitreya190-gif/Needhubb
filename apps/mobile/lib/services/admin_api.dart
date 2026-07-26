import 'package:dio/dio.dart';

// Same --dart-define=API_URL used by api_client.dart. Falls back to the
// Android emulator alias for local dev.
const _baseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:3000',
);

class AdminApi {
  static final AdminApi instance = AdminApi._();
  AdminApi._();

  String _secret = '';
  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Content-Type': 'application/json'},
  ));

  void setSecret(String s) => _secret = s;
  String get secret => _secret;
  bool get hasSecret => _secret.isNotEmpty;

  Options get _opts =>
      Options(headers: {'x-admin-secret': _secret});

  Future<AdminStats> stats() async {
    final r = await _dio.get<Map<String, dynamic>>('/admin/stats',
        options: _opts);
    return AdminStats.fromJson(r.data!);
  }

  Future<List<AdminUser>> users({String? search, int skip = 0}) async {
    final qs = {'skip': skip.toString(), if (search != null) 'search': search};
    final r = await _dio.get<List>('/admin/users',
        queryParameters: qs, options: _opts);
    return (r.data ?? [])
        .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteUser(String id) =>
      _dio.delete('/admin/users/$id', options: _opts);

  Future<List<AdminNeed>> needs({String? status, int skip = 0}) async {
    final qs = {'skip': skip.toString(), if (status != null) 'status': status};
    final r = await _dio.get<List>('/admin/needs',
        queryParameters: qs, options: _opts);
    return (r.data ?? [])
        .map((e) => AdminNeed.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteNeed(String id) =>
      _dio.delete('/admin/needs/$id', options: _opts);

  Future<List<AdminCert>> certs({String status = 'PENDING_REVIEW'}) async {
    final r = await _dio.get<List>('/admin/certificates',
        queryParameters: {'status': status}, options: _opts);
    return (r.data ?? [])
        .map((e) => AdminCert.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> reviewCert(String id, String status, {int? points}) =>
      _dio.patch('/admin/certificates/$id',
          data: {
            'status': status,
            if (points != null) 'pointsAwarded': points,
          },
          options: _opts);

  Future<List<AdminReport>> reports({String status = 'OPEN'}) async {
    final r = await _dio.get<List>('/admin/reports',
        queryParameters: {'status': status}, options: _opts);
    return (r.data ?? [])
        .map((e) => AdminReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> resolveReport(String id, String action, {String? message}) =>
      _dio.patch('/admin/reports/$id/resolve',
          data: {
            'action': action,
            if (message != null && message.isNotEmpty) 'message': message,
          },
          options: _opts);
}

// ── Models ────────────────────────────────────────────────────────────────────

class AdminStats {
  final int users, needs, pendingCerts, openReports;
  AdminStats(
      {required this.users,
      required this.needs,
      required this.pendingCerts,
      required this.openReports});
  factory AdminStats.fromJson(Map<String, dynamic> j) => AdminStats(
        users: j['users'] ?? 0,
        needs: j['needs'] ?? 0,
        pendingCerts: j['pendingCerts'] ?? 0,
        openReports: j['openReports'] ?? 0,
      );
}

class AdminUser {
  final String id, displayName, email, verificationLevel, createdAt;
  final int needsCount, reportsCount;
  AdminUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.verificationLevel,
    required this.createdAt,
    required this.needsCount,
    required this.reportsCount,
  });
  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'] ?? '',
        displayName: j['displayName'] ?? '',
        email: j['email'] ?? '',
        verificationLevel: j['verificationLevel'] ?? '',
        createdAt: j['createdAt'] ?? '',
        needsCount: (j['_count']?['needs'] ?? 0) as int,
        reportsCount: (j['_count']?['reports'] ?? 0) as int,
      );
}

class AdminNeed {
  final String id, title, status, needType, createdAt;
  final String posterName, posterEmail;
  AdminNeed({
    required this.id,
    required this.title,
    required this.status,
    required this.needType,
    required this.createdAt,
    required this.posterName,
    required this.posterEmail,
  });
  factory AdminNeed.fromJson(Map<String, dynamic> j) => AdminNeed(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        status: j['status'] ?? '',
        needType: j['needType'] ?? '',
        createdAt: j['createdAt'] ?? '',
        posterName: j['poster']?['displayName'] ?? '',
        posterEmail: j['poster']?['email'] ?? '',
      );
}

class AdminCert {
  final String id, type, fileUrl, status, createdAt;
  final int? pointsAwarded;
  final String userName, userEmail;
  AdminCert({
    required this.id,
    required this.type,
    required this.fileUrl,
    required this.status,
    required this.createdAt,
    required this.pointsAwarded,
    required this.userName,
    required this.userEmail,
  });
  factory AdminCert.fromJson(Map<String, dynamic> j) => AdminCert(
        id: j['id'] ?? '',
        type: j['type'] ?? '',
        fileUrl: j['fileUrl'] ?? '',
        status: j['status'] ?? '',
        createdAt: j['createdAt'] ?? '',
        pointsAwarded: j['pointsAwarded'] as int?,
        userName: j['user']?['displayName'] ?? '',
        userEmail: j['user']?['email'] ?? '',
      );
}

class AdminContextMessage {
  final String id, body, senderId, senderName, createdAt;
  final String? imageUrl;

  AdminContextMessage({
    required this.id,
    required this.body,
    required this.senderId,
    required this.senderName,
    required this.createdAt,
    this.imageUrl,
  });

  factory AdminContextMessage.fromJson(Map<String, dynamic> j) {
    final sender = j['sender'] as Map<String, dynamic>? ?? {};
    return AdminContextMessage(
      id: j['id'] ?? '',
      body: j['body'] ?? '',
      senderId: sender['id'] ?? '',
      senderName: sender['username'] as String? ?? sender['displayName'] as String? ?? 'Unknown',
      createdAt: j['createdAt'] ?? '',
      imageUrl: j['imageUrl'] as String?,
    );
  }
}

class AdminReport {
  final String id, targetType, targetId, reason, status, createdAt;
  final String reporterName, reporterEmail;
  final String? targetTitle;
  final String? targetBody;
  final String? targetAuthorName;
  final String? source;
  final List<AdminContextMessage> contextMessages;

  AdminReport({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.reporterName,
    required this.reporterEmail,
    this.targetTitle,
    this.targetBody,
    this.targetAuthorName,
    this.source,
    this.contextMessages = const [],
  });

  factory AdminReport.fromJson(Map<String, dynamic> j) {
    final target = j['target'] as Map<String, dynamic>?;
    final meta = j['meta'] as Map<String, dynamic>?;
    String? title;
    String? body;
    String? author;
    List<AdminContextMessage> contextMessages = [];

    if (target != null) {
      final kind = target['kind'] as String?;
      if (kind == 'NEED') {
        title = target['title'] as String? ?? target['blockedText'] as String?;
        body = target['description'] as String?;
        author = target['posterName'] as String?;
      } else if (kind == 'MESSAGE') {
        title = 'Message';
        body = target['body'] as String?;
        author = target['senderName'] as String?;
      } else if (kind == 'USER') {
        title = target['displayName'] as String?;
        body = target['email'] as String?;
      }
      // Parse context messages for MESSAGE and USER-with-threadId reports
      final rawCtx = target['contextMessages'] as List?;
      if (rawCtx != null) {
        contextMessages = rawCtx
            .cast<Map<String, dynamic>>()
            .map(AdminContextMessage.fromJson)
            .toList();
      }
    }
    if (body == null || body.isEmpty) {
      final detail = meta?['detail'] as Map<String, dynamic>?;
      final text = detail?['text'] as String?;
      if (text != null && text.isNotEmpty) body = text;
    }
    return AdminReport(
      id: j['id'] ?? '',
      targetType: j['targetType'] ?? '',
      targetId: j['targetId'] ?? '',
      reason: j['reason'] ?? '',
      status: j['status'] ?? '',
      createdAt: j['createdAt'] ?? '',
      reporterName: j['reporter']?['displayName'] ?? '',
      reporterEmail: j['reporter']?['email'] ?? '',
      targetTitle: title,
      targetBody: body,
      targetAuthorName: author,
      source: meta?['source'] as String?,
      contextMessages: contextMessages,
    );
  }
}
