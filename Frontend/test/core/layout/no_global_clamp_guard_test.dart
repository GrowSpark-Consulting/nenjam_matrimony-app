import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guard for the architectural decision in
/// docs/superpowers/specs/2026-10-22-responsive-adaptive-layout-design.md §5.1.
///
/// A widget test cannot cover this: every harness builds its own MaterialApp,
/// so main.dart's `builder` never runs under test. A clamp re-added there
/// would be invisible to a pumped-widget assertion -- verified by mutation,
/// which is why this scans the source instead.
void main() {
  group('the global app-width clamp stays removed', () {
    test('MaterialApp.router declares no builder in main.dart', () {
      final source = File('lib/main.dart').readAsStringSync();
      final routerStart = source.indexOf('MaterialApp.router(');
      expect(
        routerStart,
        isNot(-1),
        reason: 'main.dart must still build a MaterialApp.router',
      );

      // Bound the search at the end of the MaterialApp.router argument list:
      // ScreenUtilInit has its own legitimate `builder:` ABOVE this point.
      final routerBody = source.substring(routerStart);
      final end = routerBody.indexOf('\n        );');
      final args = end == -1 ? routerBody : routerBody.substring(0, end);

      expect(
        args.contains('builder:'),
        isFalse,
        reason:
            'A builder on MaterialApp.router is how the removed NmAppFrame '
            'clamp was installed. It capped the app at ~1056px AND overrode '
            'the inner MediaQuery, making every wider layout impossible. If a '
            'builder is genuinely needed here, it must not constrain width or '
            'override MediaQuery.size.',
      );
    });

    test('NmAppFrame is not re-declared anywhere under lib/', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        if (text.contains('class NmAppFrame')) offenders.add(entity.path);
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'NmAppFrame was deleted deliberately; per-surface ContentWidth '
            'tokens replace it. Re-adding it would re-break desktop layouts.',
      );
    });

    test('no widget under lib/ overrides MediaQuery.size', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        // The clamp's second, subtler half: reporting a narrowed width to
        // descendants so their own breakpoint checks answer for the wrong box.
        if (text.contains('copyWith(size:')) offenders.add(entity.path);
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Overriding MediaQuery.size hides the real viewport from every '
            'descendant, which is what made multi-column layouts structurally '
            'impossible before. Surfaces must classify from LayoutBuilder '
            'constraints instead.',
      );
    });
  });
}
