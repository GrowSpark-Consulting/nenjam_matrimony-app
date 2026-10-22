import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/layout/content_width.dart';

void main() {
  group('ContentWidth tokens', () {
    test('are ordered prose < form-wide < detail', () {
      expect(ContentWidth.form, lessThan(ContentWidth.prose));
      expect(ContentWidth.prose, lessThan(ContentWidth.formWide));
      expect(ContentWidth.formWide, lessThan(ContentWidth.detail));
    });
  });

  group('usableWidth', () {
    test('subtracts padding before clamping to the token', () {
      // 900px window minus a 96px rail is handled by the caller; here the
      // surface already sees 804 and pays its own 2x32 page padding.
      expect(
        NmContentWidth.usableWidth(
          availableWidth: 804,
          horizontalPadding: 64,
          maxWidth: ContentWidth.form,
        ),
        ContentWidth.form,
        reason: '740 usable exceeds the 560 form token, so it clamps',
      );
    });

    test('shrinks below the token on a narrow surface', () {
      expect(
        NmContentWidth.usableWidth(
          availableWidth: 320,
          horizontalPadding: 40,
          maxWidth: ContentWidth.form,
        ),
        280,
        reason: 'tokens are maximums, never fixed widths',
      );
    });

    test('never returns a negative width', () {
      expect(
        NmContentWidth.usableWidth(
          availableWidth: 20,
          horizontalPadding: 64,
          maxWidth: ContentWidth.prose,
        ),
        0,
      );
    });

    test('clamps an unbounded surface to the token', () {
      expect(
        NmContentWidth.usableWidth(
          availableWidth: double.infinity,
          horizontalPadding: 0,
          maxWidth: ContentWidth.detail,
        ),
        ContentWidth.detail,
      );
    });
  });

  group('NmContentWidth widget', () {
    Future<Size> pumpAt(WidgetTester tester, Size surface) async {
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: NmContentWidth(
            maxWidth: ContentWidth.prose,
            child: Container(key: const ValueKey('body'), color: Colors.red),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(const ValueKey('body')));
    }

    testWidgets('constrains on an ultrawide surface', (tester) async {
      expect(
        (await pumpAt(tester, const Size(3440, 1440))).width,
        ContentWidth.prose,
      );
    });

    testWidgets('fills a narrow surface instead of stretching', (tester) async {
      expect((await pumpAt(tester, const Size(360, 640))).width, 360);
    });

    testWidgets('is centered when constrained', (tester) async {
      await pumpAt(tester, const Size(1920, 1080));
      final left = tester.getTopLeft(find.byKey(const ValueKey('body'))).dx;
      expect(left, closeTo((1920 - ContentWidth.prose) / 2, 0.5));
    });
  });
}
