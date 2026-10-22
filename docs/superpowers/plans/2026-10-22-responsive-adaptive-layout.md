# Responsive & Adaptive Layout System Implementation Plan

  > **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

  **Goal:** Replace the global ~1056px app-width clamp with a constraint-driven adaptive layout system, then build real desktop layouts for discovery, chat, and profile detail.

  **Architecture:** A `WindowClass` enum classifies available width into compact/medium/expanded/large. Shell-level decisions read `MediaQuery` via `WindowClass.of(context)`; every surface-level decision reads local `BoxConstraints` via `WindowClass.fromWidth(constraints.maxWidth)` under a `LayoutBuilder`. Ultrawide protection moves from one global clamp to per-surface `ContentWidth` tokens named by content role. `ResponsiveUtils` survives as a deprecated facade so the 55 pages migrate incrementally rather than in one commit.

  **Tech Stack:** Flutter (Dart ^3.9.2), Riverpod (hand-written providers, no codegen), go_router ^14.8.1, flutter_test (hand-written fakes, no mockito/mocktail).

  **Spec:** `docs/superpowers/specs/2026-10-22-responsive-adaptive-layout-design.md`

## Global Constraints

  - **No codegen.** Do not introduce `riverpod_generator`/`@riverpod`, `freezed`, or `json_serializable`. Hand-written providers and models only.
  - **No new dependencies.** Everything here uses the existing Flutter SDK and current `pubspec.yaml` deps.
  - **Light mode only.** `themeMode: ThemeMode.light` is enforced by `test/light_mode_only_test.dart`. Do not add dark `ThemeData`.
  - **Tokens, not literals.** Use `AppSpacing` (4px grid: `xs2=2, xs=4, sm=8, md=12, base=16, lg=20, xl=24, xl2=32, xl3=40, xl4=48, xl5=56, xl6=64, xl7=80, xl8=96`), `AppRadius`, `AppColors`. No literal `EdgeInsets`/`BorderRadius` values.
  - **Naming.** `snake_case.dart` files, `UpperCamelCase` classes, `lowerCamelCase` members. `Nm` prefix only where the surrounding widget library already uses it (`NmAppFrame`, `NmContentConstraint`).
  - **Analysis must stay clean.** `flutter analyze --no-fatal-infos` — errors and warnings are fatal. `prefer_single_quotes`, `require_trailing_commas`, `prefer_const_constructors`, `avoid_print` are enforced.
  - **No suppressing overflow.** Never fix an overflow by hiding content, wrapping in `ClipRect`, or removing an assertion. Fix the layout.
  - **Mobile regression suites stay untouched:** `test/responsive_audit_test.dart`, `test/responsive_pages_audit_test.dart`, `test/light_mode_only_test.dart`, `test/bottom_nav_clearance_test.dart`. If one of these fails, the production change is wrong — fix the change, not the test.
  - **Git:** branch `feat/responsive-adaptive-layout`. Commit per task. **Never push, merge, deploy, or change env vars.**
  - **Commit message trailer** on every commit:
    `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

### Correction to the spec (authoritative)

  The spec's §6.2 table used illustrative routes `/inbox` and `/inbox/:id`. The **real** routes, verified in `lib/core/router/route_names.dart` and `lib/core/router/app_router.dart`, are:

  - Inbox list: `RouteNames.messages` = `/messages`, the 3rd `StatefulShellBranch`, renders `InboxPage`.
  - Chat detail: `RouteNames.chatDetailPattern` = `/chat-detail/:conversationId`, currently a **root-level** `GoRoute` **outside** the `StatefulShellRoute` — it deliberately covers the whole shell today.

  Use these real paths everywhere. Task 7 covers moving the chat route inside the Inbox branch, which is what makes master-detail possible at all.

  ---

### Task 1: Window-class model

  **Files:**
  - Create: `Frontend/lib/core/layout/window_class.dart`
  - Test: `Frontend/test/core/layout/window_class_test.dart`

  **Interfaces:**
  - Consumes: nothing (first task).
  - Produces:
    - `enum WindowClass { compact, medium, expanded, large }`
    - `WindowClass.fromWidth(double width)` → `WindowClass` (static)
    - `WindowClass.of(BuildContext context)` → `WindowClass` (static, reads `MediaQuery.sizeOf(context).width`)
    - Instance getters: `isCompact`, `isMedium`, `isExpanded`, `isLarge`, `isAtLeastExpanded`, `isAtLeastMedium`
    - `T resolve<T>({required T compact, T? medium, T? expanded, T? large})` — instance method, falls back down the chain
    - Const boundary fields on a `WindowClassBreakpoints` class: `mediumMin = 600`, `expandedMin = 900`, `largeMin = 1200`

  - [ ] **Step 1: Write the failing test**

  Create `Frontend/test/core/layout/window_class_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nenjam_matrimony/core/layout/window_class.dart';

  void main() {
    group('WindowClass.fromWidth half-open intervals', () {
      test('classifies every boundary pair', () {
        expect(WindowClass.fromWidth(0), WindowClass.compact);
        expect(WindowClass.fromWidth(320), WindowClass.compact);
        expect(WindowClass.fromWidth(599), WindowClass.compact);
        expect(WindowClass.fromWidth(600), WindowClass.medium);
        expect(WindowClass.fromWidth(899), WindowClass.medium);
        expect(WindowClass.fromWidth(900), WindowClass.expanded);
        expect(WindowClass.fromWidth(1199), WindowClass.expanded);
        expect(WindowClass.fromWidth(1200), WindowClass.large);
        expect(WindowClass.fromWidth(3440), WindowClass.large);
      });

      test('599.9 is still compact and 600.0 is medium', () {
        expect(WindowClass.fromWidth(599.9), WindowClass.compact);
        expect(WindowClass.fromWidth(600.0), WindowClass.medium);
      });

      test('tolerates infinite and negative widths without throwing', () {
        expect(WindowClass.fromWidth(double.infinity), WindowClass.large);
        expect(WindowClass.fromWidth(-10), WindowClass.compact);
      });
    });

    group('resolve', () {
      test('falls back down the chain when a tier is omitted', () {
        expect(
          WindowClass.large.resolve(compact: 1, medium: 2),
          2,
          reason: 'large falls back to expanded, then medium',
        );
        expect(WindowClass.expanded.resolve(compact: 1), 1);
        expect(WindowClass.large.resolve(compact: 1, large: 9), 9);
      });
    });

    group('threshold getters', () {
      test('isAtLeastExpanded is true from 900 up', () {
        expect(WindowClass.medium.isAtLeastExpanded, isFalse);
        expect(WindowClass.expanded.isAtLeastExpanded, isTrue);
        expect(WindowClass.large.isAtLeastExpanded, isTrue);
      });
    });

    group('WindowClass.of', () {
      testWidgets('reads the real MediaQuery width', (tester) async {
        late WindowClass seen;
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: Size(1440, 900)),
            child: Builder(
              builder: (context) {
                seen = WindowClass.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(seen, WindowClass.large);
      });

      testWidgets('a narrow pane on a large window classifies as compact '
          'when read from local constraints', (tester) async {
        late WindowClass paneClass;
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: Size(1920, 1080)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              // Align loosens the incoming constraint. Without it the SizedBox
              // is the direct child of pumpWidget's root, receives a TIGHT
              // constraint equal to the test surface, and cannot narrow itself
              // -- the LayoutBuilder would then see the surface width (800),
              // classify as medium, and prove nothing about a narrow pane.
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 400,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      paneClass = WindowClass.fromWidth(constraints.maxWidth);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          paneClass,
          WindowClass.compact,
          reason: 'local constraints, not the 1920px window, decide a pane',
        );
      });
    });
  }
  ```

  - [ ] **Step 2: Run test to verify it fails**

  Run: `cd Frontend && flutter test test/core/layout/window_class_test.dart`
  Expected: FAIL — `Error: Couldn't resolve the package 'nenjam_matrimony'` or `window_class.dart` not found.

  (If the package name differs, read `name:` from `Frontend/pubspec.yaml` and use that import prefix consistently in every test in this plan.)

  - [ ] **Step 3: Write minimal implementation**

  Create `Frontend/lib/core/layout/window_class.dart`:

  ```dart
  import 'package:flutter/widgets.dart';

  /// Width thresholds for [WindowClass], as half-open intervals.
  abstract final class WindowClassBreakpoints {
    /// Smallest width that counts as [WindowClass.medium].
    static const double mediumMin = 600;

    /// Smallest width that counts as [WindowClass.expanded].
    static const double expandedMin = 900;

    /// Smallest width that counts as [WindowClass.large].
    static const double largeMin = 1200;
  }

  /// How much horizontal room a piece of UI has to work with.
  ///
  /// Deliberately describes *available space*, not a device: the same phone in
  /// landscape, a tablet, a resized browser window and a 400px detail pane on a
  /// 1920px monitor are classified by what they actually offer. That is why
  /// surfaces must classify from their own [BoxConstraints] via [fromWidth]
  /// rather than from the window via [of] — see the class docs on [of].
  enum WindowClass {
    /// Below 600: phones in portrait, narrow panes, small embedded web views.
    compact,

    /// 600–899: large phones in landscape, small tablets, half-screen windows.
    medium,

    /// 900–1199: tablets in landscape, small laptop windows.
    expanded,

    /// 1200 and above: desktop browsers and larger.
    large;

    /// Classifies a raw width. Intervals are half-open, so 599 is [compact] and
    /// 600 is [medium].
    ///
    /// Tolerates `double.infinity` (an unbounded constraint, treated as [large])
    /// and negative widths (treated as [compact]) so a caller inside an
    /// unbounded or degenerate layout never throws.
    static WindowClass fromWidth(double width) {
      if (width >= WindowClassBreakpoints.largeMin) return large;
      if (width >= WindowClassBreakpoints.expandedMin) return expanded;
      if (width >= WindowClassBreakpoints.mediumMin) return medium;
      return compact;
    }

    /// Classifies the whole window.
    ///
    /// **Use this only for shell-level decisions** — which navigation affordance
    /// to show. For anything laid out *inside* the shell, wrap the surface in a
    /// `LayoutBuilder` and use [fromWidth] with the local constraints instead:
    /// a surface in a narrow pane on a wide monitor must see its pane, not the
    /// monitor.
    static WindowClass of(BuildContext context) =>
        fromWidth(MediaQuery.sizeOf(context).width);

    bool get isCompact => this == compact;
    bool get isMedium => this == medium;
    bool get isExpanded => this == expanded;
    bool get isLarge => this == large;

    /// True for [medium] and wider — i.e. not a narrow phone-width surface.
    bool get isAtLeastMedium => index >= medium.index;

    /// True for [expanded] and wider — the threshold at which the navigation
    /// rail replaces the bottom pill and two-pane layouts become available.
    bool get isAtLeastExpanded => index >= expanded.index;

    /// Picks the value for this class, falling back down the chain when a tier
    /// is omitted: [large] tries large → expanded → medium → compact.
    T resolve<T>({required T compact, T? medium, T? expanded, T? large}) {
      switch (this) {
        case WindowClass.compact:
          return compact;
        case WindowClass.medium:
          return medium ?? compact;
        case WindowClass.expanded:
          return expanded ?? medium ?? compact;
        case WindowClass.large:
          return large ?? expanded ?? medium ?? compact;
      }
    }
  }
  ```

  - [ ] **Step 4: Run test to verify it passes**

  Run: `cd Frontend && flutter test test/core/layout/window_class_test.dart`
  Expected: PASS, all tests.

  Then: `cd Frontend && flutter analyze --no-fatal-infos lib/core/layout/ test/core/layout/`
  Expected: no errors or warnings.

  - [ ] **Step 5: Commit**

  ```bash
  cd /c/Users/PC/nenjam_matrimony_app
  git add Frontend/lib/core/layout/window_class.dart Frontend/test/core/layout/window_class_test.dart
  git commit -m "$(cat <<'MSG'
  feat(layout): add the WindowClass model

  Classifies available width into compact/medium/expanded/large using
  half-open intervals. fromWidth() takes local BoxConstraints so a surface
  in a narrow pane on a wide monitor classifies by its pane; of() reads
  MediaQuery and is reserved for shell-level navigation decisions.

  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  MSG
  )"
  ```

  ---

### Task 2: Content-width tokens

  **Files:**
  - Create: `Frontend/lib/core/layout/content_width.dart`
  - Test: `Frontend/test/core/layout/content_width_test.dart`

  **Interfaces:**
  - Consumes: `WindowClass`, `WindowClassBreakpoints` from Task 1.
  - Produces:
    - `abstract final class ContentWidth` with `static const double prose = 680`, `form = 560`, `formWide = 900`, `detail = 1200`
    - `class NmContentWidth extends StatelessWidget` — `{Key? key, required double maxWidth, required Widget child, EdgeInsetsGeometry? padding}`; centers and constrains, never stretches.
    - `static double NmContentWidth.usableWidth({required double availableWidth, required double horizontalPadding, required double maxWidth})` → `double` — the §4.1 derivation, exposed for grid math in Task 6.

  - [ ] **Step 1: Write the failing test**

  Create `Frontend/test/core/layout/content_width_test.dart`:

  ```dart
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
        expect((await pumpAt(tester, const Size(3440, 1440))).width,
            ContentWidth.prose);
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
  ```

  - [ ] **Step 2: Run test to verify it fails**

  Run: `cd Frontend && flutter test test/core/layout/content_width_test.dart`
  Expected: FAIL — `content_width.dart` does not exist.

  - [ ] **Step 3: Write minimal implementation**

  Create `Frontend/lib/core/layout/content_width.dart`:

  ```dart
  import 'package:flutter/widgets.dart';

  /// Maximum content widths, named by the **role of the content** rather than by
  /// device, so each surface has one obvious choice.
  ///
  /// Every value is a *maximum*. A surface narrower than its token fills the
  /// space it has; it is never padded out to the token.
  abstract final class ContentWidth {
    /// Text-heavy reading surfaces: settings, help, safety, privacy. Sized for a
    /// comfortable measure rather than for any particular screen.
    static const double prose = 680;

    /// A single-column form. Fields stay close to their labels instead of
    /// stretching a text input across a monitor.
    static const double form = 560;

    /// A form laid out in two columns on wide surfaces.
    static const double formWide = 900;

    /// A two-column detail surface (profile detail).
    static const double detail = 1200;
  }

  /// Centers [child] in a column no wider than [maxWidth].
  ///
  /// Use one of the [ContentWidth] tokens for [maxWidth]. This replaces the old
  /// global `NmAppFrame` clamp: instead of bounding the whole app (which also
  /// hid the real window width from every descendant), each surface bounds
  /// itself, so grids and two-pane layouts can still use the full width.
  class NmContentWidth extends StatelessWidget {
    final double maxWidth;
    final Widget child;
    final EdgeInsetsGeometry? padding;

    const NmContentWidth({
      super.key,
      required this.maxWidth,
      required this.child,
      this.padding,
    });

    /// The §4.1 derivation: how much width content actually gets.
    ///
    /// [availableWidth] must already be post-navigation — in practice it is a
    /// `LayoutBuilder`'s `constraints.maxWidth` inside the shell's content area,
    /// which is a sibling of the rail and so never includes it. Pass the
    /// surface's own horizontal padding (both sides) as [horizontalPadding].
    ///
    /// Returns the smaller of the padded available width and [maxWidth], floored
    /// at 0 so a degenerate surface cannot produce a negative constraint.
    static double usableWidth({
      required double availableWidth,
      required double horizontalPadding,
      required double maxWidth,
    }) {
      if (availableWidth == double.infinity) return maxWidth;
      final padded = availableWidth - horizontalPadding;
      if (padded <= 0) return 0;
      return padded < maxWidth ? padded : maxWidth;
    }

    @override
    Widget build(BuildContext context) {
      // Padding sits OUTSIDE the constraint so [maxWidth] always means the
      // width of the CONTENT, matching [usableWidth]. With the Padding inside
      // the ConstrainedBox the two disagreed by the padding amount on any
      // surface wider than the token (1920px available, 32px/side, prose 680:
      // the widget rendered 616 while usableWidth predicted 680), which would
      // make grid column maths over-estimate the space available.
      final constrained = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      );
      return Center(
        child: padding == null
            ? constrained
            : Padding(padding: padding!, child: constrained),
      );
    }
  }
  ```

  - [ ] **Step 4: Run test to verify it passes**

  Run: `cd Frontend && flutter test test/core/layout/content_width_test.dart`
  Expected: PASS.

  Run: `cd Frontend && flutter analyze --no-fatal-infos lib/core/layout/ test/core/layout/`
  Expected: clean.

  - [ ] **Step 5: Commit**

  ```bash
  cd /c/Users/PC/nenjam_matrimony_app
  git add Frontend/lib/core/layout/content_width.dart Frontend/test/core/layout/content_width_test.dart
  git commit -m "$(cat <<'MSG'
  feat(layout): add per-surface content-width tokens

  Tokens named by content role (prose/form/formWide/detail) plus
  NmContentWidth, which constrains and centers without stretching narrow
  surfaces. usableWidth() encodes the derivation rule: subtract padding
  from the post-navigation available width, then clamp to the token --
  never compute content width from the full window.

  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  MSG
  )"
  ```

  ---

### Task 3: Responsive test harness

  **Files:**
  - Create: `Frontend/test/support/responsive_harness.dart`
  - Test: `Frontend/test/support/responsive_harness_self_test.dart`

  **Read this first — the existing harness already solved two traps.**

  `test/responsive_pages_audit_test.dart` contains a mature private harness. Read it before writing anything:

  ```bash
  cd Frontend && sed -n '140,240p' test/responsive_pages_audit_test.dart
  ```

  Two lessons it encodes, both of which a naive harness gets wrong:

  1. **It tears the tree down between sizes** (`pumpWidget(const SizedBox.shrink())` then `pump()`). Flutter reports a given `RenderFlex` overflow **only once per render object**, and `pumpWidget` reuses render objects across calls — without the teardown, only the *first* size in a sweep ever reports and every later width looks clean. A sweep without this silently under-reports.
  2. **It uses a bounded pump walk, not `pumpAndSettle`** (`for (var i = 0; i < 12; i++) await tester.pump(100ms)`). Several screens hold repeating animations (shimmer, pulsing dots), so `pumpAndSettle` never returns.

  It also sets `tester.view.padding = FakeViewPadding(top: 44, bottom: 34)` so `SafeArea` is genuinely exercised, and drives `viewInsets.bottom` for the keyboard case.

  **So: do not write a competing harness.** Build `test/support/responsive_harness.dart` by extracting that file's proven approach into shared helpers, then have the new tests use them. Leave `responsive_pages_audit_test.dart` itself **unmodified** (it is a protected mobile regression suite) — copy its technique, don't refactor it.

  **Interfaces:**
  - Consumes: nothing from earlier tasks.
  - Produces:
    - `Future<List<Object>> pumpAtSize(WidgetTester tester, Size size, Widget widget, {double keyboard = 0, List<Override> overrides = const []})` — tears down the previous tree, sets view size/padding/insets, pumps inside `ProviderScope` + `MaterialApp` with localizations, runs the bounded pump walk, and **returns the drained exceptions** rather than asserting, so callers can sweep.
    - `Future<List<Object>> resizeTo(WidgetTester tester, Size size)` — resizes an already-pumped tree (for continuous-resize assertions, where tree reuse is the point being tested) and returns drained exceptions.
    - `void expectNoOverflow(WidgetTester tester)` — convenience for single-size tests; fails on a pending layout exception.
    - `List<Object> drainExceptions(WidgetTester tester)` — repeatedly calls `takeException()` until null, collecting all of them.
    - `String shortError(Object e)` — first 6 trimmed lines joined, so a failure message names the overflow instead of dumping a stack.

  Note the deliberate split: `pumpAtSize` tears down (correct for a size sweep), `resizeTo` does not (correct for testing resize behavior itself). Document this in the file — using the wrong one is the easy mistake.
    - `const List<Size> kPhoneViewports`, `kTabletViewports`, `kDesktopViewports`, `kUltrawideViewports`, `kAllViewports`
    - `const List<double> kBoundaryWidths` = `[599, 600, 899, 900, 1023, 1024, 1199, 1200]`
    - `const Size kShortDesktop = Size(900, 600)`

  - [ ] **Step 1: Write the failing test**

  Create `Frontend/test/support/responsive_harness_self_test.dart`:

  ```dart
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
      expect(kAllViewports.length,
          kPhoneViewports.length +
              kTabletViewports.length +
              kDesktopViewports.length +
              kUltrawideViewports.length);
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

    testWidgets('pumpAtSize returns no errors for a clean tree',
        (tester) async {
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
        Row(children: const [SizedBox(width: 500, height: 10)]),
      );
      expect(errors, isNotEmpty, reason: 'a 500px child in a 100px row overflows');
      expect(shortError(errors.first), contains('overflow'));
    });

    testWidgets('a sweep reports overflow at every size, not just the first',
        (tester) async {
      // The regression this guards: without the per-size teardown, Flutter
      // reports each RenderFlex overflow only once per render object, so only
      // the first size in a sweep would report.
      final reported = <double>[];
      for (final size in const [Size(100, 100), Size(120, 100)]) {
        final errors = await pumpAtSize(
          tester,
          size,
          Row(children: const [SizedBox(width: 500, height: 10)]),
        );
        if (errors.isNotEmpty) reported.add(size.width);
      }
      expect(reported, [100, 120]);
    });
  }
  ```

  - [ ] **Step 2: Run test to verify it fails**

  Run: `cd Frontend && flutter test test/support/responsive_harness_self_test.dart`
  Expected: FAIL — `responsive_harness.dart` not found.

  - [ ] **Step 3: Write minimal implementation**

  Create `Frontend/test/support/responsive_harness.dart`:

  ```dart
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
  const List<Size> kUltrawideViewports = [
    Size(2560, 1440),
    Size(3440, 1440),
  ];

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
      // Explicit cast: takeException() returns `dynamic`, which strict-casts
      // rejects as an argument to List<Object>.add. Same form as the existing
      // harness in responsive_pages_audit_test.dart.
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
  ```

  - [ ] **Step 4: Run test to verify it passes**

  Run: `cd Frontend && flutter test test/support/responsive_harness_self_test.dart`
  Expected: PASS.

  Run: `cd Frontend && flutter analyze --no-fatal-infos test/support/`
  Expected: clean.

  - [ ] **Step 5: Commit**

  ```bash
  cd /c/Users/PC/nenjam_matrimony_app
  git add Frontend/test/support/responsive_harness.dart Frontend/test/support/responsive_harness_self_test.dart
  git commit -m "$(cat <<'MSG'
  test(layout): add the shared responsive harness

  Viewport matrices from the brief, the four breakpoint boundary pairs, a
  short-desktop case, pump/resize helpers, and an overflow guard that
  re-reports a RenderFlex overflow as a loud failure.

  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  MSG
  )"
  ```

  ---

### Task 4: Pin the legacy facade, then remove the global clamp

  This is the architectural change. It is split so the facade's behavior is
  pinned by tests **before** `NmAppFrame` is removed, which is what makes the
  removal reviewable.

  **Files:**
  - Create: `Frontend/test/core/utils/responsive_utils_legacy_test.dart`
  - Modify: `Frontend/lib/core/utils/responsive_utils.dart` (deprecate; delegate breakpoints to `WindowClassBreakpoints`)
  - Modify: `Frontend/lib/main.dart:382-384` (drop the `builder`)
  - Modify: `Frontend/lib/core/widgets/layout/responsive_layout.dart` (delete `NmAppFrame`, keep `NmContentConstraint`)
  - Modify: `Frontend/test/responsive_desktop_shell_test.dart` (drop ONLY the `builder:` line referencing the deleted `NmAppFrame`, so the file still compiles — assertions untouched; Task 5 rewrites them)
  - Test: `Frontend/test/core/layout/no_global_clamp_test.dart`

  **Interfaces:**
  - Consumes: `WindowClass`, `WindowClassBreakpoints` (Task 1); harness (Task 3).
  - Produces: `ResponsiveUtils` unchanged in signature, now `@Deprecated`. `NmAppFrame` no longer exists — any later task importing it is wrong.

  - [ ] **Step 1: Write the failing tests**

  Create `Frontend/test/core/utils/responsive_utils_legacy_test.dart` — pins current behavior so the facade cannot drift during migration:

  ```dart
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
    testWidgets('device-type thresholds are unchanged (600/1024)',
        (tester) async {
      expect(await _at(tester, 599, ResponsiveUtils.getDeviceType),
          DeviceType.phone);
      expect(await _at(tester, 600, ResponsiveUtils.getDeviceType),
          DeviceType.tablet);
      expect(await _at(tester, 1023, ResponsiveUtils.getDeviceType),
          DeviceType.tablet);
      expect(await _at(tester, 1024, ResponsiveUtils.getDeviceType),
          DeviceType.desktop);
    });

    testWidgets('grid columns are unchanged', (tester) async {
      expect(await _at(tester, 375, ResponsiveUtils.gridColumns), 2);
      expect(await _at(tester, 700, ResponsiveUtils.gridColumns), 3);
      expect(await _at(tester, 1440, ResponsiveUtils.gridColumns), 4);
    });

    testWidgets('maxContentWidth is unchanged', (tester) async {
      expect(await _at(tester, 375, ResponsiveUtils.maxContentWidth),
          double.infinity);
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
  ```

  Create `Frontend/test/core/layout/no_global_clamp_test.dart` — the assertion that the clamp is gone:

  ```dart
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
        testWidgets('MediaQuery reports the true ${size.width.toInt()}px width',
            (tester) async {
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

      testWidgets('a full-width child can occupy the whole 1920px window',
          (tester) async {
        await pumpAtSize(
          tester,
          const Size(1920, 1080),
          Container(key: const ValueKey('full'), color: Colors.red),
        );
        expect(tester.getSize(find.byKey(const ValueKey('full'))).width, 1920);
        expectNoOverflow(tester);
      });
    });

    test('NmAppFrame no longer exists', () {
      // Guard against reintroduction: if someone re-adds a global frame, this
      // file will fail to compile at the import, which is the intended signal.
      // Nothing to assert at runtime.
    });
  }
  ```

  - [ ] **Step 2: Run tests to verify they fail**

  Run: `cd Frontend && flutter test test/core/utils/responsive_utils_legacy_test.dart test/core/layout/no_global_clamp_test.dart`
  Expected: `responsive_utils_legacy_test.dart` PASSES already (it pins existing behavior — that is correct and intended). `no_global_clamp_test.dart` FAILS: reported width is `1056` (or `size.width` clamped) instead of 1920/2560/3440, because `NmAppFrame` is still installed.

  If the legacy test fails at this step, the facade's documented behavior was misread — stop and reconcile before changing anything.

  - [ ] **Step 3: Remove the clamp and deprecate the facade**

  3a. In `Frontend/lib/main.dart`, delete the `builder` argument (lines ~382–384). Remove the now-unused `NmAppFrame` import. The `MaterialApp.router` call ends after `routerConfig: router,`:

  ```dart
            // Routing
            routerConfig: router,
          );
  ```

  3b. In `Frontend/lib/core/widgets/layout/responsive_layout.dart`, delete the entire `NmAppFrame` class and its doc comment. Keep `NmContentConstraint`. Remove the `app_colors.dart` import if `NmContentConstraint` does not use it.

  3c. In `Frontend/lib/core/utils/responsive_utils.dart`, add the deprecation and delegate the breakpoint constants. Replace the class doc comment and the breakpoint block with:

  ```dart
  /// Legacy responsive helpers, kept as a compatibility facade.
  ///
  /// Superseded by `core/layout/window_class.dart` (classification) and
  /// `core/layout/content_width.dart` (max-width tokens). The replacement
  /// classifies from local `BoxConstraints`, so a surface in a narrow pane on a
  /// wide monitor sees its pane rather than the window — which the
  /// `MediaQuery`-based helpers here cannot do.
  ///
  /// Existing call sites keep working unchanged; they migrate per surface. The
  /// behavior below is pinned by `test/core/utils/responsive_utils_legacy_test.dart`
  /// so it cannot drift mid-migration.
  @Deprecated(
    'Use WindowClass (core/layout/window_class.dart) for classification and '
    'ContentWidth (core/layout/content_width.dart) for max widths. '
    'Classify from LayoutBuilder constraints, not MediaQuery.',
  )
  abstract final class ResponsiveUtils {
    // ─── Breakpoints ─────────────────────────────────────────────────
    static const double phoneSmall = 320;
    static const double phoneMedium = 375;
    static const double phoneLarge = 414;

    /// 600 — unchanged, and now the same number as
    /// [WindowClassBreakpoints.mediumMin].
    static const double tablet = WindowClassBreakpoints.mediumMin;

    /// 1024 — deliberately *not* [WindowClassBreakpoints.largeMin]. The legacy
    /// "desktop" threshold stays 1024 so existing callers are unaffected; the
    /// navigation rail's own threshold moves to 900 in the shell, which reads
    /// [WindowClass] directly rather than this value.
    static const double desktop = 1024;
  ```

  Add the import `import '../layout/window_class.dart';` and delete the now-unused `import '../constants/app_constants.dart';` — verified: `AppConstants` is referenced *only* by those two breakpoint constants.

  **Do NOT delete `navRailWidth` or `appFrameMaxWidth`** (controller ruling, pre-flight scan). `app_bottom_nav.dart:194` still reads `ResponsiveUtils.navRailWidth`, and Task 5 is what replaces that call site — deleting the member here would break the build, contradicting this task's own "analyze is clean" expectation. Instead:

  - Keep `navRailWidth = 96` exactly as it is, adding the comment `// Superseded by NavRailMetrics in app_bottom_nav.dart; kept until Task 5 migrates the call site.`
  - Keep `appFrameMaxWidth`, noting in its doc comment that `NmAppFrame` is gone so it now has no caller.

  Task 5 deletes both once `NavRailMetrics` replaces the call site.

  3d. **Neutralise the one test reference to the deleted class** (controller ruling). `test/responsive_desktop_shell_test.dart:63` passes `builder: (context, child) => NmAppFrame(...)`. With `NmAppFrame` deleted that is a **compile error**, not a test failure. Delete just that `builder:` line (and the `responsive_layout.dart` import if it becomes unused) so the file compiles. Leave every assertion in that file untouched — Task 5 rewrites them. After this edit the file's clamp assertions FAIL, which is the correct honest signal.

  - [ ] **Step 4: Run tests to verify they pass**

  Run: `cd Frontend && flutter test test/core/layout/no_global_clamp_test.dart test/core/utils/responsive_utils_legacy_test.dart`
  Expected: both PASS.

  Run the mobile regression suites — these must be green and **unmodified**:

  ```bash
  cd Frontend && flutter test test/responsive_audit_test.dart test/responsive_pages_audit_test.dart test/light_mode_only_test.dart test/bottom_nav_clearance_test.dart
  ```
  Expected: PASS. If any fails, the removal broke mobile — fix `lib/`, not the test.

  Run: `cd Frontend && flutter analyze --no-fatal-infos`
  Expected: clean. Deprecation *infos* on existing `ResponsiveUtils` callers are expected and acceptable (`--no-fatal-infos`); errors and warnings are not.

  `test/responsive_desktop_shell_test.dart` is expected to FAIL here — it asserts the clamp. It is rewritten in Task 5. Note it and continue.

  - [ ] **Step 5: Commit**

  ```bash
  cd /c/Users/PC/nenjam_matrimony_app
  git add Frontend/lib/main.dart Frontend/lib/core/widgets/layout/responsive_layout.dart Frontend/lib/core/utils/responsive_utils.dart Frontend/test/core/layout/no_global_clamp_test.dart Frontend/test/core/utils/responsive_utils_legacy_test.dart
  git commit -m "$(cat <<'MSG'
  refactor(layout): remove the global app-width clamp

  NmAppFrame capped the whole app at ~1056px in MaterialApp.builder and
  overrode the inner MediaQuery to report that width, so no descendant
  could observe a wider window -- multi-column grids, master-detail chat
  and two-column detail layouts were structurally impossible.

  MediaQuery now reports the true viewport. Ultrawide protection moves to
  the per-surface ContentWidth tokens. ResponsiveUtils stays as a
  deprecated facade with its behavior pinned by tests so the 55 pages can
  migrate incrementally.

  responsive_desktop_shell_test.dart asserted the clamp and is rewritten
  in the next commit.

  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  MSG
  )"
  ```

  ---

### Task 5: Adaptive navigation rail

  **Files:**
  - Modify: `Frontend/lib/core/widgets/navigation/app_bottom_nav.dart`
  - Rewrite: `Frontend/test/responsive_desktop_shell_test.dart`
  - Create: `Frontend/test/core/widgets/navigation/adaptive_nav_test.dart`

  **Interfaces:**
  - Consumes: `WindowClass` (Task 1), harness (Task 3), no-clamp state (Task 4).
  - Produces:
    - `class NmNavigationRail extends StatelessWidget` — `{Key? key, required List<Widget> children, required bool extended}`
    - `abstract final class NavRailMetrics` with `static const double compactWidth = 96`, `extendedWidth = 240`
    - `_NavItem` gains `required Axis axis` — `Axis.vertical` keeps today's Column; `Axis.horizontal` is icon + label in a Row for the extended rail.
    - Keys: `ValueKey('desktop-nav-rail')` retained on both variants; `ValueKey('desktop-nav-rail-extended')` added on the extended one only.

  - [ ] **Step 1: Write the failing tests**

  Create `Frontend/test/core/widgets/navigation/adaptive_nav_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nenjam_matrimony/core/widgets/navigation/app_bottom_nav.dart';

  import '../../../support/responsive_harness.dart';

  const _rail = ValueKey('desktop-nav-rail');
  const _extendedRail = ValueKey('desktop-nav-rail-extended');

  void main() {
    group('NavRailMetrics', () {
      test('widths are explicit', () {
        expect(NavRailMetrics.compactWidth, 96);
        expect(NavRailMetrics.extendedWidth, 240);
      });
    });

    group('NmNavigationRail', () {
      Future<void> pumpRail(
        WidgetTester tester, {
        required bool extended,
        Size size = const Size(1440, 900),
      }) async {
        await pumpAtSize(
          tester,
          size,
          Scaffold(
            body: Row(
              children: [
                NmNavigationRail(
                  extended: extended,
                  children: const [
                    Text('Discover'),
                    Text('Matches'),
                    Text('Inbox'),
                    Text('Premium'),
                  ],
                ),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
        );
      }

      testWidgets('compact variant is 96px and keeps the legacy key',
          (tester) async {
        await pumpRail(tester, extended: false);
        expect(find.byKey(_rail), findsOneWidget);
        expect(find.byKey(_extendedRail), findsNothing);
        expect(tester.getSize(find.byKey(_rail)).width,
            NavRailMetrics.compactWidth);
        expectNoOverflow(tester);
      });

      testWidgets('extended variant is 240px and carries both keys',
          (tester) async {
        await pumpRail(tester, extended: true);
        expect(find.byKey(_rail), findsOneWidget);
        expect(find.byKey(_extendedRail), findsOneWidget);
        expect(tester.getSize(find.byKey(_rail)).width,
            NavRailMetrics.extendedWidth);
        expectNoOverflow(tester);
      });

      testWidgets('extended rail does not overflow on a short window',
          (tester) async {
        await pumpRail(tester, extended: true, size: kShortDesktop);
        expectNoOverflow(tester);
      });
    });
  }
  ```

  Rewrite `Frontend/test/responsive_desktop_shell_test.dart`. Keep its existing `_pump` scaffolding and `_probe` key, but **delete the `builder: NmAppFrame(...)` line** (the widget no longer exists) and replace the `main()` assertions with:

  ```dart
  void main() {
    group('shell navigation affordance by window class', () {
      for (final width in kBoundaryWidths) {
        testWidgets('at ${width.toInt()}px', (tester) async {
          await _pump(tester, Size(width, 900));
          expect(tester.takeException(), isNull);

          final rail = find.byKey(const ValueKey('desktop-nav-rail'));
          final extended =
              find.byKey(const ValueKey('desktop-nav-rail-extended'));
          final probe = tester.getSize(find.byKey(_probe));

          if (width >= 1200) {
            expect(rail, findsOneWidget, reason: 'extended rail at large');
            expect(extended, findsOneWidget);
            expect(
              probe.width,
              width - NavRailMetrics.extendedWidth,
              reason: 'content fills the window minus the extended rail; the '
                  'old assertion here was probe.width == 960, which encoded '
                  'the removed global clamp',
            );
          } else if (width >= 900) {
            expect(rail, findsOneWidget, reason: 'icon rail at expanded');
            expect(extended, findsNothing);
            expect(probe.width, width - NavRailMetrics.compactWidth);
          } else {
            expect(rail, findsNothing, reason: 'bottom pill below 900');
            expect(
              probe.width,
              width,
              reason: 'the pill overlays via extendBody, so content is '
                  'full-width',
            );
          }
        });
      }
    });

    group('content is no longer clamped on wide windows', () {
      for (final size in [
        const Size(1440, 900),
        const Size(1920, 1080),
        const Size(2560, 1440),
      ]) {
        testWidgets('fills ${size.width.toInt()}px minus the rail',
            (tester) async {
          await _pump(tester, size);
          expect(
            tester.getSize(find.byKey(_probe)).width,
            size.width - NavRailMetrics.extendedWidth,
          );
        });
      }
    });

    testWidgets('extended rail switches tabs', (tester) async {
      await _pump(tester, const Size(1440, 900));
      await tester.tap(find.text('Premium'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('icon rail switches tabs at expanded width', (tester) async {
      await _pump(tester, const Size(1024, 768));
      await tester.tap(find.text('Premium'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('rail and page remain usable on a short window',
        (tester) async {
      await _pump(tester, kShortDesktop);
      expect(find.byKey(const ValueKey('desktop-nav-rail')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('repeated resizes across every boundary leave a valid layout',
        (tester) async {
      await _pump(tester, const Size(360, 800));
      for (final width in [...kBoundaryWidths, ...kBoundaryWidths.reversed]) {
        await resizeTo(tester, Size(width, 800));
        expect(tester.takeException(), isNull,
            reason: 'resize to ${width.toInt()}px produced an exception');
      }
    });
  }
  ```

  Add to that file's imports:

  ```dart
  import 'package:nenjam_matrimony/core/widgets/navigation/app_bottom_nav.dart';

  import 'support/responsive_harness.dart';
  ```

  - [ ] **Step 2: Run tests to verify they fail**

  Run: `cd Frontend && flutter test test/core/widgets/navigation/adaptive_nav_test.dart test/responsive_desktop_shell_test.dart`
  Expected: FAIL — `NmNavigationRail` and `NavRailMetrics` are undefined; `_DesktopRail` is still private and fixed at 96px with no extended variant.

  - [ ] **Step 3: Implement the adaptive rail**

  3a. In `app_bottom_nav.dart`, add the metrics class near the top (after the imports, before `navContentInset`):

  ```dart
  /// Explicit widths for the two navigation-rail variants.
  ///
  /// The rail is a *sibling* of the page content in the shell's Row, so content
  /// never has to subtract these itself — a content-level LayoutBuilder already
  /// receives the post-rail width.
  abstract final class NavRailMetrics {
    /// Icon-only rail, shown at [WindowClass.expanded].
    static const double compactWidth = AppSpacing.xl8; // 96

    /// Icon + label rail, shown at [WindowClass.large].
    static const double extendedWidth = 240;
  }
  ```

  3b. Replace the `final useRail = ResponsiveUtils.isDesktop(context);` line with window-class logic. The window class is the correct read here — which navigation affordance to show is a shell-level decision:

  ```dart
      // Shell-level decision, so the window is the right thing to measure.
      // Everything laid out *inside* the shell classifies from its own
      // LayoutBuilder constraints instead — see WindowClass.of's docs.
      final windowClass = WindowClass.of(context);
      final useRail = windowClass.isAtLeastExpanded;
      final useExtendedRail = windowClass.isLarge;
  ```

  3c. Update the `body`/`bottomNavigationBar` to pass the flag through:

  ```dart
          body: useRail
              ? Row(
                  children: [
                    NmNavigationRail(
                      extended: useExtendedRail,
                      children: items(
                        AppColors.surfaceLight,
                        axis: useExtendedRail ? Axis.horizontal : Axis.vertical,
                      ),
                    ),
                    Expanded(child: navigationShell),
                  ],
                )
              : navigationShell,
  ```

  The pill branch calls `items(surfaceColor)` — give `items` a named `axis` parameter defaulting to `Axis.vertical` so the pill call site is unchanged. In the `items` closure, pass `axis: axis` into each `_NavItem`.

  3d. Replace `_DesktopRail` with the public, two-variant `NmNavigationRail`:

  ```dart
  /// Left-hand navigation for [WindowClass.expanded] and wider, in place of the
  /// floating pill.
  ///
  /// Two variants, same items and same behavior: an icon-only rail at expanded
  /// widths, and an [extended] icon + label rail at large widths. Separated from
  /// the page by surface colour rather than a border.
  class NmNavigationRail extends StatelessWidget {
    final List<Widget> children;

    /// Whether to show the wider icon + label variant.
    final bool extended;

    const NmNavigationRail({
      super.key,
      required this.children,
      required this.extended,
    });

    @override
    Widget build(BuildContext context) {
      return Container(
        // Retained so existing tests and tooling keep locating the rail; the
        // extended variant adds its own key below rather than changing this one.
        key: const ValueKey('desktop-nav-rail'),
        width: extended
            ? NavRailMetrics.extendedWidth
            : NavRailMetrics.compactWidth,
        color: AppColors.surfaceLight,
        child: SafeArea(
          right: false,
          child: KeyedSubtree(
            key: extended
                ? const ValueKey('desktop-nav-rail-extended')
                : const ValueKey('desktop-nav-rail-compact'),
            // Scrolls rather than overflows on a short window.
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: extended ? AppSpacing.md : AppSpacing.sm,
                vertical: AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: extended
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.center,
                children: [
                  for (final item in children)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: item,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }
  ```

  3e. Give `_NavItem` an axis. Add `required this.axis` to its fields and constructor, then split its body. Keep the existing vertical `Column` exactly as it is for `Axis.vertical`; add a horizontal arrangement that reuses the same icon stack and label widgets:

  ```dart
    /// Vertical in the bottom pill and the icon rail (icon over label);
    /// horizontal in the extended rail (icon beside label).
    final Axis axis;
  ```

  In `build`, keep the existing `Semantics` + `InkWell` + `Padding` wrapper and swap only the inner layout:

  ```dart
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: axis == Axis.horizontal ? AppSpacing.sm : 0,
            ),
            child: axis == Axis.vertical
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      iconStack,
                      const SizedBox(height: AppSpacing.xs2),
                      labelWidget,
                      const SizedBox(height: AppSpacing.xs2),
                      activeIndicator,
                    ],
                  )
                : Row(
                    children: [
                      iconStack,
                      const SizedBox(width: AppSpacing.md),
                      // Flexible, so a long or localized label ellipsizes
                      // inside the 240px rail instead of overflowing it.
                      Flexible(child: labelWidget),
                    ],
                  ),
          ),
  ```

  Extract the three existing pieces into local variables above the `return` — `iconStack` (the `Stack` with the `AnimatedContainer` circle and `NavBadge`), `labelWidget` (the `Padding`+`FittedBox`+`AnimatedDefaultTextStyle`+`Text`), and `activeIndicator` (the trailing `AnimatedContainer` bar) — moving the code verbatim rather than rewriting it, so badges, animations and semantics are untouched.

  For the horizontal variant, `labelWidget` must align left: wrap its `Text` so `textAlign` is `TextAlign.start` when `axis == Axis.horizontal`, and drop the `FittedBox` in that case (the `Flexible` + `TextOverflow.ellipsis` already handles long labels; a `FittedBox` inside a `Flexible` would shrink the text instead of ellipsizing).

  3f. Add the import `import '../../layout/window_class.dart';` and remove `import '../../utils/responsive_utils.dart';` if nothing else in the file uses it.

  - [ ] **Step 4: Run tests to verify they pass**

  Run: `cd Frontend && flutter test test/core/widgets/navigation/adaptive_nav_test.dart test/responsive_desktop_shell_test.dart`
  Expected: PASS.

  Run the mobile regression suites, unmodified:
  ```bash
  cd Frontend && flutter test test/responsive_audit_test.dart test/responsive_pages_audit_test.dart test/bottom_nav_clearance_test.dart test/light_mode_only_test.dart
  ```
  Expected: PASS — the pill path below 900 is untouched.

  Run: `cd Frontend && flutter analyze --no-fatal-infos`
  Expected: clean.

  - [ ] **Step 5: Commit**

  ```bash
  cd /c/Users/PC/nenjam_matrimony_app
  git add Frontend/lib/core/widgets/navigation/app_bottom_nav.dart Frontend/test/responsive_desktop_shell_test.dart Frontend/test/core/widgets/navigation/adaptive_nav_test.dart
  git commit -m "$(cat <<'MSG'
  feat(nav): adaptive navigation rail at expanded and large widths

  Bottom pill below 900 (unchanged), 96px icon rail at 900-1199, 240px
  icon+label rail at 1200+. _DesktopRail becomes the public
  NmNavigationRail with an extended flag; _NavItem gains an axis so the
  extended variant lays out icon beside label while the pill and icon rail
  keep today's stacked arrangement. Badges, semantics labels, animations
  and goBranch behavior are reused as-is.

  The rail threshold moves from 1024 to 900, so tablet landscape and small
  laptop windows now get a rail.

  responsive_desktop_shell_test.dart previously asserted probe.width == 960
  at 1920px, which encoded the removed global clamp. It now asserts content
  fills the window minus the rail, and sweeps every breakpoint boundary
  plus repeated resizes.

  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  MSG
  )"
  ```

  ---

### Task 6: Adaptive grid + Discover and profile-detail surfaces

  **Files:**
  - Create: `Frontend/lib/core/layout/adaptive_grid.dart`
  - Test: `Frontend/test/core/layout/adaptive_grid_test.dart`
  - Modify: `Frontend/lib/features/discover/presentation/pages/discover_page.dart`
  - Modify: `Frontend/lib/features/profile_detail/presentation/pages/profile_detail_page.dart`
  - Create: `Frontend/test/features/discover/discover_responsive_test.dart`
  - Create: `Frontend/test/features/profile_detail/profile_detail_responsive_test.dart`

  **Interfaces:**
  - Consumes: `WindowClass` (1), `ContentWidth`/`NmContentWidth` (2), harness (3).
  - Produces:
    - `abstract final class AdaptiveGrid` with
      `static GridMetrics resolve({required double availableWidth, required double horizontalPadding, required double spacing, double targetTileWidth = 320, double maxTileWidth = 420, int maxColumns = 5})`
    - `class GridMetrics` — `final int columns; final double tileWidth; final double gutter;` (const, with `==`/`hashCode`)

  - [ ] **Step 1: Write the failing test**

  Create `Frontend/test/core/layout/adaptive_grid_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:nenjam_matrimony/core/layout/adaptive_grid.dart';

  void main() {
    GridMetrics at(double width) => AdaptiveGrid.resolve(
          availableWidth: width,
          horizontalPadding: 32,
          spacing: 16,
        );

    group('column count derives from post-padding width', () {
      test('a 320px phone gets one column', () {
        expect(at(320).columns, 1);
      });

      test('column count grows monotonically with width', () {
        var previous = 0;
        for (var w = 320.0; w <= 3440; w += 20) {
          final columns = at(w).columns;
          expect(columns, greaterThanOrEqualTo(previous),
              reason: 'columns must never decrease as width grows (at ${w}px)');
          previous = columns;
        }
      });

      test('is capped so ultrawide does not produce a dozen columns', () {
        expect(at(3440).columns, lessThanOrEqualTo(5));
      });
    });

    group('tile width', () {
      test('never exceeds the cap even on an ultrawide surface', () {
        for (final w in [1920.0, 2560.0, 3440.0]) {
          expect(at(w).tileWidth, lessThanOrEqualTo(420),
              reason: 'capping only the column count would yield giant cards');
        }
      });

      test('tiles plus gutters fit the available width', () {
        for (var w = 320.0; w <= 3440; w += 37) {
          final m = at(w);
          final used = m.tileWidth * m.columns + m.gutter * (m.columns - 1);
          expect(used, lessThanOrEqualTo(w - 32 + 0.5),
              reason: 'grid must fit inside its padded width at ${w}px');
        }
      });

      test('a narrow pane on a wide monitor yields one column', () {
        // The caller passes its LayoutBuilder width, not the window width.
        expect(at(360).columns, 1);
      });
    });

    group('degenerate input', () {
      test('always yields at least one column and a non-negative tile', () {
        final m = at(10);
        expect(m.columns, 1);
        expect(m.tileWidth, greaterThanOrEqualTo(0));
      });
    });
  }
  ```

  - [ ] **Step 2: Run test to verify it fails**

  Run: `cd Frontend && flutter test test/core/layout/adaptive_grid_test.dart`
  Expected: FAIL — `adaptive_grid.dart` not found.

  - [ ] **Step 3: Write the grid implementation**

  Create `Frontend/lib/core/layout/adaptive_grid.dart`:

  ```dart
  import 'dart:math' as math;

  /// A resolved grid: how many columns, how wide each tile, and the gutter.
  class GridMetrics {
    final int columns;
    final double tileWidth;
    final double gutter;

    const GridMetrics({
      required this.columns,
      required this.tileWidth,
      required this.gutter,
    });

    @override
    bool operator ==(Object other) =>
        other is GridMetrics &&
        other.columns == columns &&
        other.tileWidth == tileWidth &&
        other.gutter == gutter;

    @override
    int get hashCode => Object.hash(columns, tileWidth, gutter);

    @override
    String toString() =>
        'GridMetrics(columns: $columns, tileWidth: $tileWidth, gutter: $gutter)';
  }

  /// Derives grid metrics from the width a surface actually has.
  ///
  /// Column count comes from a target tile width rather than a
  /// breakpoint-to-count lookup table, so intermediate widths and continuous
  /// browser resizing behave correctly instead of snapping at a few hardcoded
  /// sizes.
  ///
  /// Both the column count *and* the tile width are capped: capping only the
  /// columns would let a 3440px surface render four 800px cards.
  abstract final class AdaptiveGrid {
    static GridMetrics resolve({
      required double availableWidth,
      required double horizontalPadding,
      required double spacing,
      double targetTileWidth = 320,
      double maxTileWidth = 420,
      int maxColumns = 5,
    }) {
      final padded = availableWidth - horizontalPadding;
      if (padded <= 0) {
        return GridMetrics(columns: 1, tileWidth: 0, gutter: spacing);
      }

      // How many tiles of roughly the target width fit, counting the gutters
      // between them.
      var columns =
          ((padded + spacing) / (targetTileWidth + spacing)).floor();
      columns = columns.clamp(1, maxColumns);

      var tileWidth = (padded - spacing * (columns - 1)) / columns;

      // If that leaves tiles wider than the cap, add columns until they fit or
      // the column cap is reached.
      while (tileWidth > maxTileWidth && columns < maxColumns) {
        columns += 1;
        tileWidth = (padded - spacing * (columns - 1)) / columns;
      }

      // At the column cap on a very wide surface, stop growing the tiles: the
      // grid then sits narrower than its container rather than stretching.
      tileWidth = math.min(tileWidth, maxTileWidth);

      return GridMetrics(
        columns: columns,
        tileWidth: math.max(0, tileWidth),
        gutter: spacing,
      );
    }
  }
  ```

  - [ ] **Step 4: Run test to verify it passes**

  Run: `cd Frontend && flutter test test/core/layout/adaptive_grid_test.dart`
  Expected: PASS.

  - [ ] **Step 5: Commit the grid primitive**

  ```bash
  cd /c/Users/PC/nenjam_matrimony_app
  git add Frontend/lib/core/layout/adaptive_grid.dart Frontend/test/core/layout/adaptive_grid_test.dart
  git commit -m "$(cat <<'MSG'
  feat(layout): derive grid metrics from available width

  Column count comes from a target tile width rather than a breakpoint
  lookup, so intermediate widths and continuous resizing behave correctly.
  Caps both the column count and the tile width -- capping only columns
  would let an ultrawide surface render a few giant cards.

  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  MSG
  )"
  ```

  - [ ] **Step 6: Read the two pages before changing them**

  Run:
  ```bash
  cd Frontend && sed -n '1,120p' lib/features/discover/presentation/pages/discover_page.dart
  cd Frontend && sed -n '1,120p' lib/features/profile_detail/presentation/pages/profile_detail_page.dart
  ```

  Identify, and write down before editing:
  - Discover: the widget that renders the profile list/feed, and its current scroll parent.
  - Profile detail: the list of section widgets rendered in the single scrolling column, in order.

  Do not restructure state, providers, or data flow. Only the arrangement changes.

  - [ ] **Step 7: Write the failing surface tests**

  **These two tests need the real provider and fake shapes, which depend on files not yet read. Read them first, then write the tests against what you find — do not guess provider names.**

  ```bash
  cd Frontend
  # How existing tests override providers and shape fakes (no mockito/mocktail
  # anywhere in this repo — hand-written fakes with noSuchMethod forwarding):
  grep -rln "ProviderScope(" test/ | head -5
  ls test/features
  # The providers each page actually watches:
  grep -n "Provider" lib/features/discover/presentation/providers/discover_providers.dart | head -20
  grep -n "Provider" lib/features/profile_detail/presentation/providers/profile_detail_providers.dart | head -20
  ```

  `profile_detail` already ships a `profile_detail_mock_datasource.dart`, so prefer overriding the repository provider to the mock datasource over building a new fake.

  **Required assertions — `discover_responsive_test.dart`:**

  | Test | Size | Assert |
  |---|---|---|
  | one column on a phone | 360×800 | exactly one card per row; `expectNoOverflow` |
  | multiple columns on desktop | 1440×900 | ≥2 cards share a row (compare each card's `getTopLeft().dy`) |
  | tile width capped | 3440×1440 | every card's width ≤ 420 |
  | card aspect ratio preserved | 1440×900 | each card's photo width/height ratio equals the single-column ratio measured at 360px, within 0.01 |
  | continuous resize | 360 → each of `kBoundaryWidths` → back | `resizeTo` returns no exceptions at any step |

  To count cards per row, find the card widgets and group `tester.getTopLeft(...).dy` — cards sharing a `dy` are in one row. Use the discover page's existing card widget type as the finder; read the page to get its name.

  **Required assertions — `profile_detail_responsive_test.dart`:**

  | Test | Size | Assert |
  |---|---|---|
  | single column | 1199×900 | no `Row` splitting the sections; sections stacked (strictly increasing `dy`) |
  | two columns | 1200×900 | two section groups side by side (two distinct `dx` groups) |
  | capped on ultrawide | 3440×1440 | the sections' bounding width ≤ `ContentWidth.detail` |
  | reading order preserved | 1200×900 | collecting the section keys in widget-tree order yields the **same sequence** as at 1199px — the partition must not reorder |

  The reading-order test is the important one: give each section a stable `ValueKey` in the production code, collect them via `find.byType(...)` evaluation order at both widths, and assert the two lists are equal.

  - [ ] **Step 8: Run the surface tests to verify they fail**

  Run: `cd Frontend && flutter test test/features/discover/discover_responsive_test.dart test/features/profile_detail/profile_detail_responsive_test.dart`
  Expected: FAIL — discover still renders a single column at every width; profile detail still single-column at 1200.

  - [ ] **Step 9: Implement the Discover grid**

  Wrap the feed in a `LayoutBuilder`, classify from `constraints.maxWidth`, and drive a `SliverGrid`/`GridView` from `AdaptiveGrid.resolve`. Pattern:

  ```dart
  LayoutBuilder(
    builder: (context, constraints) {
      // Local constraints, not MediaQuery: this surface may sit in a pane.
      final metrics = AdaptiveGrid.resolve(
        availableWidth: constraints.maxWidth,
        horizontalPadding: AppSpacing.base * 2,
        spacing: AppSpacing.base,
      );
      if (metrics.columns == 1) {
        // Keep the existing single-column feed verbatim on compact surfaces.
        return existingFeedListView;
      }
      return GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.base),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: metrics.columns,
          crossAxisSpacing: metrics.gutter,
          mainAxisSpacing: metrics.gutter,
          // Must come from the existing card's own ratio so photo proportions
          // are preserved. Find it before writing this line:
          //   grep -rn "AspectRatio\|aspectRatio" \
          //     lib/features/discover/presentation/
          // If the card has no explicit ratio, measure it at 360px in the test
          // and use that value as a named constant here -- do not invent one.
          childAspectRatio: kDiscoverCardAspectRatio,
        ),
        itemCount: profiles.length,
        itemBuilder: (context, index) => existingProfileCard(profiles[index]),
      );
    },
  )
  ```

  Keep the existing profile-card widget and its `AspectRatio` untouched. If the single-column feed has behavior the grid cannot express (e.g. a swipeable reel), keep the single-column path for `columns == 1` and only grid above that, as shown.

  - [ ] **Step 10: Implement profile-detail two-column**

  Wrap the section column in a `LayoutBuilder`. At `WindowClass.fromWidth(constraints.maxWidth).isLarge`, split into two columns inside `NmContentWidth(maxWidth: ContentWidth.detail, ...)`; otherwise keep today's single column verbatim.

  Critical, per spec §6.3: build **one** ordered list of section widgets and partition it, so the two columns' concatenated order equals the single-column order. Do not hand-place sections into two hardcoded lists — that is what scrambles reading and focus order.

  ```dart
  LayoutBuilder(
    builder: (context, constraints) {
      final windowClass = WindowClass.fromWidth(constraints.maxWidth);
      final sections = <Widget>[ /* the existing sections, in today's order */ ];

      if (!windowClass.isLarge) {
        return Column(children: sections);
      }

      // Partition, not reorder: concatenating left + right reproduces the
      // single-column order, so keyboard traversal and the semantics tree stay
      // in the order a reader expects.
      const leftCount = 2; // gallery + key facts
      return NmContentWidth(
        maxWidth: ContentWidth.detail,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Column(children: sections.take(leftCount).toList()),
            ),
            const SizedBox(width: AppSpacing.xl2),
            Expanded(
              flex: 3,
              child: Column(children: sections.skip(leftCount).toList()),
            ),
          ],
        ),
      );
    },
  )
  ```

  - [ ] **Step 11: Run all tests to verify they pass**

  Run: `cd Frontend && flutter test test/features/discover/discover_responsive_test.dart test/features/profile_detail/profile_detail_responsive_test.dart test/core/layout/`
  Expected: PASS.

  Run the mobile regression suites, unmodified:
  ```bash
  cd Frontend && flutter test test/responsive_audit_test.dart test/responsive_pages_audit_test.dart test/bottom_nav_clearance_test.dart test/light_mode_only_test.dart
  ```
  Expected: PASS.

  Run: `cd Frontend && dart format lib/core/layout lib/features/discover lib/features/profile_detail && flutter analyze --no-fatal-infos`
  Expected: clean.

  - [ ] **Step 12: Commit**

  ```bash
  cd /c/Users/PC/nenjam_matrimony_app
  git add Frontend/lib/features/discover Frontend/lib/features/profile_detail Frontend/test/features/discover Frontend/test/features/profile_detail
  git commit -m "$(cat <<'MSG'
  feat(discover,profile): adaptive grid and two-column detail

  Discover derives its column count from local LayoutBuilder constraints
  via AdaptiveGrid, keeping the existing single-column feed on compact
  surfaces and the existing card composition and photo aspect ratios
  throughout.

  Profile detail splits into two columns at large widths inside the
  ContentWidth.detail cap. The sections are partitioned from one ordered
  list rather than hand-placed, so concatenating the columns reproduces the
  single-column order and keyboard traversal stays sane.

  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  MSG
  )"
  ```

  ---

### Task 7: Chat master-detail (isolated)

  The highest-risk task, isolated per the spec. **Do not combine this commit with any other task.**

  **Files:**
  - Modify: `Frontend/lib/core/router/app_router.dart` (move the chat route into the Inbox branch)
  - Create: `Frontend/lib/features/inbox/presentation/pages/inbox_shell_page.dart`
  - Modify: `Frontend/lib/features/inbox/presentation/pages/inbox_page.dart` (selection navigates; no push at wide widths)
  - Create: `Frontend/test/features/inbox/chat_master_detail_test.dart`

  **Interfaces:**
  - Consumes: `WindowClass` (1), harness (3).
  - Produces: `class InboxShellPage extends StatelessWidget` — `{Key? key, String? selectedConversationId, ConversationEntity? initialConversation}`. Renders the list alone on compact, and list + detail on expanded/large.

  **Verified current structure (do not re-derive):**
  - `RouteNames.messages` = `/messages`, 3rd `StatefulShellBranch`, `NoTransitionPage(child: InboxPage())`.
  - `RouteNames.chatDetailPattern` = `'/chat-detail/:conversationId'`, registered as a **root-level** `GoRoute` at `app_router.dart:635-646`, with a comment stating it deliberately covers the whole shell. Its builder is `ChatDetailRoutePage(conversationId: state.pathParameters['conversationId']!, initial: state.extra is ConversationEntity ? state.extra! as ConversationEntity : null)`.
  - `RouteNames.chatDetailPath(String conversationId)` builds the path with `Uri.encodeComponent`.

  - [ ] **Step 1: Write the failing test**

  Create `Frontend/test/features/inbox/chat_master_detail_test.dart`. Build a real `GoRouter` over the modified route table with a fake conversation repository.

  **Read these before writing the fakes — the provider and repository names must come from the source, not from this plan:**

  ```bash
  cd Frontend
  sed -n '1,80p' lib/features/inbox/presentation/providers/inbox_providers.dart
  sed -n '1,40p' lib/features/inbox/domain/repositories/conversation_repository.dart
  sed -n '1,40p' lib/features/inbox/domain/entities/conversation_entity.dart
  # The existing router test shows how to build a GoRouter in a test:
  sed -n '1,80p' test/router_refresh_test.dart
  ```

  `test/router_refresh_test.dart` already constructs a router under test — reuse its approach rather than inventing a second one.

  **Required assertions.** Each row is one `testWidgets`. "list" = the conversation-list widget; "chat" = the chat-detail widget; use the real type names found above.

  | Group | Test | Setup | Assert |
  |---|---|---|---|
  | topology | list alone on compact | 390×844, location `/messages` | list present, chat absent |
  | topology | list + empty pane at large | 1440×900, `/messages` | list present **and** the empty-state widget present; chat absent |
  | topology | chat full-screen on compact | 390×844, chat path for `c1` | chat present, list **absent** |
  | topology | list + chat at large | 1440×900, chat path for `c1` | both present; the `c1` row renders selected |
  | URL | selection changes the URL | 1440×900, `/messages`, tap the `c1` row | `router.routerDelegate.currentConfiguration.uri.toString()` == the chat path for `c1` |
  | URL | deep link restores selection | router built with `initialLocation` = chat path for `c1`, 1440×900 | list + chat for `c1`, no exception |
  | URL | back leaves no duplicate | 1440×900, tap `c1`, then `router.pop()` | location == `/messages`; chat absent; exactly one list in the tree |
  | URL | repeated selection does not stack history | tap `c1`, `c2`, `c3` at 1440 | location is `c3`'s path; a single `pop()` returns to `/messages`, proving `go` not `push` |
  | resize | selection survives shrinking | 1440 on `c1`'s path → `resizeTo(Size(390, 844))` | chat for `c1` present full-screen, list absent |
  | resize | selection survives widening | continue → `resizeTo(Size(1440, 900))` | list + chat for `c1`, still selected |
  | errors | unknown id keeps existing error state | fake repo throws/returns null for `nope`, 1440×900 | the page's existing error widget is shown; the two-pane layout is intact; `expectNoOverflow` |
  | scrolling | panes scroll independently | 1440×900 with enough items to scroll both | fling the list; the chat pane's `ScrollController.offset` (or its `Scrollable`'s position) is unchanged; then the reverse |

  For the "no duplicate route" and "no stacked history" tests, read the location from the router you constructed rather than from any page state — the point is that the URL, not widget state, holds the selection.

  - [ ] **Step 2: Run test to verify it fails**

  Run: `cd Frontend && flutter test test/features/inbox/chat_master_detail_test.dart`
  Expected: FAIL — `/chat-detail/:id` still replaces the whole shell, so the conversation list is absent at 1440.

  - [ ] **Step 3: Move the chat route into the Inbox branch**

  In `app_router.dart`:

  3a. Delete the root-level `GoRoute` at ~635–646 for `RouteNames.chatDetailPattern`, **and** the comment block above it that explains it covers the whole shell (that rationale no longer holds).

  **The chat URL must not change — this is settled, not a judgment call.**

  Verified: `test/router_refresh_test.dart:70` exercises `/chat-detail/abc?ref=push`, a **push-notification deep link**, and `route_entity_resolvers.dart` resolves a conversation from that URL for cold starts. Changing the path to `/messages/chat-detail/:id` would break links already delivered in push payloads and shared by users.

  So: keep `RouteNames.chatDetailPattern` = `/chat-detail/:conversationId` **exactly as it is**, and keep it registered inside the Inbox `StatefulShellBranch` using its **absolute** path. go_router permits an absolute path on a branch route as long as it does not nest under another path segment — register it as a second `GoRoute` in the branch's `routes` list, a sibling of `/messages`, not a child of it. Both then live in the Inbox branch, so the shell and its rail stay visible on the chat route, while the URL is untouched.

  Do **not** add `chatDetailChildPath`. Do **not** change `chatDetailPath`, `isChatDetailLocation`, or any existing assertion in `router_refresh_test.dart`.

  3b. Replace the Inbox branch so the chat route is a sibling of `/messages` **inside the same branch**, rendering inside the shell:

  ```dart
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RouteNames.messages,
                  name: RouteNames.messagesName,
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: InboxShellPage()),
                ),
                // In the Inbox branch (so the shell and its rail stay visible
                // and the chat can sit beside the list at expanded widths), but
                // at its own absolute path, unchanged: /chat-detail/:id is a
                // live push-notification deep link and must keep working.
                //
                // The URL stays authoritative -- this is a real, refreshable,
                // deep-linkable route at every width. Only its presentation
                // changes with available width.
                GoRoute(
                  path: RouteNames.chatDetailPattern,
                  name: RouteNames.chatDetailName,
                  pageBuilder: (context, state) => NoTransitionPage(
                    child: InboxShellPage(
                      selectedConversationId:
                          state.pathParameters['conversationId']!,
                      // Present for in-app navigation; absent after a reload or
                      // for a copied link, in which case the page looks the
                      // thread up by id.
                      initialConversation: state.extra is ConversationEntity
                          ? state.extra! as ConversationEntity
                          : null,
                    ),
                  ),
                ),
              ],
            ),
  ```

  3c. `route_names.dart` needs **no changes**. `chatDetail`, `chatDetailPattern`, `chatDetailPath` and `isChatDetailLocation` all keep their current values and behavior, which is what keeps the existing deep links and `router_refresh_test.dart` valid.

  3d. Verify the route move did not break deep-link resolution. `lib/core/router/route_entity_resolvers.dart` looks a conversation up from the URL for a cold start, and `route_entity_pages.dart` holds the chat route's body — read both and confirm `InboxShellPage` is wired in consistently with how `ChatDetailRoutePage` was:

  ```bash
  cd Frontend && sed -n '1,60p' lib/core/router/route_entity_pages.dart && sed -n '1,40p' lib/core/router/route_entity_resolvers.dart
  ```

  If the chat route's page was built through a helper in `route_entity_pages.dart` rather than inline, change it **there** and keep the route table calling that helper, matching the existing structure.

  - [ ] **Step 4: Implement `InboxShellPage`**

  Create `Frontend/lib/features/inbox/presentation/pages/inbox_shell_page.dart`:

  ```dart
  /// Inbox, as either one pane or two depending on available width.
  ///
  /// The URL is the source of truth for the selection, so the same route works
  /// as a deep link, survives a reload, and is restored by browser back and
  /// forward at every width. Only the *presentation* changes: on compact the
  /// selected conversation is a full-screen page; at expanded and wider it sits
  /// beside the list.
  class InboxShellPage extends StatelessWidget {
    final String? selectedConversationId;
    final ConversationEntity? initialConversation;

    const InboxShellPage({
      super.key,
      this.selectedConversationId,
      this.initialConversation,
    });

    @override
    Widget build(BuildContext context) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final windowClass = WindowClass.fromWidth(constraints.maxWidth);

          if (!windowClass.isAtLeastExpanded) {
            // Compact: one pane at a time, exactly as before.
            return selectedConversationId == null
                ? const InboxPage()
                : ChatDetailRoutePage(
                    conversationId: selectedConversationId!,
                    initial: initialConversation,
                  );
          }

          return Row(
            children: [
              SizedBox(
                width: _listPaneWidth,
                // Its own scrollable, so flinging the list never scrolls the
                // chat and vice versa.
                child: InboxPage(selectedConversationId: selectedConversationId),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selectedConversationId == null
                    ? const _NoConversationSelected()
                    : ChatDetailRoutePage(
                        key: ValueKey(selectedConversationId),
                        conversationId: selectedConversationId!,
                        initial: initialConversation,
                      ),
              ),
            ],
          );
        },
      );
    }

    static const double _listPaneWidth = 360;
  }
  ```

  Add `_NoConversationSelected` — an empty state using the existing `empty_state.dart` widget from `lib/core/widgets/feedback/` (read it first; do not write a new one).

  The `ValueKey(selectedConversationId)` on the detail pane is load-bearing: it forces a fresh chat state when the selection changes, rather than reusing the previous conversation's controllers.

  - [ ] **Step 5: Make selection navigate rather than push**

  In `inbox_page.dart`:
  - Add `final String? selectedConversationId;` to the constructor so a row can render as selected.
  - Change the row tap from a push to `context.go(RouteNames.chatDetailPath(id), extra: conversation)`. `go` (not `push`) keeps one detail route on the stack, so repeatedly selecting conversations at desktop width cannot accumulate history entries or leave a stale pane.

  Read the current tap handler first and preserve everything else it does (read receipts, analytics, etc.):
  ```bash
  cd Frontend && grep -n "push\|go(\|chatDetail" lib/features/inbox/presentation/pages/inbox_page.dart
  ```

  - [ ] **Step 6: Run tests to verify they pass**

  Run: `cd Frontend && flutter test test/features/inbox/chat_master_detail_test.dart`
  Expected: PASS, all groups.

  Run the full suite — this task touches the router, so everything is in scope:
  ```bash
  cd Frontend && flutter test
  ```
  Expected: PASS. Any router-related failure here is a real regression from the route move; fix the production code.

  Run: `cd Frontend && dart format lib/core/router lib/features/inbox && flutter analyze --no-fatal-infos`
  Expected: clean.

  - [ ] **Step 7: Commit**

  ```bash
  cd /c/Users/PC/nenjam_matrimony_app
  git add Frontend/lib/core/router Frontend/lib/features/inbox Frontend/test/features/inbox
  git commit -m "$(cat <<'MSG'
  feat(inbox): master-detail chat at expanded and large widths

  The chat route moves from root level into the Inbox branch, so it
  renders beside the conversation list inside the shell instead of
  covering it. On compact it stays a full-screen page.

  The URL is unchanged: /chat-detail/:conversationId is a live
  push-notification deep link, so the route keeps its absolute path and
  sits as a sibling of /messages within the branch rather than nesting
  under it. route_names.dart and router_refresh_test.dart are untouched.

  The URL remains authoritative at every width: the route is still
  deep-linkable and refreshable, selection uses go() rather than push() so
  repeated selections cannot accumulate history entries, and resizing
  across 900 preserves the selected conversation in both directions
  because the selection lives in the URL rather than in widget state.

  Unknown conversation ids keep their existing error behavior. The two
  panes own their own scrollables.

  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  MSG
  )"
  ```

  ---

### Task 8: Remaining-screen audit and constraints

  **Files:**
  - Create: `Frontend/test/responsive_screen_audit_test.dart`
  - Modify: whichever pages the audit shows need a token or a fix (one commit per feature group)
  - Create: `docs/superpowers/reports/2026-10-22-responsive-audit.md`

  **Interfaces:**
  - Consumes: everything above.
  - Produces: the per-page audit table the spec §10 promises.

  - [ ] **Step 1: Enumerate every page and build the audit table skeleton**

  Run:
  ```bash
  cd Frontend && find lib/features -name "*_page.dart" | sort > /c/Users/PC/AppData/Local/Temp/claude/c--Users-PC-nenjam-matrimony-app/b06213bb-c387-4ba7-a325-9f3cfc58baf3/scratchpad/pages.txt && wc -l < /c/Users/PC/AppData/Local/Temp/claude/c--Users-PC-nenjam-matrimony-app/b06213bb-c387-4ba7-a325-9f3cfc58baf3/scratchpad/pages.txt
  ```

  Create `docs/superpowers/reports/2026-10-22-responsive-audit.md` with one row per page and columns: `Page | Route | Token applied | Status (inspected/changed/tested/unaudited) | Notes`. Fill `unaudited` for all rows initially; update rows as you work. Every row must end with a real status — the spec forbids silently claiming coverage.

  - [ ] **Step 2: Write the sweep test**

  Create `Frontend/test/responsive_screen_audit_test.dart` sweeping the pages that can be pumped without heavy fakes (static/presentational pages first — splash, onboarding, help, safety, privacy, language, premium) across `kAllViewports`, asserting `expectNoOverflow` after each pump. Follow `test/responsive_pages_audit_test.dart`'s existing harness shape for building each page — read it first:

  ```bash
  cd Frontend && sed -n '1,170p' test/responsive_pages_audit_test.dart
  ```

  Reuse its page-construction approach rather than inventing a second one. Pages needing provider overrides get the same fake pattern already used there.

  - [ ] **Step 3: Run the sweep and record real failures**

  Run: `cd Frontend && flutter test test/responsive_screen_audit_test.dart`

  For each failure: record the page, viewport, and the actual overflow in the audit doc, then fix the **layout**. Typical fixes, in order of preference:
  - Wrap a fixed-width child in `Flexible`/`Expanded`.
  - Replace a `Row` of chips with `Wrap`.
  - Give a text widget `maxLines` + `TextOverflow.ellipsis`, or let it wrap.
  - Replace a hardcoded height with intrinsic sizing.
  - Apply `NmContentWidth` with the right token for the page's content role.

  Forbidden: `ClipRect` to hide an overflow, removing an assertion, or shrinking a font to dodge the error.

  - [ ] **Step 4: Apply content tokens by role**

  For each page, apply the token matching its content role, per spec §4:
  - `ContentWidth.prose` — help, safety, privacy, settings, notifications, support.
  - `ContentWidth.form` — auth forms, registration wizard steps, partner preferences, search filters.
  - `ContentWidth.detail` — profile detail (done in Task 6).
  - `feed` (no wrapper) — discover, matches, search results, shortlist, profile views.

  Verify at 1440/1920/3440 that form fields do not stretch, via a test per feature group.

  - [ ] **Step 5: Run everything**

  ```bash
  cd Frontend && dart format lib test && flutter analyze --no-fatal-infos && flutter test
  ```
  Expected: all PASS, analysis clean.

  - [ ] **Step 6: Run the web release build**

  ```bash
  cd Frontend && flutter build web --release
  ```
  Expected: build succeeds. Record the output size. If it fails, fix it — a passing build is in the spec's acceptance criteria.

  - [ ] **Step 7: Commit per feature group**

  Commit in small groups (auth/onboarding, registration, settings/premium, search/filters), each with its own message. Example:

  ```bash
  cd /c/Users/PC/nenjam_matrimony_app
  git add Frontend/lib/features/authentication Frontend/lib/features/onboarding
  git commit -m "$(cat <<'MSG'
  fix(auth,onboarding): constrain forms on wide windows

  Applies the ContentWidth.form token so fields keep their measure instead
  of stretching across a desktop monitor, and fixes the overflows the
  viewport sweep found at <widths>.

  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  MSG
  )"
  ```

  - [ ] **Step 8: Commit the audit report**

  ```bash
  cd /c/Users/PC/nenjam_matrimony_app
  git add docs/superpowers/reports/2026-10-22-responsive-audit.md Frontend/test/responsive_screen_audit_test.dart
  git commit -m "$(cat <<'MSG'
  docs(responsive): per-page audit table and viewport sweep

  Records every page as inspected, changed, tested or unaudited, with the
  overflows found and how each was fixed. Pages not reached are named
  rather than silently claimed as covered.

  Browser-level verification is recorded as NOT PERFORMED: the Chrome
  automation tooling was unavailable, so real-browser resize, back/forward,
  zoom, focus and console checks are unverified.

  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  MSG
  )"
  ```

  ---

## Final verification (run before reporting completion)

  - [ ] `cd Frontend && dart format --set-exit-if-changed lib test` — formatted
  - [ ] `cd Frontend && flutter analyze --no-fatal-infos` — clean
  - [ ] `cd Frontend && flutter test` — all pass
  - [ ] `cd Frontend && flutter build web --release` — succeeds
  - [ ] Mobile regression suites unmodified: `git diff --stat main -- Frontend/test/responsive_audit_test.dart Frontend/test/responsive_pages_audit_test.dart Frontend/test/light_mode_only_test.dart Frontend/test/bottom_nav_clearance_test.dart` prints nothing
  - [ ] `git log --oneline` shows chat master-detail as its own commit
  - [ ] Audit table has no `unaudited` row left unexplained
  - [ ] Nothing pushed, merged, or deployed; no env vars changed

## Report must state

  - Changed files, grouped by task.
  - Viewports actually verified, and by which test.
  - Every existing assertion that changed, and why (notably `responsive_desktop_shell_test.dart`'s `probe.width == 960`).
  - **Browser verification: NOT PERFORMED** — Chrome automation unavailable. List the six unverified checks from spec §9.
  - Any page left unaudited, by name.
  - Confirmation that the chat URL `/chat-detail/:conversationId` is unchanged, and that `router_refresh_test.dart`'s push-deep-link assertions still pass.
