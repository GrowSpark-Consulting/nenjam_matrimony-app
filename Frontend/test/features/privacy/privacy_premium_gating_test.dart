import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/privacy/presentation/pages/privacy_page.dart';
import 'package:nenjam_matrimony/features/safety/domain/entities/blocked_user_entity.dart';
import 'package:nenjam_matrimony/features/safety/presentation/providers/blocked_users_provider.dart';
import 'package:nenjam_matrimony/features/settings/domain/repositories/settings_repository.dart';
import 'package:nenjam_matrimony/features/settings/presentation/providers/settings_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Both Privacy visibility toggles are premium features enforced by the
/// backend. The page must reflect that honestly: a non-premium member sees
/// them locked and off with an upgrade prompt — never a switch that looks on
/// while the backend ignores it — and a premium member can change them.
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
          path: RouteNames.premium,
          builder: (_, __) => const Scaffold(body: Text('stub premium')),
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

  testWidgets(
    'non-premium: both toggles locked and off, upgrade prompt shown',
    (tester) async {
      // Even if a payload claimed a flag was on, a non-premium member must not
      // see it as on — the backend ignores it.
      final repository = await pump(tester, {
        'isPremium': false,
        'hideMyProfile': true,
        'hidePhotosFromNonConnections': true,
      });

      expect(
        find.byKey(const ValueKey('privacy-premium-locked')),
        findsOneWidget,
      );
      final all = switches(tester);
      expect(all, hasLength(2));
      for (final s in all) {
        expect(s.value, isFalse);
        expect(s.onChanged, isNull, reason: 'locked for non-premium members');
      }

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(repository.patches, isEmpty);
    },
  );

  testWidgets('a response without isPremium (older backend) stays locked', (
    tester,
  ) async {
    await pump(tester, {'profileVisibleToPremiumOnly': true});

    expect(
      find.byKey(const ValueKey('privacy-premium-locked')),
      findsOneWidget,
    );
    for (final s in switches(tester)) {
      expect(s.value, isFalse);
      expect(s.onChanged, isNull);
    }
  });

  testWidgets('the upgrade prompt opens Premium', (tester) async {
    await pump(tester, {'isPremium': false});

    await tester.tap(find.text('Upgrade to Premium'));
    await tester.pumpAndSettle();

    expect(find.text('stub premium'), findsOneWidget);
  });

  testWidgets('premium: toggles reflect the backend state and are enabled', (
    tester,
  ) async {
    await pump(tester, {
      'isPremium': true,
      'hideMyProfile': true,
      'hidePhotosFromNonConnections': false,
    });

    expect(find.byKey(const ValueKey('privacy-premium-locked')), findsNothing);
    final all = switches(tester);
    expect(all.map((s) => s.value), [true, false]);
    for (final s in all) {
      expect(s.onChanged, isNotNull);
    }
  });

  testWidgets(
    'premium: switching Hide My Profile persists it and re-reads the backend',
    (tester) async {
      final repository = await pump(tester, {
        'isPremium': true,
        'hideMyProfile': false,
        'hidePhotosFromNonConnections': false,
      });

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(repository.patches, [
        {'hideMyProfile': true},
      ]);
      // Reloaded from the (fake) backend, not flipped locally.
      expect(repository.reads, greaterThanOrEqualTo(2));
      expect(switches(tester).first.value, isTrue);
    },
  );

  testWidgets('premium: switching photo privacy sends only that key', (
    tester,
  ) async {
    final repository = await pump(tester, {
      'isPremium': true,
      'hideMyProfile': false,
      'hidePhotosFromNonConnections': false,
    });

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();

    expect(repository.patches, [
      {'hidePhotosFromNonConnections': true},
    ]);
  });
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(Map<String, dynamic> initial)
    : _state = Map<String, dynamic>.of(initial);

  Map<String, dynamic> _state;
  final List<Map<String, dynamic>> patches = [];
  int reads = 0;

  @override
  Future<Map<String, dynamic>> getSettings({CancelToken? cancelToken}) async {
    reads++;
    return Map<String, dynamic>.of(_state);
  }

  @override
  Future<void> updatePrivacySettings(Map<String, dynamic> settings) async {
    patches.add(Map<String, dynamic>.of(settings));
    _state = {..._state, ...settings};
  }

  @override
  Future<void> deleteAccount() async {}
}

class _NoBlockedUsers extends BlockedUsersNotifier {
  @override
  Future<List<BlockedUserEntity>> build() async => [];
}
