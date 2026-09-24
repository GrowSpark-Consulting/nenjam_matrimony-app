import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/privacy/presentation/pages/privacy_page.dart';
import 'package:nenjam_matrimony/features/safety/domain/entities/blocked_user_entity.dart';
import 'package:nenjam_matrimony/features/safety/presentation/providers/blocked_users_provider.dart';
import 'package:nenjam_matrimony/features/settings/domain/repositories/settings_repository.dart';
import 'package:nenjam_matrimony/features/settings/presentation/providers/settings_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Both Privacy visibility toggles are temporarily open to every member
/// (backend `ALLOW_FREE_PRIVACY_CONTROLS`), premium or not. Whatever the
/// server returns is what the switches show; a save disables the switch until
/// the server answers and rolls back if it fails.
void main() {
  Future<_FakeSettingsRepository> pump(
    WidgetTester tester,
    Map<String, dynamic> settings,
  ) async {
    final repository = _FakeSettingsRepository(settings);
    final router = GoRouter(
      initialLocation: RouteNames.discover,
      routes: [
        GoRoute(
          path: RouteNames.discover,
          builder: (_, __) => const Scaffold(body: Text('stub discover')),
        ),
        GoRoute(
          path: RouteNames.privacy,
          builder: (_, __) => const PrivacyPage(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repository),
          blockedUsersNotifierProvider.overrideWith(_NoBlockedUsers.new),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push(RouteNames.privacy);
    await tester.pumpAndSettle();
    return repository;
  }

  List<Switch> switches(WidgetTester tester) =>
      tester.widgetList<Switch>(find.byType(Switch)).toList();
  Switch profileSwitch(WidgetTester tester) => switches(tester).first;
  Switch photoSwitch(WidgetTester tester) => switches(tester).last;
  Finder profileToggle() => find.byType(Switch).first;
  Finder photoToggle() => find.byType(Switch).last;

  const free = {
    'isPremium': false,
    'hideMyProfile': false,
    'hidePhotosFromNonConnections': false,
  };

  testWidgets('free member: both toggles enabled, no premium lock or upsell', (
    tester,
  ) async {
    await pump(tester, free);

    final all = switches(tester);
    expect(all, hasLength(2));
    for (final s in all) {
      expect(s.value, isFalse);
      expect(s.onChanged, isNotNull);
    }
    expect(find.text('Upgrade to Premium'), findsNothing);
    expect(find.text('Premium privacy controls'), findsNothing);
    expect(find.textContaining('Premium membership'), findsNothing);
  });

  testWidgets('free member: both toggles show the server values', (
    tester,
  ) async {
    await pump(tester, {
      'isPremium': false,
      'hideMyProfile': true,
      'hidePhotosFromNonConnections': true,
    });

    expect(switches(tester).map((s) => s.value), [true, true]);
  });

  testWidgets('premium member: same toggles, same behaviour', (tester) async {
    await pump(tester, {
      'isPremium': true,
      'hideMyProfile': true,
      'hidePhotosFromNonConnections': false,
    });

    expect(switches(tester).map((s) => s.value), [true, false]);
    for (final s in switches(tester)) {
      expect(s.onChanged, isNotNull);
    }
  });

  testWidgets('Hide My Profile: ON sends true, OFF sends false', (
    tester,
  ) async {
    final repository = await pump(tester, free);

    await tester.tap(profileToggle());
    await tester.pumpAndSettle();
    expect(profileSwitch(tester).value, isTrue);

    await tester.tap(profileToggle());
    await tester.pumpAndSettle();
    expect(profileSwitch(tester).value, isFalse);

    expect(repository.patches, [
      {'hideMyProfile': true},
      {'hideMyProfile': false},
    ]);
    expect(repository.reads, 1, reason: 'the PATCH response is the state');
  });

  testWidgets('Hide Photos: ON sends true, OFF sends false', (tester) async {
    final repository = await pump(tester, free);

    await tester.tap(photoToggle());
    await tester.pumpAndSettle();
    expect(photoSwitch(tester).value, isTrue);

    await tester.tap(photoToggle());
    await tester.pumpAndSettle();
    expect(photoSwitch(tester).value, isFalse);

    expect(repository.patches, [
      {'hidePhotosFromNonConnections': true},
      {'hidePhotosFromNonConnections': false},
    ]);
  });

  testWidgets('both can be switched on, each sending only its own key', (
    tester,
  ) async {
    final repository = await pump(tester, free);

    await tester.tap(profileToggle());
    await tester.pumpAndSettle();
    await tester.tap(photoToggle());
    await tester.pumpAndSettle();

    expect(switches(tester).map((s) => s.value), [true, true]);
    expect(repository.patches, [
      {'hideMyProfile': true},
      {'hidePhotosFromNonConnections': true},
    ]);
  });

  testWidgets('shows the value the server confirmed, not the one requested', (
    tester,
  ) async {
    final repository = await pump(tester, free);
    repository.response = Map<String, dynamic>.of(free);

    await tester.tap(photoToggle());
    await tester.pumpAndSettle();

    expect(photoSwitch(tester).value, isFalse);
  });

  testWidgets(
    'while saving, the switch shows the pending value and ignores more taps',
    (tester) async {
      final repository = await pump(tester, free);
      final gate = repository.gate = Completer<void>();

      await tester.tap(photoToggle());
      await tester.pump();

      expect(photoSwitch(tester).value, isTrue);
      expect(photoSwitch(tester).onChanged, isNull);
      // The other toggle is not blocked by this one's save.
      expect(profileSwitch(tester).onChanged, isNotNull);

      await tester.tap(photoToggle());
      await tester.pump();
      expect(repository.patches, hasLength(1));

      gate.complete();
      await tester.pumpAndSettle();
      expect(photoSwitch(tester).value, isTrue);
      expect(photoSwitch(tester).onChanged, isNotNull);
    },
  );

  for (final (label, toggle, value) in [
    ('Hide My Profile', 0, profileSwitch),
    ('Hide Photos', 1, photoSwitch),
  ]) {
    testWidgets('$label: a failed save rolls back and says so', (tester) async {
      final repository = await pump(tester, free);
      repository.failWith = ApiException(500, 'Internal server error');

      await tester.tap(find.byType(Switch).at(toggle));
      await tester.pumpAndSettle();

      expect(value(tester).value, isFalse);
      expect(value(tester).onChanged, isNotNull);
      expect(
        find.text("Couldn't save your changes. Please try again."),
        findsOneWidget,
      );
    });
  }

  testWidgets('a 403 is handled like any failed save: rolled back', (
    tester,
  ) async {
    final repository = await pump(tester, free);
    repository.failWith = ApiException(403, 'Forbidden');

    await tester.tap(photoToggle());
    await tester.pumpAndSettle();

    expect(photoSwitch(tester).value, isFalse);
    expect(
      find.text("Couldn't save your changes. Please try again."),
      findsOneWidget,
    );
  });
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(Map<String, dynamic> initial)
    : state = Map<String, dynamic>.of(initial);

  /// What the next `GET /settings` returns.
  Map<String, dynamic> state;
  final List<Map<String, dynamic>> patches = [];
  int reads = 0;

  /// When set, `PATCH` waits on it — to observe the in-flight UI.
  Completer<void>? gate;

  /// When set, `PATCH` throws it instead of saving.
  Object? failWith;

  /// When set, `PATCH` answers with this instead of the merged state.
  Map<String, dynamic>? response;

  @override
  Future<Map<String, dynamic>> getSettings({CancelToken? cancelToken}) async {
    reads++;
    return Map<String, dynamic>.of(state);
  }

  @override
  Future<Map<String, dynamic>> updatePrivacySettings(
    Map<String, dynamic> settings,
  ) async {
    patches.add(Map<String, dynamic>.of(settings));
    await gate?.future;
    final failure = failWith;
    if (failure != null) throw failure;
    state = response ?? {...state, ...settings};
    return Map<String, dynamic>.of(state);
  }

  @override
  Future<void> deleteAccount() async {}
}

class _NoBlockedUsers extends BlockedUsersNotifier {
  @override
  Future<List<BlockedUserEntity>> build() async => [];
}
