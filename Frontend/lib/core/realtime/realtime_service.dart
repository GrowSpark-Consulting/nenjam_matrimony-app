import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'realtime_event.dart';

/// Thin wrapper over a single authenticated socket.io connection.
///
/// Responsibilities: connect after login with a fresh Firebase ID token,
/// auto-reconnect with exponential backoff + heartbeat (socket.io built-ins),
/// refresh the token on each (re)connect attempt so an hour-old token doesn't
/// wedge reconnection, and surface inbound [RealtimeEvent]s on a broadcast
/// stream. It holds NO UI/business logic — the Riverpod layer decides what to
/// refresh (see realtime_providers.dart).
class RealtimeService {
  RealtimeService({
    required String baseUrl,
    required Future<String?> Function() tokenProvider,
  })  : _baseUrl = baseUrl,
        _tokenProvider = tokenProvider;

  final String _baseUrl;
  final Future<String?> Function() _tokenProvider;

  io.Socket? _socket;
  final _events = StreamController<RealtimeEvent>.broadcast();

  /// Emits every recognized inbound event. Screens/providers listen and
  /// re-fetch; the payload is intentionally not exposed (it's only an id).
  Stream<RealtimeEvent> get events => _events.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Connects (idempotent — a second call while connected is a no-op). Safe to
  /// call on every login / app-resume.
  Future<void> connect() async {
    if (_socket != null) {
      if (!(_socket!.connected)) _socket!.connect();
      return;
    }
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) return;

    final socket = io.io(
      _baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000) // backoff starts at 1s …
          .setReconnectionDelayMax(15000) // … capped at 15s (exponential)
          .setAuth({'token': token})
          .build(),
    );

    socket.onConnect((_) => _log('connected: ${socket.id}'));
    socket.onDisconnect((reason) => _log('disconnected: $reason'));
    socket.onConnectError((e) => _log('connect_error: $e'));

    // Refresh the token before every reconnect attempt so a token that expired
    // during a long offline stretch doesn't cause an auth-reject loop.
    socket.on('reconnect_attempt', (_) async {
      final fresh = await _tokenProvider();
      if (fresh != null && fresh.isNotEmpty) {
        socket.auth = {'token': fresh};
      }
    });

    // The server disconnects a socket whose token is invalid/expired; re-auth
    // with a force-refreshed token and let reconnection resume.
    socket.on('unauthorized', (_) async {
      _log('unauthorized — refreshing token');
      final fresh = await _tokenProvider();
      if (fresh != null && fresh.isNotEmpty) {
        socket.auth = {'token': fresh};
      }
    });

    for (final name in RealtimeEvent.wireNames) {
      socket.on(name, (_) {
        final event = RealtimeEvent.fromWire(name);
        if (event != null && !_events.isClosed) _events.add(event);
      });
    }

    _socket = socket;
    socket.connect();
  }

  /// Disconnects on logout — clears listeners so no stale events fire against a
  /// signed-out session.
  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _events.close();
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[realtime] $message');
  }
}
