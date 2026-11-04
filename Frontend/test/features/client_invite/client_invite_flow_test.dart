import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/firebase_auth_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/client_invite/data/repositories/api_client_invite_repository.dart';
import 'package:nenjam_matrimony/features/client_invite/domain/models/client_invite_models.dart';
import 'package:nenjam_matrimony/features/client_invite/domain/repositories/client_invite_repository.dart';
import 'package:nenjam_matrimony/features/client_invite/presentation/pages/client_invite_page.dart';
import 'package:nenjam_matrimony/features/client_invite/presentation/providers/client_invite_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Way 2 client invitation flow, against fakes. This proves the app logic and
/// the wire shape of the requests; it is NOT a live backend or device test
/// (the feature switch is off and no approved test number was used).

const _secretToken = 'client-token-SECRET-123';
const _customToken = 'firebase-custom-token-456';

ClientInvite _invite(String id, String agent) => ClientInvite.tryFromJson({
  'id': id,
  'agentDisplayName': agent,
  'expiresOn': '2026-11-11',
  'referredMemberDiscountPercent': 5,
  'details': {
    'basicDetails': {'firstName': 'Priya', 'lastName': 'Sundaram'},
    'religionDetails': {
      'religionCode': 'HINDU',
      'religion': 'Hindu',
      'communityCode': 'HINDU-VELLALAR',
      'community': 'Vellalar',
    },
    'partnerPreference': {
      'preferredAgeRange': '26-30',
      'extended': {'diet': 'Vegetarian'},
    },
  },
})!;

class FakeInviteRepo implements ClientInviteRepository {
  final calls = <String>[];
  Object? otpError;
  Object? verifyError;
  Object? listError;
  Object? acceptError;
  Object? rejectError;
  List<ClientInvite> invites = [_invite('i1', 'Ravi K.')];
  String? customToken = _customToken;

  @override
  Future<ClientOtpChallenge> requestOtp(String phone) async {
    calls.add('otp:$phone');
    if (otpError != null) throw otpError!;
    return const ClientOtpChallenge(
      expiresInSeconds: 300,
      resendAfterSeconds: 30,
    );
  }

  @override
  Future<ClientAccessToken> verifyOtp(String phone, String code) async {
    calls.add('verify:$phone:$code');
    if (verifyError != null) throw verifyError!;
    return const ClientAccessToken(_secretToken);
  }

  @override
  Future<List<ClientInvite>> list(ClientAccessToken token) async {
    calls.add('list');
    if (listError != null) throw listError!;
    return invites;
  }

  @override
  Future<ClientAcceptResult> accept(ClientAccessToken token, String id) async {
    calls.add('accept:$id:${token.value == _secretToken}');
    final e = acceptError;
    if (e != null) {
      acceptError = null; // fail once, then succeed (retry tests)
      throw e;
    }
    return ClientAcceptResult(
      firebaseCustomToken: customToken,
      agentDisplayName: 'Ravi K.',
      windowEndsAt: '2026-12-27',
    );
  }

  @override
  Future<void> reject(ClientAccessToken token, String id) async {
    calls.add('reject:$id');
    if (rejectError != null) throw rejectError!;
  }
}

class _Credential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeAuth implements FirebaseAuthService {
  FakeAuth({this.signedIn = false});
  bool signedIn;
  final customTokens = <String>[];
  Object? signInError;

  @override
  User? get currentUser => signedIn ? _FakeUser() : null;

  @override
  Future<UserCredential> signInWithCustomToken(String token) async {
    customTokens.add(token);
    if (signInError != null) throw signInError!;
    return _Credential();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeUser implements User {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ApiException _api(int status, String code, {int? retry}) =>
    ApiException(status, 'x', code: code, retryAfterSeconds: retry);

void main() {
  late FakeInviteRepo repo;
  late FakeAuth auth;

  ProviderContainer make() {
    final c = ProviderContainer(
      overrides: [
        clientInviteRepositoryProvider.overrideWithValue(repo),
        firebaseAuthServiceProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(c.dispose);
    // Keep the auto-dispose notifier alive for the test.
    c.listen(clientInviteControllerProvider, (_, __) {});
    return c;
  }

  setUp(() {
    repo = FakeInviteRepo();
    auth = FakeAuth();
    SharedPreferences.setMockInitialValues({});
  });

  Future<ClientInviteController> toInvites(ProviderContainer c) async {
    final ctl = c.read(clientInviteControllerProvider.notifier);
    await ctl.requestCode('98765 43210');
    await ctl.verifyCode('123456');
    return ctl;
  }

  group('OTP', () {
    test('a bare 10-digit number becomes +91 E.164; a full one is kept', () {
      expect(
        ClientInviteController.normalizePhone('98765 43210'),
        '+919876543210',
      );
      expect(
        ClientInviteController.normalizePhone('+44 7700 900123'),
        '+447700900123',
      );
      expect(ClientInviteController.normalizePhone('12345'), isNull);
      expect(ClientInviteController.normalizePhone(''), isNull);
    });

    test('request then verify lists the invitations', () async {
      final c = make();
      await toInvites(c);
      final s = c.read(clientInviteControllerProvider);
      expect(s.step, ClientInviteStep.invites);
      expect(s.invites.single.agentDisplayName, 'Ravi K.');
      expect(repo.calls, [
        'otp:+919876543210',
        'verify:+919876543210:123456',
        'list',
      ]);
    });

    test('a bad phone is refused without a request', () async {
      final c = make();
      await c.read(clientInviteControllerProvider.notifier).requestCode('12');
      expect(
        c.read(clientInviteControllerProvider).issue,
        ClientInviteIssue.invalidPhone,
      );
      expect(repo.calls, isEmpty);
    });

    test('documented error codes map to their issue', () async {
      final cases = <ApiException, ClientInviteIssue>{
        _api(503, 'OTP_DELIVERY_UNAVAILABLE'): ClientInviteIssue.otpUnavailable,
        _api(429, 'RATE_LIMITED', retry: 12): ClientInviteIssue.rateLimited,
        _api(400, 'VALIDATION_FAILED'): ClientInviteIssue.validationFailed,
      };
      for (final e in cases.entries) {
        repo.otpError = e.key;
        final c = make();
        await c
            .read(clientInviteControllerProvider.notifier)
            .requestCode('9876543210');
        final s = c.read(clientInviteControllerProvider);
        expect(s.issue, e.value, reason: e.key.code);
        expect(s.step, ClientInviteStep.phone);
        if (e.value == ClientInviteIssue.rateLimited) {
          expect(s.retryAfterSeconds, 12);
        }
      }
      for (final e in {
        _api(401, 'OTP_INVALID'): ClientInviteIssue.otpInvalid,
        _api(401, 'OTP_EXPIRED'): ClientInviteIssue.otpExpired,
      }.entries) {
        repo.otpError = null;
        repo.verifyError = e.key;
        final c = make();
        final ctl = c.read(clientInviteControllerProvider.notifier);
        await ctl.requestCode('9876543210');
        await ctl.verifyCode('123456');
        final s = c.read(clientInviteControllerProvider);
        expect(s.issue, e.value);
        expect(
          s.step,
          ClientInviteStep.code,
          reason: 'stays on the code screen',
        );
      }
    });

    test('a malformed code is refused locally', () async {
      final c = make();
      final ctl = c.read(clientInviteControllerProvider.notifier);
      await ctl.requestCode('9876543210');
      await ctl.verifyCode('12ab');
      expect(
        c.read(clientInviteControllerProvider).issue,
        ClientInviteIssue.invalidCode,
      );
      expect(repo.calls.where((x) => x.startsWith('verify')), isEmpty);
    });
  });

  group('invitations', () {
    test('several invitations are all listed', () async {
      repo.invites = [_invite('a', 'Ravi K.'), _invite('b', 'Meena S.')];
      final c = make();
      await toInvites(c);
      expect(c.read(clientInviteControllerProvider).invites.map((i) => i.id), [
        'a',
        'b',
      ]);
    });

    test('no invitation is an empty list, not an error', () async {
      repo.invites = [];
      final c = make();
      await toInvites(c);
      final s = c.read(clientInviteControllerProvider);
      expect(s.step, ClientInviteStep.invites);
      expect(s.invites, isEmpty);
      expect(s.issue, isNull);
    });

    test('details: labels win over codes, partner preferences come last', () {
      final i = _invite('x', 'Ravi K.');
      expect(i.sections.map((s) => s.key), [
        'basicDetails',
        'religionDetails',
        'partnerPreference',
      ]);
      final religion = i.sections[1].rows.map((r) => r.value);
      expect(religion, ['Hindu', 'Vellalar']);
    });
  });

  group('accept', () {
    test('signs in with the custom token, drops the CLIENT state, and does '
        'nothing else', () async {
      final c = make();
      final ctl = await toInvites(c);
      await ctl.accept('i1');
      final s = c.read(clientInviteControllerProvider);
      expect(auth.customTokens, [_customToken]);
      expect(s.step, ClientInviteStep.signedIn);
      expect(s.agentDisplayName, 'Ravi K.');
      expect(s.invites, isEmpty);
      expect(s.phone, isNull);
      // Only the four documented calls: no profile/draft loading exists here.
      expect(repo.calls.last, 'accept:i1:true');
      // A further accept has no token left to use.
      await ctl.accept('i1');
      expect(repo.calls.where((x) => x.startsWith('accept')), hasLength(1));
    });

    test('a dropped connection can be retried with the same token', () async {
      repo.acceptError = const ClientInviteNetworkException();
      final c = make();
      final ctl = await toInvites(c);
      await ctl.accept('i1');
      expect(
        c.read(clientInviteControllerProvider).issue,
        ClientInviteIssue.network,
      );
      expect(
        c.read(clientInviteControllerProvider).step,
        ClientInviteStep.invites,
      );
      expect(auth.customTokens, isEmpty);

      await ctl.accept('i1');
      expect(
        c.read(clientInviteControllerProvider).step,
        ClientInviteStep.signedIn,
      );
      expect(auth.customTokens, [_customToken]);
    });

    test('a failed Firebase sign-in is retryable via accept again', () async {
      auth.signInError = FirebaseAuthException(code: 'network-request-failed');
      final c = make();
      final ctl = await toInvites(c);
      await ctl.accept('i1');
      expect(
        c.read(clientInviteControllerProvider).issue,
        ClientInviteIssue.signInFailed,
      );
      expect(
        c.read(clientInviteControllerProvider).step,
        ClientInviteStep.invites,
      );

      auth.signInError = null;
      await ctl.accept('i1');
      expect(
        c.read(clientInviteControllerProvider).step,
        ClientInviteStep.signedIn,
      );
      expect(repo.calls.where((x) => x.startsWith('accept')), hasLength(2));
    });

    test('a null custom token never signs anyone in', () async {
      repo.customToken = null;
      final c = make();
      final ctl = await toInvites(c);
      await ctl.accept('i1');
      expect(auth.customTokens, isEmpty);
      expect(
        c.read(clientInviteControllerProvider).issue,
        ClientInviteIssue.noSignInToken,
      );
      expect(
        c.read(clientInviteControllerProvider).step,
        ClientInviteStep.invites,
      );
    });

    test('a null custom token with a session already held keeps it', () async {
      repo.customToken = null;
      auth.signedIn = true;
      final c = make();
      final ctl = await toInvites(c);
      await ctl.accept('i1');
      expect(auth.customTokens, isEmpty);
      expect(
        c.read(clientInviteControllerProvider).step,
        ClientInviteStep.signedIn,
      );
    });

    test(
      'INVITE_UNAVAILABLE / INVITE_NOT_FOUND are shown, nothing signs in',
      () async {
        for (final e in {
          _api(409, 'INVITE_UNAVAILABLE'): ClientInviteIssue.inviteUnavailable,
          _api(404, 'INVITE_NOT_FOUND'): ClientInviteIssue.inviteNotFound,
        }.entries) {
          repo.acceptError = e.key;
          final c = make();
          final ctl = await toInvites(c);
          await ctl.accept('i1');
          expect(c.read(clientInviteControllerProvider).issue, e.value);
          expect(auth.customTokens, isEmpty);
        }
      },
    );

    test(
      'ALREADY_MEMBER drops the CLIENT token and points to sign-in',
      () async {
        repo.acceptError = _api(409, 'ALREADY_MEMBER');
        final c = make();
        final ctl = await toInvites(c);
        await ctl.accept('i1');
        expect(
          c.read(clientInviteControllerProvider).issue,
          ClientInviteIssue.alreadyMember,
        );
        expect(auth.customTokens, isEmpty);
        // Token is gone: another accept cannot happen.
        await ctl.accept('i1');
        expect(repo.calls.where((x) => x.startsWith('accept')), hasLength(1));
      },
    );

    test(
      'an expired CLIENT token sends her back to the phone screen',
      () async {
        repo.acceptError = _api(401, 'TOKEN_EXPIRED');
        final c = make();
        final ctl = await toInvites(c);
        await ctl.accept('i1');
        final s = c.read(clientInviteControllerProvider);
        expect(s.issue, ClientInviteIssue.sessionExpired);
        expect(s.step, ClientInviteStep.phone);
        expect(s.invites, isEmpty);
      },
    );
  });

  group('reject', () {
    test('calls reject, removes the card and keeps her signed out', () async {
      repo.invites = [_invite('a', 'Ravi K.'), _invite('b', 'Meena S.')];
      final c = make();
      final ctl = await toInvites(c);
      await ctl.reject('a');
      final s = c.read(clientInviteControllerProvider);
      expect(repo.calls, contains('reject:a'));
      expect(s.invites.map((i) => i.id), ['b']);
      expect(s.step, ClientInviteStep.invites);
      expect(auth.customTokens, isEmpty);
    });

    test('an already-closed invitation is reported', () async {
      repo.rejectError = _api(409, 'INVITE_UNAVAILABLE');
      final c = make();
      final ctl = await toInvites(c);
      await ctl.reject('i1');
      expect(
        c.read(clientInviteControllerProvider).issue,
        ClientInviteIssue.inviteUnavailable,
      );
    });
  });

  group('feature disabled', () {
    test(
      'CLIENT_INVITES_DISABLED flips the flag that hides the entry',
      () async {
        repo.otpError = _api(403, 'CLIENT_INVITES_DISABLED');
        final c = make();
        expect(c.read(clientInvitesDisabledProvider), isFalse);
        await c
            .read(clientInviteControllerProvider.notifier)
            .requestCode('9876543210');
        expect(c.read(clientInvitesDisabledProvider), isTrue);
        expect(
          c.read(clientInviteControllerProvider).issue,
          ClientInviteIssue.featureDisabled,
        );
      },
    );
  });

  group('CLIENT token handling', () {
    test('never in state, toString, or SharedPreferences', () async {
      final c = make();
      final ctl = await toInvites(c);
      await ctl.accept('i1');
      expect(
        const ClientAccessToken(_secretToken).toString(),
        isNot(contains(_secretToken)),
      );
      expect(
        c.read(clientInviteControllerProvider).toString(),
        isNot(contains(_secretToken)),
      );
      expect(
        ClientAcceptResult.fromJson({
          'firebaseCustomToken': _customToken,
        }).toString(),
        isNot(contains(_customToken)),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('startOver forgets the token', () async {
      final c = make();
      final ctl = await toInvites(c);
      ctl.startOver();
      await ctl.accept('i1');
      expect(repo.calls.where((x) => x.startsWith('accept')), isEmpty);
    });
  });

  group('wire shape (ApiClientInviteRepository)', () {
    late _Recorder recorder;
    late ApiClientInviteRepository api;

    setUp(() {
      recorder = _Recorder();
      final client = ApiClient();
      client.dio.httpClientAdapter = recorder;
      api = ApiClientInviteRepository(client);
    });

    test('sends the documented paths, bodies and headers; Bearer only '
        'after verify; never touches /profiles', () async {
      recorder.responses = [
        (200, {'expiresInSeconds': 300, 'resendAfterSeconds': 30}),
        (
          200,
          {
            'accessToken': _secretToken,
            'expiresInSeconds': 900,
            'scope': 'CLIENT',
          },
        ),
        (
          200,
          {
            'items': [
              {
                'id': 'i1',
                'agentDisplayName': 'Ravi K.',
                'details': <String, Object?>{},
                'expiresOn': '2026-11-11',
                'referredMemberDiscountPercent': 5,
              },
            ],
          },
        ),
        (
          200,
          {
            'firebaseCustomToken': _customToken,
            'agentDisplayName': 'Ravi K.',
            'windowEndsAt': '2026-12-27',
          },
        ),
        (204, null),
      ];
      await api.requestOtp('+919876543210');
      final token = await api.verifyOtp('+919876543210', '123456');
      await api.list(token);
      final accepted = await api.accept(token, 'i1');
      await api.reject(token, 'i1');

      final r = recorder.requests;
      expect(r.map((x) => '${x.method} ${x.path}'), [
        'POST /client-invites/otp/request',
        'POST /client-invites/otp/verify',
        'GET /client-invites',
        'POST /client-invites/i1/accept',
        'POST /client-invites/i1/reject',
      ]);
      expect(r[0].data, {'phone': '+919876543210'});
      expect(r[1].data, {'phone': '+919876543210', 'code': '123456'});
      for (final x in r) {
        expect(x.headers['Accept-Version'], '1');
        expect(x.path, isNot(contains('/profiles')));
      }
      expect(r[0].headers.containsKey('Authorization'), isFalse);
      expect(r[1].headers.containsKey('Authorization'), isFalse);
      for (final x in r.skip(2)) {
        expect(x.headers['Authorization'], 'Bearer $_secretToken');
      }
      expect(accepted.firebaseCustomToken, _customToken);
    });

    test('refusals carry their contract code; 429 reads Retry-After; '
        'no response is a network error', () async {
      recorder.responses = [
        (409, {'statusCode': 409, 'code': 'ALREADY_MEMBER', 'message': 'm'}),
        (
          503,
          {
            'statusCode': 503,
            'code': 'OTP_DELIVERY_UNAVAILABLE',
            'message': 'm',
          },
        ),
        (429, {'statusCode': 429, 'code': 'RATE_LIMITED', 'message': 'm'}),
      ];
      recorder.retryAfter = '17';
      await expectLater(
        api.accept(const ClientAccessToken(_secretToken), 'i1'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'ALREADY_MEMBER'),
        ),
      );
      await expectLater(
        api.requestOtp('+919876543210'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'OTP_DELIVERY_UNAVAILABLE',
          ),
        ),
      );
      await expectLater(
        api.requestOtp('+919876543210'),
        throwsA(
          isA<ApiException>().having((e) => e.retryAfterSeconds, 'retry', 17),
        ),
      );
      recorder.responses = [];
      recorder.fail = true;
      await expectLater(
        api.requestOtp('+919876543210'),
        throwsA(isA<ClientInviteNetworkException>()),
      );
    });
  });

  group('page', () {
    Widget host(ProviderContainer c, {GoRouter? router}) {
      return UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
          routerConfig:
              router ??
              GoRouter(
                initialLocation: RouteNames.clientInvite,
                routes: [
                  GoRoute(
                    path: RouteNames.clientInvite,
                    builder: (_, __) => const ClientInvitePage(),
                  ),
                  GoRoute(
                    path: '/other',
                    builder: (_, __) => const Scaffold(body: Text('navigated')),
                  ),
                ],
              ),
        ),
      );
    }

    testWidgets('full happy path ends on a signed-in message with no '
        'navigation', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = make();
      await tester.pumpWidget(host(c));

      await tester.enterText(find.byType(TextFormField), '9876543210');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Enter the code for +919876543210'),
        findsOneWidget,
      );
      // No promise of a real SMS.
      expect(find.textContaining('SMS'), findsNothing);

      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(find.text('Ravi K. added you'), findsOneWidget);
      expect(
        find.text('Hindu'),
        findsNothing,
        reason: 'rows are "Label: value"',
      );
      expect(find.textContaining('Religion: Hindu'), findsOneWidget);
      expect(find.text('5% off your first plan'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(find.text("You're signed in."), findsOneWidget);
      expect(find.text('navigated'), findsNothing);
      expect(auth.customTokens, [_customToken]);
    });

    testWidgets('decline asks first, then calls reject', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = make();
      await tester.pumpWidget(host(c));
      await tester.enterText(find.byType(TextFormField), '9876543210');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining("They won't be able to add your number again"),
        findsOneWidget,
      );
      expect(repo.calls, isNot(contains('reject:i1')));
      await tester.tap(find.widgetWithText(TextButton, 'Decline').last);
      await tester.pumpAndSettle();
      expect(repo.calls, contains('reject:i1'));
      expect(
        find.text("There's no invitation for this number."),
        findsOneWidget,
      );
      expect(auth.customTokens, isEmpty);
    });

    testWidgets('ALREADY_MEMBER offers the normal sign-in', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repo.acceptError = _api(409, 'ALREADY_MEMBER');
      final c = make();
      await tester.pumpWidget(host(c));
      await tester.enterText(find.byType(TextFormField), '9876543210');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('already has a Nenjam account'),
        findsOneWidget,
      );
      expect(find.text('Go to sign in'), findsOneWidget);
    });
  });
}

class _Recorded {
  _Recorded(this.method, this.path, this.headers, this.data);
  final String method;
  final String path;
  final Map<String, dynamic> headers;
  final Object? data;
}

class _Recorder implements HttpClientAdapter {
  final requests = <_Recorded>[];
  List<(int, Object?)> responses = [];
  String? retryAfter;
  bool fail = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      _Recorded(
        options.method,
        options.path,
        Map<String, dynamic>.from(options.headers),
        options.data,
      ),
    );
    if (fail || responses.isEmpty) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final (status, body) = responses.removeAt(0);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        if (status == 429 && retryAfter != null) 'retry-after': [retryAfter!],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
