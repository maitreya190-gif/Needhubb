import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

const _wsUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:3000',
);

final socketServiceProvider = Provider<SocketService>((ref) => SocketService());

class SocketService {
  io.Socket? _socket;
  static const _storage = FlutterSecureStorage();

  Future<void> connect() async {
    if (_socket?.connected == true) return;
    final token = await _storage.read(key: 'auth_token');
    if (token == null) return;

    _socket = io.io(
      _wsUrl,
      io.OptionBuilder()
          .setTransports(['polling', 'websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1000)
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      // ignore: avoid_print
      print('[socket] connected');
    });
    _socket!.onDisconnect((_) {
      // ignore: avoid_print
      print('[socket] disconnected');
    });
    _socket!.onConnectError((e) {
      // ignore: avoid_print
      print('[socket] connect error: $e');
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void joinThread(String threadId) {
    _socket?.emit('join_thread', threadId);
  }

  void leaveThread(String threadId) {
    _socket?.emit('leave_thread', threadId);
  }

  /// Listen for new messages on the current thread.
  void onNewMessage(void Function(Map<String, dynamic> msg) handler) {
    _socket?.on('new_message', (data) {
      if (data is Map<String, dynamic>) handler(data);
    });
  }

  /// Listen for reaction updates.
  void onMessageReaction(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('message_reaction', (data) {
      if (data is Map<String, dynamic>) handler(data);
    });
  }

  /// Listen for deleted messages.
  void onMessageDeleted(void Function(String messageId) handler) {
    _socket?.on('message_deleted', (data) {
      if (data is Map<String, dynamic>) {
        final id = data['messageId'] as String?;
        if (id != null) handler(id);
      }
    });
  }

  /// Listen for any new notification (badge increment).
  void onNewNotification(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('new_notification', (data) {
      if (data is Map<String, dynamic>) handler(data);
    });
  }

  /// New need posted — broadcast to all users
  void onNewNeed(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('new_need', (data) {
      if (data is Map<String, dynamic>) handler(data);
    });
  }

  /// Someone responded to my need
  void onNewResponse(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('new_response', (data) {
      if (data is Map<String, dynamic>) handler(data);
    });
  }

  /// My offer was accepted or declined
  void onResponseDecision(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('response_decision', (data) {
      if (data is Map<String, dynamic>) handler(data);
    });
  }

  void off(String event) => _socket?.off(event);

  bool get isConnected => _socket?.connected == true;
}
