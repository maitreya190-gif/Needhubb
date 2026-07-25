import 'api_client.dart';

DateTime? _parseDate(dynamic v) {
  if (v is! String || v.trim().isEmpty) return null;
  final raw = v.trim();
  final str = raw.endsWith('Z') || raw.contains('+') || (raw.length > 10 && raw.substring(10).contains('-'))
      ? raw
      : '${raw}Z';
  final parsed = DateTime.tryParse(str) ?? DateTime.tryParse(raw);
  return parsed?.toLocal();
}

class ChitchatPerson {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final DateTime? availableUntil;
  final double? lat;
  final double? lng;
  final double? distanceKm;

  const ChitchatPerson({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.availableUntil,
    this.lat,
    this.lng,
    this.distanceKm,
  });

  factory ChitchatPerson.fromJson(Map<String, dynamic> j) {
    return ChitchatPerson(
      userId: j['userId'] as String,
      displayName: j['displayName'] as String? ?? '',
      avatarUrl: j['avatarUrl'] as String?,
      bio: j['bio'] as String?,
      availableUntil: _parseDate(j['availableUntil']),
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      distanceKm: (j['distanceKm'] as num?)?.toDouble(),
    );
  }

  String get distanceLabel {
    if (distanceKm == null) return '';
    if (distanceKm! < 1) return '${(distanceKm! * 1000).round()} m';
    return '${distanceKm!.toStringAsFixed(1)} km';
  }
}

class ChitchatStatus {
  final bool available;
  final DateTime? availableUntil;
  const ChitchatStatus({required this.available, this.availableUntil});

  factory ChitchatStatus.fromJson(Map<String, dynamic> j) {
    return ChitchatStatus(
      available: j['available'] as bool? ?? false,
      availableUntil: _parseDate(j['availableUntil']),
    );
  }
}

class ChitchatApi {
  final ApiClient _api;
  ChitchatApi(this._api);

  Future<ChitchatStatus> setAvailability(int hours) async {
    final r = await _api.post('/chitchat/availability', {'hours': hours});
    return ChitchatStatus(
      available: true,
      availableUntil: _parseDate(r['availableUntil']),
    );
  }

  Future<void> clearAvailability() => _api.delete('/chitchat/availability');

  Future<ChitchatStatus> status() async {
    final r = await _api.get('/chitchat/status');
    return ChitchatStatus.fromJson(r);
  }

  Future<List<ChitchatPerson>> availablePeople({
    double? lat,
    double? lng,
    double? distanceKm,
  }) async {
    final res = await _api.getList(
      '/chitchat/available-people',
      query: {
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (distanceKm != null) 'distanceKm': distanceKm,
      },
    );
    return res.map(ChitchatPerson.fromJson).toList();
  }
}
