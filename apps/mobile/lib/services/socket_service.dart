import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

const _wsUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:3000',
);

// On-screen debug status — surfaces the socket state without needing adb.
final ValueNotifier<String> socketDebugStatus = ValueNotifier<String>('idle');
final ValueNotifier<int> socketEventCount = ValueNotifier<int>(0);

// Singleton instance — all callers share the same connected socket.
final socketServiceProvider = Provider<SocketService>((ref) => SocketService.instance);

class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();
  // Keep the old default constructor pointing at the singleton for legacy call sites.
  factory SocketService() => instance;

  io.Socket? _socket;
  static const _storage = FlutterSecureStorage();

  void _setStatus(String s) {
    socketDebugStatus.value = s;
    // ignore: avoid_print
    print('[socket] $s');
  }

  Future<void> connect() async {
    if (_socket?.connected == true) {
      _setStatus('already connected');
      return;
    }
    final token = await _storage.read(key: 'auth_token');
    if (token == null) {
      _setStatus('no token');
      return;
    }
    _setStatus('connecting to $_wsUrl');

    // On native (Android/iOS), socket_io_client 3.x only supports websocket
    // transport — polling is web-only. Force websocket explicitly.
    _socket = io.io(
      _wsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setQuery({'token': token})
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .setTimeout(20000)
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) => _setStatus('✅ connected'));
    _socket!.onDisconnect((_) => _setStatus('❌ disconnected'));
    _socket!.onConnectError((e) => _setStatus('connect_err: $e'));
    _socket!.on('connect_error', (e) => _setStatus('connect_error evt: $e'));
    _socket!.on('error', (e) => _setStatus('error evt: $e'));
    _socket!.onAny((event, data) {
      socketEventCount.value = socketEventCount.value + 1;
      // ignore: avoid_print
      print('[socket] onAny: $event');
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

  // JSON maps from socket.io often arrive as Map<dynamic, dynamic>, not
  // Map<String, dynamic> — accept any Map and re-key.
  Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  /// Listen for new messages on the current thread.
  void onNewMessage(void Function(Map<String, dynamic> msg) handler) {
    // ignore: avoid_print
    print('[socket] registering new_message listener, socket=${_socket != null}, connected=${_socket?.connected}');
    _socket?.on('new_message', (data) {
      // ignore: avoid_print
      print('[socket] 📨 new_message event fired! data type: ${data.runtimeType}');
      final m = _asMap(data);
      if (m != null) handler(m);
      else {
        // ignore: avoid_print
        print('[socket] ❌ new_message data was null after asMap');
      }
    });
  }

  /// Listen for reaction updates.
  void onMessageReaction(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('message_reaction', (data) {
      final m = _asMap(data);
      if (m != null) handler(m);
    });
  }

  /// Listen for read-receipt updates (double-tick → blue).
  void onMessagesRead(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('messages_read', (data) {
      final m = _asMap(data);
      if (m != null) handler(m);
    });
  }

  /// Listen for deleted messages.
  void onMessageDeleted(void Function(String messageId) handler) {
    _socket?.on('message_deleted', (data) {
      final m = _asMap(data);
      if (m == null) return;
      final id = m['messageId'] as String?;
      if (id != null) handler(id);
    });
  }

  /// Listen for any new notification (badge increment).
  void onNewNotification(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('new_notification', (data) {
      final m = _asMap(data);
      if (m != null) handler(m);
    });
  }

  /// New need posted — broadcast to all users
  void onNewNeed(void Function(Map<String, dynamic> data) handler) {
    // ignore: avoid_print
    print('[socket] registering new_need listener, socket=${_socket != null}');
    _socket?.on('new_need', (data) {
      // ignore: avoid_print
      print('[socket] 🆕 new_need event fired!');
      final m = _asMap(data);
      if (m != null) handler(m);
    });
  }

  /// Someone responded to my need
  void onNewResponse(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('new_response', (data) {
      final m = _asMap(data);
      if (m != null) handler(m);
    });
  }

  /// My offer was accepted or declined
  void onResponseDecision(void Function(Map<String, dynamic> data) handler) {
    _socket?.on('response_decision', (data) {
      final m = _asMap(data);
      if (m != null) handler(m);
    });
  }

  void off(String event) => _socket?.off(event);

  bool get isConnected => _socket?.connected == true;
}
