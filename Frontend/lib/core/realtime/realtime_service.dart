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
  final _chatEvents = StreamController<ChatRealtimePayload>.broadcast();
  final _ready = StreamController<void>.broadcast();
  Timer? _heartbeat;

  /// How often a connected device pings the server so it stays "online" even
  /// while idle (matches the backend's stale window — see PresenceService).
  static const _heartbeatInterval = Duration(seconds: 25);

  /// Emits every recognized inbound refresh-signal event. Screens/providers
  /// listen and re-fetch; the payload is intentionally not exposed (only an id).
  Stream<RealtimeEvent> get events => _events.stream;

  /// Emits every inbound chat event WITH its payload — unlike [events], chat is
  /// applied inline (see [ChatRealtimeEvent]). Bridged to the inbox providers in
  /// `chat_realtime_sync.dart`.
  Stream<ChatRealtimePayload> get chatEvents => _chatEvents.stream;

  /// Fires every time the socket becomes authenticated and ready — the
  /// initial connect, and every successful reconnect after a drop. Chat's
  /// typing indicator (`TypingController.resetForReconnect`) uses this to
  /// discard any "I already told the peer I'm typing" assumption made
  /// before a disconnect — a `true` sent while offline never reached them,
  /// and they have no way to know it was supposedly still in effect.
  Stream<void> get onReady => _ready.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Sends a client→server socket event (typing, presence heartbeat). No-op when
  /// the socket isn't connected — the server reconciles via REST/replay anyway.
  void emit(String event, [Object? data]) {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    if (data == null) {
      socket.emit(event);
    } else {
      socket.emit(event, data);
    }
  }

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
    socket.onDisconnect((reason) {
      _log('disconnected: $reason');
      _stopHeartbeat();
    });
    socket.onConnectError((e) => _log('connect_error: $e'));

    // The server emits `ready` once the socket is authenticated and joined to
    // its user room. Only then is it safe to ask for the reconnect replay and
    // to start the presence heartbeat (emitting earlier would race the auth).
    socket.on('ready', (_) {
      _log('ready — requesting sync + starting heartbeat');
      socket.emit(ChatClientEvent.sync);
      _startHeartbeat();
      if (!_ready.isClosed) _ready.add(null);
    });

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

    // Chat events carry a payload the client applies inline (not a refresh
    // signal). Forward the decoded map to [chatEvents].
    for (final name in ChatRealtimeEvent.wireNames) {
      socket.on(name, (payload) {
        final event = ChatRealtimeEvent.fromWire(name);
        if (event == null || _chatEvents.isClosed) return;
        final data = _asMap(payload);
        if (data != null) _chatEvents.add(ChatRealtimePayload(event, data));
      });
    }

    _socket = socket;
    socket.connect();
  }

  /// App went to the background: mark this device offline right away (the server
  /// broadcasts it to peers with a last-seen) and pause the heartbeat so we
  /// don't keep re-announcing online while backgrounded.
  void handleAppBackgrounded() {
    emit(ChatClientEvent.presenceOffline);
    _stopHeartbeat();
  }

  /// App returned to the foreground: reconnect if the socket dropped while away,
  /// otherwise resume the heartbeat — which immediately re-announces online.
  void handleAppForegrounded() {
    final socket = _socket;
    if (socket == null) {
      unawaited(connect());
      return;
    }
    if (!socket.connected) {
      socket.connect(); // 'ready' will restart the heartbeat
      return;
    }
    _startHeartbeat(); // still connected — re-announce online now
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    // Fire once immediately so presence is fresh the moment we're ready, then on
    // the interval.
    emit(ChatClientEvent.presencePing);
    _heartbeat = Timer.periodic(
      _heartbeatInterval,
      (_) => emit(ChatClientEvent.presencePing),
    );
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  /// socket.io hands event payloads back as `dynamic`; a chat payload is always
  /// a JSON object. Cast defensively so a malformed frame can't throw onto the
  /// socket's event loop.
  Map<String, dynamic>? _asMap(dynamic payload) {
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) return payload.cast<String, dynamic>();
    return null;
  }

  /// Disconnects on logout — clears listeners so no stale events fire against a
  /// signed-out session.
  void disconnect() {
    _stopHeartbeat();
    _socket?.dispose();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _events.close();
    _chatEvents.close();
    _ready.close();
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[realtime] $message');
  }
}
