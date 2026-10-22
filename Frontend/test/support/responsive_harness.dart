import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Phone viewports from the responsive brief.
const List<Size> kPhoneViewports = [
  Size(320, 568),
  Size(360, 640),
  Size(375, 667),
  Size(390, 844),
  Size(430, 932),
];

/// Tablet and foldable-sized viewports.
const List<Size> kTabletViewports = [
  Size(600, 800),
  Size(768, 1024),
  Size(820, 1180),
  Size(1024, 768),
];

/// Desktop and laptop viewports.
const List<Size> kDesktopViewports = [
  Size(1280, 720),
  Size(1366, 768),
  Size(1440, 900),
  Size(1600, 900),
  Size(1920, 1080),
];

/// Large and ultrawide displays.
const List<Size> kUltrawideViewports = [Size(2560, 1440), Size(3440, 1440)];

/// Every viewport in the brief, for sweeps that should hold everywhere.
const List<Size> kAllViewports = [
  ...kPhoneViewports,
  ...kTabletViewports,
  ...kDesktopViewports,
  ...kUltrawideViewports,
];

/// The four breakpoint boundary pairs: a layout must not change *within* a
/// pair's class and must change *across* it.
const List<double> kBoundaryWidths = [
  599,
  600,
  899,
  900,
  1023,
  1024,
  1199,
  1200,
];

/// A desktop-width window that is short vertically — the case where a rail
/// plus a tall page most easily overflows.
const Size kShortDesktop = Size(900, 600);

/// Collects every pending framework exception.
///
/// [WidgetTester.takeException] returns one at a time, so a single call can
/// hide later overflows behind the first.
List<Object> drainExceptions(WidgetTester tester) {
  final found = <Object>[];
  while (true) {
    final Object? e = tester.takeException() as Object?;
    if (e == null) return found;
    found.add(e);
  }
}

/// First few lines of an exception, so a failure message names the overflow
/// instead of dumping a stack. A RenderFlex overflow's first line alone is
/// just "A RenderFlex overflowed by N pixels" with no widget identity.
String shortError(Object e) => e
    .toString()
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .take(6)
    .join(' | ');

/// Pumps [widget] at [size] and returns any exceptions it produced.
///
/// Tears the previous tree down first: Flutter reports a given RenderFlex
/// overflow only ONCE per render object, and `pumpWidget` reuses render
/// objects across calls — without the teardown, only the first size in a
/// sweep reports and every later width looks clean.
///
/// Uses a bounded pump walk rather than `pumpAndSettle`, because several
/// screens hold repeating animations (shimmer, pulsing dots) that never
/// settle.
///
/// Returns rather than asserts, so a caller can sweep many sizes and report
/// all failures at once. For a single size, follow with [expectNoOverflow].
Future<List<Object>> pumpAtSize(
  WidgetTester tester,
  Size size,
  Widget widget, {
  double keyboard = 0,
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  // Notch + home-indicator sized safe area, so SafeArea handling is genuinely
  // exercised rather than assumed.
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  await tester.binding.setSurfaceSize(size);

  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: widget,
      ),
    ),
  );

  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return drainExceptions(tester);
}

/// Resizes an already-pumped tree, as a browser window resize would.
///
/// Deliberately does **not** tear the tree down — reusing the render objects
/// is exactly what a resize test is asserting survives. That also means a
/// repeated overflow may not re-report here; use [pumpAtSize] when the goal is
/// to detect overflow at each size, and this when the goal is to prove a
/// resize leaves a valid layout.
Future<List<Object>> resizeTo(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return drainExceptions(tester);
}

/// Fails if the framework reported a layout exception. Never "fix" a failure
/// here by deleting the call — fix the layout.
void expectNoOverflow(WidgetTester tester) {
  final found = drainExceptions(tester);
  if (found.isEmpty) return;
  fail(
    'Unexpected layout exception(s), likely a RenderFlex overflow:\n'
    '${found.map(shortError).join('\n')}',
  );
}
