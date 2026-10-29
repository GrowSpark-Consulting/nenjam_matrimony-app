import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/buttons/gradient_button.dart';
import 'package:nenjam_matrimony/core/widgets/cards/subscription_card.dart';
import 'package:nenjam_matrimony/features/membership/data/repositories/mock_membership_repository.dart';
import 'package:nenjam_matrimony/features/membership/domain/models/membership_models.dart';
import 'package:nenjam_matrimony/features/membership/domain/repositories/membership_repository.dart';
import 'package:nenjam_matrimony/features/membership/presentation/providers/membership_providers.dart';
import 'package:nenjam_matrimony/features/premium/presentation/pages/premium_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import '../../support/responsive_harness.dart';

/// The Premium tab is driven by `GET /membership/plans` and `/me`. Today the
/// backend has no prices and `checkoutAvailable: false`, so it must show the
/// honest coming-soon state and no plans at all; plans appear only when the
/// API says something is on sale.
void main() {
  /// Every string the old hardcoded plan cards rendered, plus the old labels.
  const removedStrings = [
    'Gold Luxury',
    'Platinum VIP',
    '₹4,999',
    '₹9,999',
    '3 Months',
    '6 Months',
    'Send 100 direct messages',
    'View 50 verified contact numbers',
    'AI Compatibility & Horoscope report',
    'Priority profile listing',
    'Unlimited direct messages',
    'Unlimited contact views',
    'Dedicated Relationship Manager',
    'Guaranteed top tier placement',
    'Proceed to Payment',
    'கட்டணத்திற்குத் தொடரவும்',
    'Luxury Premium',
    'சொகுசு பிரீமியத்திற்கு',
    'for information only',
    'தகவலுக்காக மட்டுமே',
  ];

  Future<List<Object>> pump(
    WidgetTester tester, {
    MembershipRepository? repo,
    Size size = const Size(390, 800),
    Locale locale = const Locale('en'),
  }) => pumpAtSize(
    tester,
    size,
    const PremiumPage(),
    locale: locale,
    overrides: [
      membershipRepositoryProvider.overrideWithValue(
        repo ?? MockMembershipRepository(),
      ),
    ],
  );

  group('coming soon (empty durations, checkoutAvailable: false)', () {
    for (final locale in const [Locale('en'), Locale('ta')]) {
      for (final width in const [320.0, 480.0]) {
        testWidgets('shows only the unavailable state '
            '(${locale.languageCode} @ ${width.toInt()})', (tester) async {
          expectNoOverflowIn(
            await pump(tester, size: Size(width, 800), locale: locale),
          );
          final l10n = lookupAppLocalizations(locale);

          expect(find.byType(NmSubscriptionCard), findsNothing);
          expect(find.textContaining('₹'), findsNothing);
          for (final text in removedStrings) {
            expect(find.textContaining(text), findsNothing, reason: text);
          }
          // The catalogue's plan names are not shown either: nothing is on
          // sale, so no plan is presented.
          expect(find.text('Gold'), findsNothing);
          expect(find.text('Platinum'), findsNothing);

          expect(find.text(l10n.premiumUnavailableNotice), findsOneWidget);
          final button = tester.widget<NmGradientButton>(
            find.byType(NmGradientButton),
          );
          expect(button.label, l10n.premiumComingSoon);
          expect(button.onPressed, isNull);
          expect(find.text(l10n.membershipHistoryTitle), findsOneWidget);
        });
      }
    }

    testWidgets('checkout on but no priced length is still coming soon', (
      tester,
    ) async {
      final json = Map<String, dynamic>.from(MockMembershipRepository.plansJson)
        ..['checkoutAvailable'] = true;
      await pump(
        tester,
        repo: MockMembershipRepository(
          catalog: MembershipCatalog.fromJson(json),
        ),
      );
      expect(find.text('Gold'), findsNothing);
      expect(
        find.text(lookupAppLocalizations(const Locale('en')).premiumComingSoon),
        findsOneWidget,
      );
    });
  });

  group('plans on sale (API-driven)', () {
    MockMembershipRepository onSale({bool checkoutAvailable = true}) {
      final plans = (MockMembershipRepository.plansJson['plans'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      plans[1]['durations'] = [
        {
          'months': 3,
          'durationDays': 90,
          'bonusDays': 0,
          'priceInPaise': 399900,
          'currency': 'INR',
        },
      ];
      plans[1]['entitlements'] = {
        'interests.send': {'limit': null},
        'chat.initiate': true,
      };
      final me = Map<String, dynamic>.from(MockMembershipRepository.freeMeJson)
        ..['checkoutAvailable'] = checkoutAvailable
        ..['purchaseOptions'] = [
          {
            'planCode': 'GOLD',
            'planName': 'Gold',
            'months': 3,
            'priceInPaise': 399900,
            'currency': 'INR',
            'kind': 'NEW',
          },
        ];
      return MockMembershipRepository(
        catalog: MembershipCatalog.fromJson({
          ...MockMembershipRepository.plansJson,
          'checkoutAvailable': checkoutAvailable,
          'plans': plans,
        }),
        me: MyMembership.fromJson(me),
      );
    }

    testWidgets('renders plans, labels, entitlements and ₹ from paise', (
      tester,
    ) async {
      expectNoOverflowIn(await pump(tester, repo: onSale()));
      final l10n = lookupAppLocalizations(const Locale('en'));

      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Gold'), findsOneWidget);
      expect(find.text(l10n.membershipCurrentPlan), findsOneWidget);
      // Feature labels come from the API.
      expect(find.text('Sending interests'), findsNWidgets(2));
      expect(find.text(l10n.membershipFeaturePerMonth(5)), findsOneWidget);
      expect(find.text(l10n.membershipFeatureUnlimited), findsOneWidget);
      // 399900 paise → ₹3,999.
      expect(find.textContaining('₹3,999'), findsWidgets);
      expect(find.text(l10n.premiumComingSoon), findsNothing);
    });

    testWidgets('Buy stays disabled: no payment provider in this build', (
      tester,
    ) async {
      await pump(tester, repo: onSale());
      final l10n = lookupAppLocalizations(const Locale('en'));
      final buy = tester.widget<NmGradientButton>(
        find.widgetWithText(
          NmGradientButton,
          '${l10n.membershipBuy} · '
          '${l10n.membershipMonths(3)} · ₹3,999',
        ),
      );
      expect(buy.onPressed, isNull);
      expect(find.text(l10n.membershipPurchaseUnavailableHere), findsOneWidget);
    });
  });

  testWidgets('a failed load offers a retry instead of plans', (tester) async {
    await pump(tester, repo: _FailingRepository());
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.membershipLoadError), findsOneWidget);
    expect(find.text(l10n.commonRetry), findsOneWidget);
    expect(find.byType(NmGradientButton), findsNothing);
  });
}

class _FailingRepository extends MockMembershipRepository {
  @override
  Future<MembershipCatalog> getPlans() async => throw Exception('offline');
}
