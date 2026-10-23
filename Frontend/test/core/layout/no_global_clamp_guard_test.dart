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
    test('MaterialApp.router\'s only builder is the desktop rail frame', () {
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

      // A builder on MaterialApp.router is how the removed NmAppFrame clamp
      // was installed: it capped the app at ~1056px AND overrode the inner
      // MediaQuery, making every wider layout impossible. The one builder
      // allowed is NmDesktopFrame, which caps nothing — pages get the window
      // minus the rail, uncapped (responsive_desktop_shell_test) — and
      // overrides no MediaQuery (the size check below).
      final builders = 'builder:'.allMatches(args).length;
      expect(
        builders,
        lessThanOrEqualTo(1),
        reason: 'only the desktop frame may wrap the router',
      );
      if (builders == 1) {
        expect(
          args,
          contains('NmDesktopFrame(router: router, child: child!)'),
          reason:
              'A builder here must not constrain width or override '
              'MediaQuery.size; the desktop frame is the one that does '
              'neither.',
        );
      }
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
