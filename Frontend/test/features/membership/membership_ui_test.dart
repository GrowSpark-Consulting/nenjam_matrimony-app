import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/membership/data/repositories/mock_membership_repository.dart';
import 'package:nenjam_matrimony/features/membership/domain/models/membership_models.dart';
import 'package:nenjam_matrimony/features/membership/presentation/pages/membership_history_page.dart';
import 'package:nenjam_matrimony/features/membership/presentation/providers/membership_providers.dart';
import 'package:nenjam_matrimony/features/membership/presentation/widgets/membership_denial_sheet.dart';
import 'package:nenjam_matrimony/features/membership/presentation/widgets/membership_status_card.dart';
import 'package:nenjam_matrimony/features/profile_photos/data/repositories/photo_repository.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import '../../support/responsive_harness.dart';

final _en = lookupAppLocalizations(const Locale('en'));

MyMembership _me(Map<String, dynamic> overrides) => MyMembership.fromJson({
  ...MockMembershipRepository.freeMeJson,
  ...overrides,
});

void main() {
  group('profilePhotoCapProvider (effectiveCaps["profile.photos"])', () {
    Future<int?> capFor(MyMembership me) async {
      final container = ProviderContainer(
        overrides: [
          membershipRepositoryProvider.overrideWithValue(
            MockMembershipRepository(me: me),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(myMembershipProvider.future);
      return container.read(profilePhotoCapProvider);
    }

    test('follows the server: 6 today, 15 / 20 under enforce', () async {
      expect(await capFor(_me({})), 6);
      expect(
        await capFor(
          _me({
            'effectiveCaps': {'profile.photos': 15},
          }),
        ),
        15,
      );
      expect(
        await capFor(
          _me({
            'effectiveCaps': {'profile.photos': 20},
          }),
        ),
        20,
      );
    });

    test('null from the server means no cap', () async {
      expect(
        await capFor(
          _me({
            'effectiveCaps': {'profile.photos': null},
          }),
        ),
        isNull,
      );
    });

    test('before /me answers, the pre-membership cap applies', () {
      final container = ProviderContainer(
        overrides: [
          membershipRepositoryProvider.overrideWithValue(
            MockMembershipRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(profilePhotoCapProvider), kPreMembershipPhotoCap);
    });
  });

  group('membership 403 handling', () {
    ApiException denial({
      String code = 'MEMBERSHIP_LIMIT_REACHED',
      String? up,
    }) => ApiException(
      403,
      'You have used all 5 interests.',
      code: code,
      upgradeTo: up,
    );
    final checkoutOn = _me({'checkoutAvailable': true});

    test('only MEMBERSHIP_ codes count; the account 403 has no code', () {
      expect(membershipDenialOf(denial()), isNotNull);
      expect(membershipDenialOf(ApiException(403, 'Account inactive')), isNull);
      expect(
        membershipDenialOf(ApiException(429, 'x', code: 'ATTEMPT_LIMIT')),
        isNull,
      );
      expect(membershipDenialOf(Exception('x')), isNull);
      // Photo uploads throw PhotoApiException — still recognised.
      expect(
        membershipDenialOf(
          PhotoApiException(403, 'x', code: 'MEMBERSHIP_LIMIT_REACHED'),
        ),
        isNotNull,
      );
    });

    test('upgrade only with upgradeTo AND checkout available', () {
      expect(mayOfferUpgrade(denial(up: 'GOLD'), checkoutOn), isTrue);
      expect(mayOfferUpgrade(denial(), checkoutOn), isFalse);
      expect(mayOfferUpgrade(denial(up: 'GOLD'), _me({})), isFalse);
      expect(mayOfferUpgrade(denial(up: 'GOLD'), null), isFalse);
    });

    test('never for fair use, LEGACY or UNAVAILABLE', () {
      expect(
        mayOfferUpgrade(
          denial(code: 'MEMBERSHIP_FAIR_USE_LIMIT', up: 'GOLD'),
          checkoutOn,
        ),
        isFalse,
      );
      for (final source in ['LEGACY', 'UNAVAILABLE']) {
        expect(
          mayOfferUpgrade(
            denial(up: 'GOLD'),
            _me({'checkoutAvailable': true, 'source': source}),
          ),
          isFalse,
          reason: source,
        );
      }
    });

    testWidgets('sheet shows the server sentence and reset date', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MembershipDenialSheet(
              denial: ApiException(
                403,
                'You have used all 5 interests.',
                code: 'MEMBERSHIP_LIMIT_REACHED',
                resetsAt: DateTime.utc(2026, 10, 31, 18, 30),
              ),
              offerUpgrade: false,
            ),
          ),
        ),
      );
      expect(find.text('You have used all 5 interests.'), findsOneWidget);
      expect(find.textContaining('Your allowance resets on'), findsOneWidget);
      expect(find.text(_en.membershipDenialSeePlans), findsNothing);
    });
  });

  group('MembershipStatusCard (GET /membership/me)', () {
    Future<void> pumpCard(WidgetTester tester, MyMembership me) async {
      expectNoOverflowIn(
        await pumpAtSize(
          tester,
          const Size(320, 700),
          const Center(child: MembershipStatusCard()),
          overrides: [
            membershipRepositoryProvider.overrideWithValue(
              MockMembershipRepository(me: me),
            ),
          ],
        ),
      );
    }

    testWidgets('Free member, nothing on sale', (tester) async {
      await pumpCard(tester, _me({}));
      expect(find.text(_en.membershipCardFreeTitle), findsOneWidget);
      expect(find.text(_en.membershipCardFreeSubtitleSoon), findsOneWidget);
      expect(find.textContaining('Elite'), findsNothing);
    });

    testWidgets('paid plan shows its name and end date', (tester) async {
      await pumpCard(
        tester,
        _me({
          'source': 'SUBSCRIPTION',
          'plan': {'code': 'GOLD', 'name': 'Gold'},
          'subscription': {
            'id': 's1',
            'planCode': 'GOLD',
            'endDate': '2027-01-25T06:00:00.000Z',
          },
        }),
      );
      expect(find.text(_en.membershipCardPlanTitle('Gold')), findsOneWidget);
      expect(find.textContaining('Active until'), findsOneWidget);
    });
  });

  group('MembershipHistoryPage (GET /membership/history)', () {
    testWidgets('empty history says so', (tester) async {
      await pumpAtSize(
        tester,
        const Size(390, 800),
        const MembershipHistoryPage(),
        overrides: [
          membershipRepositoryProvider.overrideWithValue(
            MockMembershipRepository(),
          ),
        ],
      );
      expect(find.text(_en.membershipHistoryEmpty), findsOneWidget);
    });

    for (final locale in const [Locale('en'), Locale('ta')]) {
      testWidgets('items: status, months, ₹ (${locale.languageCode})', (
        tester,
      ) async {
        final l10n = lookupAppLocalizations(locale);
        expectNoOverflowIn(
          await pumpAtSize(
            tester,
            const Size(320, 700),
            const MembershipHistoryPage(),
            locale: locale,
            overrides: [
              membershipRepositoryProvider.overrideWithValue(
                MockMembershipRepository(
                  history: [
                    MembershipHistoryItem.fromJson({
                      'id': 'h1',
                      'plan': {'code': 'GOLD', 'name': 'Gold'},
                      'months': 3,
                      'status': 'PENDING',
                      'source': 'PURCHASE',
                      'priceInPaise': 399950,
                      'currency': 'INR',
                    }),
                    MembershipHistoryItem.fromJson({
                      'id': 'h2',
                      'plan': {'code': 'PLATINUM', 'name': 'Platinum'},
                      'status': 'CANCELLED',
                      'cancellationReason': 'REVOKED',
                      'source': 'ADMIN_GRANT',
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
        expect(find.text(l10n.membershipStatusPending), findsOneWidget);
        expect(find.text(l10n.membershipStatusRevoked), findsOneWidget);
        expect(find.textContaining('₹3,999.50'), findsOneWidget);
        expect(find.textContaining(l10n.membershipSourceGrant), findsOneWidget);
      });
    }
  });
}
