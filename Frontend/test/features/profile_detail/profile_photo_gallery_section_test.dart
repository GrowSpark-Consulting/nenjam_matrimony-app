import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_photo_gallery_section.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The mosaic renders 1 large + up to 4 small tiles from the member's
/// *additional* photos. These cover the counts the layout has to survive:
/// none, one, a partial row, a full mosaic, and more than fits.
List<String> _photos(int count) =>
    [for (var i = 0; i < count; i++) 'https://example.invalid/photo-$i.jpg'];

Future<void> _pump(
  WidgetTester tester,
  List<String> photos, {
  Size size = const Size(375, 812),
  Brightness brightness = Brightness.light,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ProfilePhotoGallerySection(photoUrls: photos),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Tiles are the only `ClipRRect`s the mosaic builds, one per photo shown.
int _tileCount(WidgetTester tester) => tester
    .widgetList(
      find.descendant(
        of: find.byType(ProfilePhotoGallerySection),
        matching: find.byType(ClipRRect),
      ),
    )
    .length;

void main() {
  testWidgets('no additional photos shows the empty state, not a fake tile',
      (tester) async {
    await _pump(tester, _photos(0));

    expect(find.text('No other photos shared yet'), findsOneWidget);
    expect(_tileCount(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one additional photo renders only the large tile',
      (tester) async {
    await _pump(tester, _photos(1));

    expect(_tileCount(tester), 1);
    expect(find.text('No other photos shared yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('three additional photos render large + a partial small row',
      (tester) async {
    await _pump(tester, _photos(3));

    expect(_tileCount(tester), 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('five additional photos render the full 1-large + 4-small mosaic',
      (tester) async {
    await _pump(tester, _photos(5));

    expect(_tileCount(tester), 5);
    // Exactly five means no "+N" badge — nothing was left out.
    expect(find.textContaining('+'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more than five photos cap the mosaic and surface the remainder',
      (tester) async {
    await _pump(tester, _photos(9));

    expect(_tileCount(tester), 5);
    expect(find.text('+4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out without overflow on a 320px-wide screen',
      (tester) async {
    await _pump(tester, _photos(9), size: const Size(320, 568));

    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out without overflow on a large phone', (tester) async {
    await _pump(tester, _photos(9), size: const Size(430, 932));

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in dark mode', (tester) async {
    await _pump(tester, _photos(5), brightness: Brightness.dark);

    expect(_tileCount(tester), 5);
    expect(tester.takeException(), isNull);
  });
}
