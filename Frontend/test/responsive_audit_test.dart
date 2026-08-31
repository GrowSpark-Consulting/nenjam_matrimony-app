import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/pages/registration_landing_page.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/account_section.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/activity_stats_card.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/ai_match_coach_card.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/discover_opportunities_card.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/identity_hero_card.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/match_journey_card.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/partner_preference_card.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/photo_gallery_card.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/premium_membership_card.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/profile_performance_card.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/quick_actions_card.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/today_priority_card.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/verification_card.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Regression coverage for the responsive audit: every modified Profile
/// section and the sign-up landing screen must render without a
/// RenderFlex overflow (or any other layout exception) across small
/// phones through tablets, in both orientations, and under large system
/// font scaling.
///
/// Breakpoints span 320dp (smallest supported phone) through 1024dp
/// (tablet landscape).
const _widths = [320.0, 360.0, 390.0, 412.0, 480.0, 600.0, 800.0, 1024.0];

/// Every shipped locale. Tamil renders materially longer than English for
/// the same copy, so a card that fits in `en` can still overflow in `ta` —
/// running the whole matrix in both is the regression net for that.
const _locales = [Locale('en'), Locale('ta')];

/// Wraps [child] the way it's actually used: inside a padded, scrollable
/// column at a fixed width, with the app's real localization delegates so
/// `AppLocalizations.of(context)` resolves.
Widget _harness(Widget child, double width, Locale locale) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: child,
        ),
      ),
    ),
  );
}

Future<void> _expectNoOverflow(
  WidgetTester tester,
  Widget Function(AppLocalizations l10n) build,
  String label,
) async {
  for (final locale in _locales) {
    final l10n = lookupAppLocalizations(locale);
    for (final width in _widths) {
      for (final textScale in [1.0, 2.0]) {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: _harness(build(l10n), width, locale),
          ),
        );
        // Some cards contain infinitely-repeating animations (e.g. the
        // Match Journey pulsing dot), so advance a bounded number of frames
        // instead of pumpAndSettle (which would never terminate).
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.takeException(),
          isNull,
          reason: '$label overflowed/errored at width=$width '
              'textScale=$textScale locale=${locale.languageCode}',
        );
      }
    }
  }
}

void main() {
  testWidgets('NmMatchJourneyCard has no overflow across breakpoints', (
    tester,
  ) async {
    await _expectNoOverflow(
      tester,
      (l10n) => const NmMatchJourneyCard(currentStep: 3),
      'NmMatchJourneyCard',
    );
  });

  testWidgets('NmIdentityHeroCard has no overflow across breakpoints', (
    tester,
  ) async {
    await _expectNoOverflow(
      tester,
      (l10n) => const NmIdentityHeroCard(
        name: 'Arjun Sundar Krishnamoorthy Venkataraman',
        age: 28,
        nmId: 'NM984523',
        location: 'Chennai, Tamil Nadu, India',
        profileCompletion: 82,
        isPremium: true,
        isVerified: true,
        faith: 'Hindu, Iyer',
        height: "5'10\"",
        maritalStatus: 'Never Married',
        profession: 'Senior Product Designer',
      ),
      'NmIdentityHeroCard',
    );
  });

  testWidgets('NmTodayPrioritiesSection has no overflow across breakpoints', (
    tester,
  ) async {
    await _expectNoOverflow(
      tester,
      (l10n) => NmTodayPrioritiesSection(
        priorities: NmTodayPrioritiesSection.defaultPrioritiesFor(l10n),
      ),
      'NmTodayPrioritiesSection',
    );
  });

  testWidgets('NmAiMatchCoachCard has no overflow across breakpoints', (
    tester,
  ) async {
    await _expectNoOverflow(
      tester,
      (l10n) => const NmAiMatchCoachCard(),
      'NmAiMatchCoachCard',
    );
  });

  testWidgets('Activity + Performance cards have no overflow', (
    tester,
  ) async {
    await _expectNoOverflow(
      tester,
      (l10n) => const Column(
        children: [
          NmActivityStatsCard(),
          SizedBox(height: 16),
          NmProfilePerformanceCard(),
        ],
      ),
      'Activity + Performance',
    );
  });

  testWidgets('NmDiscoverOpportunitiesCard has no overflow', (tester) async {
    await _expectNoOverflow(
      tester,
      (l10n) => const NmDiscoverOpportunitiesCard(
        matches: [
          NmDiscoverMatch(
            name: 'Priya',
            age: 26,
            profession: 'Software Engineer',
            compatibilityPct: 94,
          ),
        ],
      ),
      'NmDiscoverOpportunitiesCard',
    );
  });

  testWidgets('NmVerificationCard has no overflow across breakpoints', (
    tester,
  ) async {
    await _expectNoOverflow(
      tester,
      (l10n) => NmVerificationCard(items: NmVerificationCard.defaultsFor(l10n)),
      'NmVerificationCard',
    );
  });

  testWidgets('NmPartnerPreferenceCard has no overflow across breakpoints', (
    tester,
  ) async {
    await _expectNoOverflow(
      tester,
      (l10n) => NmPartnerPreferenceCard(
        preferences: NmPartnerPreferenceCard.defaultsFor(l10n),
      ),
      'NmPartnerPreferenceCard',
    );
  });

  testWidgets('NmPhotoGalleryCard has no overflow across breakpoints', (
    tester,
  ) async {
    await _expectNoOverflow(
      tester,
      (l10n) => const NmPhotoGalleryCard(photoUrls: []),
      'NmPhotoGalleryCard',
    );
  });

  testWidgets('NmPremiumMembershipCard has no overflow across breakpoints', (
    tester,
  ) async {
    await _expectNoOverflow(
      tester,
      (l10n) => const NmPremiumMembershipCard(),
      'NmPremiumMembershipCard',
    );
  });

  testWidgets('NmQuickActionsCard has no overflow across breakpoints', (
    tester,
  ) async {
    await _expectNoOverflow(
      tester,
      (l10n) => const NmQuickActionsCard(
        actions: [
          NmQuickAction(icon: Icons.settings_outlined, label: 'Settings'),
          NmQuickAction(icon: Icons.lock_person_outlined, label: 'Privacy'),
          NmQuickAction(
            icon: Icons.contact_support_outlined,
            label: 'Help Center',
          ),
          NmQuickAction(
            icon: Icons.card_membership_outlined,
            label: 'Subscription',
          ),
        ],
      ),
      'NmQuickActionsCard',
    );
  });

  testWidgets('NmAccountSection has no overflow across breakpoints', (
    tester,
  ) async {
    await _expectNoOverflow(
      tester,
      (l10n) => const NmAccountSection(),
      'NmAccountSection',
    );
  });

  testWidgets('RegistrationLandingPage has no overflow across breakpoints', (
    tester,
  ) async {
    for (final size in [
      const Size(320, 640),
      const Size(360, 740),
      const Size(390, 844),
      const Size(412, 915),
      const Size(480, 900),
      const Size(600, 900),
      // Landscape orientations.
      const Size(740, 360),
      const Size(844, 390),
      const Size(1024, 768),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RegistrationLandingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'RegistrationLandingPage overflowed/errored at size=$size',
      );
    }
  });
}
