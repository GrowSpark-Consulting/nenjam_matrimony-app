import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/auth_token_service.dart';

/// Models `FirebaseAuth.authStateChanges()`: it replays the current state to
/// every new subscriber and then **stays open** for later changes.
///
/// The "stays open" half is what makes this test meaningful. `Stream.value()`
/// closes after emitting, and a closed stream makes `firstWhere` fail fast —
/// so a fake built on it would pass against the very bug this file exists to
/// catch. Only a live stream reproduces the hang.
class _AuthStateStream {
  _AuthStateStream(this._current);

  final User? _current;
  int listenCount = 0;
  final List<StreamController<User?>> _controllers = [];

  Stream<User?> call() {
    listenCount++;
    late StreamController<User?> controller;
    controller = StreamController<User?>(
      onListen: () => controller.add(_current),
    );
    _controllers.add(controller);
    return controller.stream;
  }

  Future<void> dispose() async {
    for (final c in _controllers) {
      await c.close();
    }
  }
}

class _FakeUser implements User {
  _FakeUser(this.token);

  final String token;
  bool? lastForceRefresh;

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    lastForceRefresh = forceRefresh;
    return token;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeFirebaseAuth implements FirebaseAuth {
  _FakeFirebaseAuth({User? currentUser, required _AuthStateStream stream})
      : _currentUser = currentUser,
        _stream = stream;

  final User? _currentUser;
  final _AuthStateStream _stream;

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<User?> authStateChanges() => _stream();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  group('AuthTokenService.getFirebaseToken — signed out', () {
    test('returns null promptly instead of waiting out the restore timeout',
        () async {
      // The regression. AuthInterceptor awaits this on EVERY request, and
      // onboarding runs entirely signed out (auth is the last step), so a
      // stall here is paid before the request is even sent.
      //
      // `authStateChanges()` replays `null` for a signed-out member.
      // `firstWhere((user) => user != null)` discarded that emission and,
      // because the stream stays open, blocked for the full 5s
      // `_sessionRestoreTimeout` before returning null anyway.
      final stream = _AuthStateStream(null);
      final service = AuthTokenService(_FakeFirebaseAuth(stream: stream));

      final stopwatch = Stopwatch()..start();
      final token = await service.getFirebaseToken();
      stopwatch.stop();

      expect(token, isNull);
      // Bound is deliberately far below the 5s timeout and far above what the
      // fixed path costs (~2ms), so it fails loudly on regression without
      // being flaky on a slow machine.
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(2000),
        reason: 'a signed-out lookup must not wait out _sessionRestoreTimeout',
      );

      await stream.dispose();
    });

    test('getBearerHeader is null and equally prompt', () async {
      final stream = _AuthStateStream(null);
      final service = AuthTokenService(_FakeFirebaseAuth(stream: stream));

      final stopwatch = Stopwatch()..start();
      final header = await service.getBearerHeader();
      stopwatch.stop();

      expect(header, isNull);
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));

      await stream.dispose();
    });
  });

  group('AuthTokenService.getFirebaseToken — signed in', () {
    test('returns the token for a session restored via authStateChanges',
        () async {
      // The window this wait exists to cover: `currentUser` is still null
      // because restore has not finished, but a real session is there and
      // arrives in the stream's first emission.
      final user = _FakeUser('restored-token');
      final stream = _AuthStateStream(user);
      final service = AuthTokenService(_FakeFirebaseAuth(stream: stream));

      await expectLater(service.getFirebaseToken(), completion('restored-token'));
      expect(stream.listenCount, 1);

      await stream.dispose();
    });

    test('returns the token from currentUser without touching the stream',
        () async {
      final user = _FakeUser('current-token');
      final stream = _AuthStateStream(null);
      final service = AuthTokenService(
        _FakeFirebaseAuth(currentUser: user, stream: stream),
      );

      expect(await service.getFirebaseToken(), 'current-token');
      // No restore wait is needed when the user is already there.
      expect(stream.listenCount, 0);

      await stream.dispose();
    });

    test('passes forceRefresh through to the user', () async {
      final user = _FakeUser('fresh-token');
      final stream = _AuthStateStream(null);
      final service = AuthTokenService(
        _FakeFirebaseAuth(currentUser: user, stream: stream),
      );

      expect(await service.getFirebaseToken(forceRefresh: true), 'fresh-token');
      expect(user.lastForceRefresh, isTrue);

      await stream.dispose();
    });

    test('getBearerHeader formats the Bearer prefix', () async {
      final user = _FakeUser('abc123');
      final stream = _AuthStateStream(null);
      final service = AuthTokenService(
        _FakeFirebaseAuth(currentUser: user, stream: stream),
      );

      expect(await service.getBearerHeader(), 'Bearer abc123');

      await stream.dispose();
    });
  });
}
