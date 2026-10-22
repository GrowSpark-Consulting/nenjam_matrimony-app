import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/layout/window_class.dart';

import '../../support/responsive_harness.dart';

void main() {
  group('no global width clamp', () {
    for (final size in [
      const Size(1440, 900),
      const Size(1920, 1080),
      const Size(2560, 1440),
      const Size(3440, 1440),
    ]) {
      testWidgets('MediaQuery reports the true ${size.width.toInt()}px width', (
        tester,
      ) async {
        late double reported;
        late WindowClass windowClass;
        await pumpAtSize(
          tester,
          size,
          Builder(
            builder: (context) {
              reported = MediaQuery.sizeOf(context).width;
              windowClass = WindowClass.of(context);
              return const SizedBox.shrink();
            },
          ),
        );
        expect(
          reported,
          size.width,
          reason: 'a global clamp would report ~1056 here',
        );
        expect(windowClass, WindowClass.large);
      });
    }

    testWidgets('a full-width child can occupy the whole 1920px window', (
      tester,
    ) async {
      // pumpAtSize returns (and drains) the exceptions, so the overflow check
      // must consume that list rather than re-reading the empty queue.
      final errors = await pumpAtSize(
        tester,
        const Size(1920, 1080),
        Container(key: const ValueKey('full'), color: Colors.red),
      );
      expect(tester.getSize(find.byKey(const ValueKey('full'))).width, 1920);
      expectNoOverflowIn(errors);
    });
  });
}
