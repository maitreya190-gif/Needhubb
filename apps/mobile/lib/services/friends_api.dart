import 'api_client.dart';

class FriendRequestDto {
  final String id;
  final String fromUserId;
  final String toUserId;
  final String status;
  final String? otherDisplayName;
  final String? otherAvatarUrl;

  const FriendRequestDto({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.status,
    this.otherDisplayName,
    this.otherAvatarUrl,
  });

  factory FriendRequestDto.fromJson(Map<String, dynamic> j) {
    final other = j['other'] as Map<String, dynamic>?;
    final profile = other?['profile'] as Map<String, dynamic>?;
    return FriendRequestDto(
      id: j['id'] as String,
      fromUserId: j['fromUserId'] as String,
      toUserId: j['toUserId'] as String,
      status: j['status'] as String,
      otherDisplayName: other?['displayName'] as String?,
      otherAvatarUrl: profile?['avatarUrl'] as String?,
    );
  }
}

class FriendDto {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? bio;

  const FriendDto({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.bio,
  });

  factory FriendDto.fromJson(Map<String, dynamic> j) {
    final profile = j['profile'] as Map<String, dynamic>?;
    return FriendDto(
      id: j['id'] as String,
      displayName: j['displayName'] as String? ?? '',
      avatarUrl: profile?['avatarUrl'] as String?,
      bio: profile?['bio'] as String?,
    );
  }
}

class FriendsApi {
  final ApiClient _api;
  FriendsApi(this._api);

  Future<void> sendRequest(String toUserId) =>
      _api.post('/friends/requests', {'toUserId': toUserId});

  Future<({List<FriendRequestDto> inbox, List<FriendRequestDto> outbox})>
      listRequests() async {
    final r = await _api.get('/friends/requests');
    final inbox = ((r['inbox'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(FriendRequestDto.fromJson)
        .toList();
    final outbox = ((r['outbox'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(FriendRequestDto.fromJson)
        .toList();
    return (inbox: inbox, outbox: outbox);
  }

  Future<void> accept(String requestId) =>
      _api.post('/friends/requests/$requestId/accept', const {});
  Future<void> decline(String requestId) =>
      _api.post('/friends/requests/$requestId/decline', const {});
  Future<void> cancel(String requestId) =>
      _api.delete('/friends/requests/$requestId');

  Future<List<FriendDto>> list() async {
    final res = await _api.getList('/friends');
    return res.map(FriendDto.fromJson).toList();
  }

  Future<void> unfriend(String userId) => _api.delete('/friends/$userId');
  Future<void> block(String userId) =>
      _api.post('/friends/blocks', {'userId': userId});
  Future<void> unblock(String userId) => _api.delete('/friends/blocks/$userId');

  Future<List<FriendDto>> listBlocks() async {
    final res = await _api.getList('/friends/blocks');
    return res.map(FriendDto.fromJson).toList();
  }
}
