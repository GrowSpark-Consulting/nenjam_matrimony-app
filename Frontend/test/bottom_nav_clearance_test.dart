import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/buttons/gradient_button.dart';
import 'package:nenjam_matrimony/core/widgets/cards/profile_hero_content.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/compatibility_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/matches/presentation/pages/matches_page.dart';
import 'package:nenjam_matrimony/features/matches/presentation/providers/reel_feed_provider.dart';
import 'package:nenjam_matrimony/features/premium/presentation/pages/premium_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The floating nav pill is drawn OVER the tab pages: `AppBottomNavShell`'s
/// Scaffold sets `extendBody: true`, and Flutter answers by publishing the
/// pill's measured height as the page's `MediaQuery.padding.bottom`.
///
/// These tests pin the two consequences a page has to honour:
///
///  1. its last content still comes to rest ABOVE the pill, and
///  2. its background still runs the full height of the screen, so the page
///     shows through around the pill instead of a widget ending early and
///     leaving an opaque strip behind it.
///
/// They model the shell the way the shell presents itself to a branch page: a
/// bottom padding of [_navHeight] over a full-height body.
const double _navHeight = 96;

const _sizes = <Size>[
  Size(320, 568), // smallest supported phone
  Size(375, 812),
  Size(430, 932),
];

/// A profile with every metadata chip filled — the "many chips" case, which is
/// the one that reaches lowest down the card.
const _profile = DiscoveryProfileEntity(
  id: 'p1',
  matrimonyId: 'NEN1',
  name: 'Meera',
  age: 27,
  location: 'Coimbatore',
  profession: 'Software Engineer',
  education: 'B.E / B.Tech',
  photoUrls: [],
  religion: 'Hindu',
  community: 'Iyer',
  height: '5ft 4in',
  motherTongue: 'Tamil',
  maritalStatus: 'Never Married',
  diet: 'Vegetarian',
  gender: 'Female',
  compatibility: CompatibilityEntity(aiMatchPercent: 92),
);

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  Size size, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  await tester.binding.setSurfaceSize(size);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          // What the shell hands a branch page: a notch on top, and a bottom
          // padding that already accounts for the pill plus the system
          // navigation area beneath it.
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 44, bottom: _navHeight),
          ),
          child: page,
        ),
      ),
    ),
  );

  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('Matches reel', () {
    for (final size in _sizes) {
      testWidgets(
        'profile chips clear the floating nav @ ${size.width.toInt()}',
        (tester) async {
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await _pump(
            tester,
            const MatchesPage(),
            size,
            overrides: [reelFeedProvider.overrideWith(_StubReelFeed.new)],
          );

          final info = find.byType(NmProfileHeroInfo);
          expect(
            info,
            findsOneWidget,
            reason: 'the stubbed reel feed should render one card',
          );

          // The education chip is the one reported as cut off by the pill.
          expect(find.text('B.E / B.Tech'), findsOneWidget);

          final navTop = size.height - _navHeight;
          expect(
            tester.getRect(info).bottom,
            lessThanOrEqualTo(navTop),
            reason: 'the metadata chips (location/height/education) must sit '
                'above the floating pill, not underneath it',
          );
        },
      );
    }
  });

  group('Premium', () {
    for (final size in _sizes) {
      testWidgets('CTA clears the floating nav @ ${size.width.toInt()}', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await _pump(tester, const PremiumPage(), size);

        // The page must paint all the way down: if the scroll viewport stops
        // at the top of the pill (a SafeArea eating the inset), the Scaffold's
        // own opaque background fills the gap and shows as a full-width strip
        // behind the floating pill.
        final viewport = tester.getRect(find.byType(Scrollable).first);
        expect(
          viewport.bottom,
          size.height,
          reason: 'the scroll viewport must run to the bottom of the screen so '
              'the page shows through around the pill',
        );

        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -4000),
        );
        await tester.pumpAndSettle();

        final cta = find.byType(NmGradientButton);
        expect(cta, findsWidgets, reason: 'Premium CTA should be reachable');

        final navTop = size.height - _navHeight;
        expect(
          tester.getRect(cta.last).bottom,
          lessThanOrEqualTo(navTop),
          reason: 'scrolled fully to the bottom, the Proceed CTA must rest '
              'above the floating pill',
        );
      });
    }
  });
}

/// Serves one fully-populated profile without touching the repository layer.
class _StubReelFeed extends ReelFeedNotifier {
  @override
  Future<ReelFeedState> build() async =>
      const ReelFeedState(profiles: [_profile], hasMore: false);
}
