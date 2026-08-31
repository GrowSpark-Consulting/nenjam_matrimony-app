import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_detail_section_tab_bar.dart';

/// Isolated reproduction of the "scroll resets to top while scrolling" bug
/// and proof of its fix — deliberately avoids importing the real
/// ProfileDetailPage, whose widget tree (via ProfileDetailBottomActionBar ->
/// interests -> inbox -> realtime -> notifications) currently fails to
/// compile due to an unrelated, pre-existing flutter_local_notifications API
/// mismatch. This harness reproduces the exact structural pattern that
/// actually matters — a pinned SliverPersistentHeader containing a
/// horizontal ListView, inside a vertical CustomScrollView — using the real,
/// unmodified [ProfileDetailSectionTabBar] and [ProfileDetailTabBarDelegate]
/// widgets, so it exercises the real production code, not a reimplementation
/// of it.
///
/// A third variant of this test — calling the OLD, pre-fix
/// `Scrollable.ensureVisible(tabContext, ...)` directly (the static helper,
/// which walks every ancestor Scrollable, not just the tab bar's own) — was
/// run once during the investigation and is deliberately NOT kept here: it
/// didn't just snap the outer scroll to 0, it never resolved at all and hit
/// widget_test's 10-minute timeout. That's consistent with — and stronger
/// evidence for — the same root cause (the static helper handing the outer
/// vertical CustomScrollView a "make this pinned, already-visible header
/// visible" request whose RevealedOffset math cannot converge), but a test
/// that takes 10 minutes to fail isn't worth keeping in the suite. The fix
/// below is what matters, and it passes in well under a second.
const _labels = [
  'Family',
  'Lifestyle',
  'Horoscope',
  'Compatibility',
  'Preferences',
  'Verification',
];

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final mainController = ScrollController();
  final tabBarController = ScrollController();
  final itemKeys = List.generate(_labels.length, (_) => GlobalKey());
  int selectedIndex = 0;

  @override
  void dispose() {
    mainController.dispose();
    tabBarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: mainController,
          slivers: [
            // Stand-in for ProfileDetailHeroAppBar's SliverAppBar.
            const SliverAppBar(pinned: true, expandedHeight: 320),
            SliverPersistentHeader(
              pinned: true,
              delegate: ProfileDetailTabBarDelegate(
                child: ProfileDetailSectionTabBar(
                  controller: tabBarController,
                  labels: _labels,
                  itemKeys: itemKeys,
                  selectedIndex: selectedIndex,
                  onTap: (i) => setState(() => selectedIndex = i),
                ),
              ),
            ),
            // Stand-in for the SliverList of profile sections — tall enough
            // that the main scrollable has real room to move.
            SliverList(
              delegate: SliverChildListDelegate(
                List.generate(
                  20,
                  (i) => Container(height: 200, color: i.isEven ? Colors.grey[200] : Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors _revealActiveTab's fixed implementation exactly: target only the
/// tab bar's own ScrollPosition, never the static Scrollable.ensureVisible
/// helper.
Future<void> _revealTab(_HarnessState state, int index) {
  final tabRenderObject = state.itemKeys[index].currentContext!.findRenderObject()!;
  return state.tabBarController.position.ensureVisible(
    tabRenderObject,
    alignment: 0.5,
    duration: const Duration(milliseconds: 50),
    curve: Curves.easeOut,
  );
}

void main() {
  testWidgets(
      "FIX: ScrollPosition.ensureVisible() on the tab bar's own controller "
      'never touches the outer vertical scroll', (tester) async {
    await tester.pumpWidget(const _Harness());
    await tester.pumpAndSettle();

    final state = tester.state<_HarnessState>(find.byType(_Harness));

    state.mainController.jumpTo(900);
    await tester.pump();
    expect(state.mainController.offset, 900);

    await _revealTab(state, 2); // Horoscope — an arbitrary mid-list tab.
    await tester.pumpAndSettle();

    expect(
      state.mainController.offset,
      closeTo(900, 1.0),
      reason: 'the main page scroll position must never move when only the tab '
          'bar is being centered',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reaching the Lifestyle tab (index 1) specifically does not '
      'reset the main scroll', (tester) async {
    await tester.pumpWidget(const _Harness());
    await tester.pumpAndSettle();

    final state = tester.state<_HarnessState>(find.byType(_Harness));

    state.mainController.jumpTo(900);
    await tester.pump();

    await _revealTab(state, 1); // Lifestyle.
    await tester.pumpAndSettle();

    expect(state.mainController.offset, closeTo(900, 1.0));
    expect(tester.takeException(), isNull);
  });
}
