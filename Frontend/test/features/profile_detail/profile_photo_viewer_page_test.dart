import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_photo_viewer_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Swiping between photos is a touch gesture; with a mouse or keyboard the
/// second photo was unreachable. The viewer now has previous/next buttons
/// and the arrow keys.
void main() {
  Future<void> pumpViewer(WidgetTester tester, List<String> urls) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfilePhotoViewerPage(photoUrls: urls),
      ),
    );
    await tester.pumpAndSettle();
  }

  const three = [
    'https://example.invalid/1.jpg',
    'https://example.invalid/2.jpg',
    'https://example.invalid/3.jpg',
  ];

  testWidgets('next and previous buttons move between photos', (tester) async {
    await pumpViewer(tester, three);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byTooltip('Previous photo'), findsNothing);

    await tester.tap(find.byTooltip('Next photo'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Next photo'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byTooltip('Next photo'), findsNothing);

    await tester.tap(find.byTooltip('Previous photo'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('arrow keys move between photos', (tester) async {
    await pumpViewer(tester, three);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('a single photo shows no pager buttons', (tester) async {
    await pumpViewer(tester, const ['https://example.invalid/1.jpg']);
    expect(find.byTooltip('Next photo'), findsNothing);
    expect(find.byTooltip('Previous photo'), findsNothing);
  });
}
