import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'responsive_harness.dart';

void main() {
  test('viewport matrices cover the brief', () {
    expect(kPhoneViewports, contains(const Size(320, 568)));
    expect(kPhoneViewports, contains(const Size(430, 932)));
    expect(kTabletViewports, contains(const Size(768, 1024)));
    expect(kDesktopViewports, contains(const Size(1920, 1080)));
    expect(kUltrawideViewports, contains(const Size(3440, 1440)));
    expect(
      kAllViewports.length,
      kPhoneViewports.length +
          kTabletViewports.length +
          kDesktopViewports.length +
          kUltrawideViewports.length,
    );
  });

  test('boundary widths are the four breakpoint pairs', () {
    expect(kBoundaryWidths, [599, 600, 899, 900, 1023, 1024, 1199, 1200]);
  });

  testWidgets('pumpAtSize reports the size it was given', (tester) async {
    late Size seen;
    final errors = await pumpAtSize(
      tester,
      const Size(1440, 900),
      Builder(
        builder: (context) {
          seen = MediaQuery.sizeOf(context);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(errors, isEmpty);
    expect(seen, const Size(1440, 900));
  });

  testWidgets('resizeTo changes the reported size in place', (tester) async {
    final seen = <Size>[];
    await pumpAtSize(
      tester,
      const Size(400, 800),
      Builder(
        builder: (context) {
          seen.add(MediaQuery.sizeOf(context));
          return const SizedBox.shrink();
        },
      ),
    );
    await resizeTo(tester, const Size(1200, 800));
    expect(seen.first.width, 400);
    expect(seen.last.width, 1200);
  });

  testWidgets('pumpAtSize returns no errors for a clean tree', (tester) async {
    final errors = await pumpAtSize(
      tester,
      const Size(400, 800),
      const Center(child: Text('fits')),
    );
    expect(errors, isEmpty);
    expectNoOverflow(tester);
  });

  testWidgets('pumpAtSize surfaces a real overflow', (tester) async {
    final errors = await pumpAtSize(
      tester,
      const Size(100, 100),
      Row(children: [Container(width: 500, height: 10)]),
    );
    expect(
      errors,
      isNotEmpty,
      reason: 'a 500px child in a 100px row overflows',
    );
    expect(shortError(errors.first), contains('overflow'));
  });

  testWidgets('a sweep reports overflow at every size, not just the first', (
    tester,
  ) async {
    // The regression this guards: without the per-size teardown, Flutter
    // reports each RenderFlex overflow only once per render object, so only
    // the first size in a sweep would report.
    final reported = <double>[];
    for (final size in const [Size(100, 100), Size(120, 100)]) {
      final errors = await pumpAtSize(
        tester,
        size,
        Row(children: [Container(width: 500, height: 10)]),
      );
      if (errors.isNotEmpty) reported.add(size.width);
    }
    expect(reported, [100, 120]);
  });
}
