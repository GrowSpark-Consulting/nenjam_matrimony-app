import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/help/presentation/pages/partner_program_help_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The Partner Program Help & Support copy, as supplied — including Agent
/// Terms and the still-unconfirmed support contact.
void main() {
  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PartnerProgramHelpPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls until [text] is built, then checks it.
  Future<void> expectText(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(text), findsOneWidget);
  }

  testWidgets('shows the supplied copy in order', (tester) async {
    await pump(tester, const Size(1080, 2400));
    for (final text in [
      'Welcome to the Nenjam Partner Program.',
      'Getting started',
      'Sign in with your mobile number and the one-time code (OTP) we send '
          'you. Then fill in your application. Our team reviews it and either '
          'approves it or tells you why it was not approved. Once you are '
          'approved, you get your personal referral code.',
      'Referring members',
      'Tracking referrals and earnings',
      'Bank details',
      'Need help?',
      'Never share your OTP or any login details with anyone.',
    ]) {
      await expectText(tester, text);
    }
  });

  testWidgets('keeps the Agent Terms section', (tester) async {
    await pump(tester, const Size(1080, 2400));
    for (final text in [
      'Agent terms (main points)',
      'Never charge families any fee for joining.',
      'Never make false promises about matches.',
      'Never share information about the people you refer or your clients.',
      'Never create a profile for someone without their agreement.',
      'Breaking these rules can lead to your account being paused.',
    ]) {
      await expectText(tester, text);
    }
  });

  testWidgets('the support contact is an explicit placeholder', (tester) async {
    await pump(tester, const Size(1080, 2400));
    await expectText(
      tester,
      'Contact the Nenjam team at <support contact to be confirmed>.',
    );
    expect(find.textContaining('@'), findsNothing);
  });

  for (final size in const [Size(320, 568), Size(568, 320), Size(480, 900)]) {
    testWidgets('scrolls without overflow at ${size.width}x${size.height}', (
      tester,
    ) async {
      await pump(tester, size);
      await expectText(
        tester,
        'Never share your OTP or any login details with anyone.',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('larger text still scrolls to the end', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PartnerProgramHelpPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectText(
      tester,
      'Never share your OTP or any login details with anyone.',
    );
    expect(tester.takeException(), isNull);
  });
}
