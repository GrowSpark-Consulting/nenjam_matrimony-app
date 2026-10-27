import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/constants/app_spacing.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/premium_membership_card.dart';

/// Regression: the crown→text and text→CTA gaps were `AppSpacing.base * 4`
/// (64px), which squeezed the copy into a narrow right-hand column. On a
/// 320px phone the card grew to ~500px tall — a mostly empty plum block
/// under the photo gallery on My Profile.
Future<void> _pump(
  WidgetTester tester,
  double width, {
  bool isPremiumMember = false,
  VoidCallback? onCtaTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: NmPremiumMembershipCard(
              isPremiumMember: isPremiumMember,
              onCtaTap: onCtaTap,
            ),
          ),
        ),
      ),
    ),
  );
}

Rect _crown(WidgetTester tester) => tester.getRect(
  find
      .ancestor(
        of: find.byIcon(Icons.workspace_premium_rounded).last,
        matching: find.byType(Container),
      )
      .first,
);

void main() {
  // Content widths of My Profile's cards at 320 / 390 / 568 / tablet+desktop
  // (page padding 20 each side; 680 is the centered max width).
  for (final width in const [280.0, 350.0, 528.0, 680.0]) {
    testWidgets('copy sits next to the crown, not 64px away (w=$width)', (
      tester,
    ) async {
      await _pump(tester, width);
      final titleLeft = tester.getTopLeft(find.text('Upgrade to Nenjam Elite'));
      expect(titleLeft.dx - _crown(tester).right, AppSpacing.base);
      expect(tester.takeException(), isNull);
    });
  }

  // In narrow mode the content Column used the default MainAxisSize.max, so
  // any parent with a bounded height (a fixed-height slot, a short window)
  // stretched the card to fill it with empty plum.
  testWidgets('narrow card hugs its content under a bounded height', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: 350, child: NmPremiumMembershipCard()),
            ),
          ),
        ),
      ),
    );
    final intrinsic = tester.getSize(find.byType(NmPremiumMembershipCard));

    await _pump(tester, 350); // Align inside a 600px-tall Scaffold body.
    expect(
      tester.getSize(find.byType(NmPremiumMembershipCard)).height,
      intrinsic.height,
    );
    expect(intrinsic.height, lessThan(600));
  });

  testWidgets('non-member: upgrade copy and a working CTA', (tester) async {
    var taps = 0;
    await _pump(tester, 350, onCtaTap: () => taps++);
    expect(find.text('Upgrade to Nenjam Elite'), findsOneWidget);
    await tester.tap(find.text('Explore Elite'));
    expect(taps, 1);
  });

  testWidgets('member: shows the member copy instead of the upsell', (
    tester,
  ) async {
    await _pump(tester, 350, isPremiumMember: true);
    expect(find.text('Nenjam Elite Member'), findsOneWidget);
    expect(find.text('Upgrade to Nenjam Elite'), findsNothing);
  });
}
