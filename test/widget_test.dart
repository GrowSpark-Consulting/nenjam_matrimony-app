import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Setup mock shared preferences for local storage
    SharedPreferences.setMockInitialValues({});
    await storageService.init();

    // Set screen size for test environment
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;

    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: NenjamMatrimonyApp()));
    await tester.pumpAndSettle();

    // Verify app builds without crashing
    expect(find.byType(NenjamMatrimonyApp), findsOneWidget);

    // Reset view
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
