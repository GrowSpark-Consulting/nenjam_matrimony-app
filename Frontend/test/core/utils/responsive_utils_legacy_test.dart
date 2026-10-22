import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/utils/responsive_utils.dart';

import '../../support/responsive_harness.dart';

/// Reads the legacy helpers at a given width. These assertions encode the
/// behavior that existing call sites already depend on; they must keep passing
/// until every caller has migrated off the facade.
Future<T> _at<T>(
  WidgetTester tester,
  double width,
  T Function(BuildContext) read,
) async {
  late T value;
  // pumpAtSize already supplies ProviderScope + MaterialApp + localizations,
  // so pass the bare widget — wrapping another MaterialApp here would nest two.
  await pumpAtSize(
    tester,
    Size(width, 800),
    Builder(
      builder: (context) {
        value = read(context);
        return const SizedBox.shrink();
      },
    ),
  );
  return value;
}

void main() {
  testWidgets('device-type thresholds are unchanged (600/1024)', (
    tester,
  ) async {
    expect(
      await _at(tester, 599, ResponsiveUtils.getDeviceType),
      DeviceType.phone,
    );
    expect(
      await _at(tester, 600, ResponsiveUtils.getDeviceType),
      DeviceType.tablet,
    );
    expect(
      await _at(tester, 1023, ResponsiveUtils.getDeviceType),
      DeviceType.tablet,
    );
    expect(
      await _at(tester, 1024, ResponsiveUtils.getDeviceType),
      DeviceType.desktop,
    );
  });

  testWidgets('grid columns are unchanged', (tester) async {
    expect(await _at(tester, 375, ResponsiveUtils.gridColumns), 2);
    expect(await _at(tester, 700, ResponsiveUtils.gridColumns), 3);
    expect(await _at(tester, 1440, ResponsiveUtils.gridColumns), 4);
  });

  testWidgets('maxContentWidth is unchanged', (tester) async {
    expect(
      await _at(tester, 375, ResponsiveUtils.maxContentWidth),
      double.infinity,
    );
    expect(await _at(tester, 700, ResponsiveUtils.maxContentWidth), 720.0);
    expect(await _at(tester, 1440, ResponsiveUtils.maxContentWidth), 960.0);
  });

  testWidgets('adaptive falls back down the chain', (tester) async {
    expect(
      await _at(
        tester,
        1440,
        (c) => ResponsiveUtils.adaptive(c, phone: 1, tablet: 2),
      ),
      2,
    );
  });
}
