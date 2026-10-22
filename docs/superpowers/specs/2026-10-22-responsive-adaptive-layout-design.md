# Responsive & Adaptive Layout System — Design

**Date:** 2026-10-22
**Branch:** `feat/responsive-adaptive-layout`
**Scope:** Flutter client (`Frontend/`) only. No backend, auth, or API contract changes.

---

## 1. Problem

The app already has partial web-readiness: `ResponsiveUtils` with breakpoints,
`NmContentConstraint`, `NmAppFrame`, a 96px desktop nav rail, and three
responsive test suites covering 320–1920.

One structural decision blocks a real desktop experience. `NmAppFrame`, installed
in `MaterialApp.builder` (`lib/main.dart`), caps the **entire app** at
`maxContentWidth + navRailWidth` (≈1056px) and then overrides the inner
`MediaQuery.size` to report that capped width:

```dart
MediaQuery(data: media.copyWith(size: Size(maxWidth, media.size.height)), ...)
```

Consequences:

- On 1440/1920/2560/3440 displays the app is a centered ~1056px column — a
  letterboxed mobile app, not a desktop layout.
- Because the inner `MediaQuery` reports ≤1056px, **no descendant can ever
  observe a width above ~1056px**. Multi-column discovery grids, master-detail
  chat, and two-column profile details are structurally impossible while the
  frame stands.
- `test/responsive_desktop_shell_test.dart` asserts the clamp
  (`expect(probe.width, 960)` at 1920px), so the test suite currently locks in
  the behavior that must change.

The task is therefore not "add responsiveness" but **replace a global
width-clamp with a constraint-driven adaptive layout system**, then build real
desktop layouts for the highest-value surfaces.

## 2. Approved decisions

| Decision | Choice |
|---|---|
| Global shell | **Full-width app shell with per-surface max-widths** (remove the global clamp) |
| Desktop navigation | **Responsive rail**: 96px icon rail at 900–1199, ~240px extended rail at ≥1200 |
| Migration strategy | `ResponsiveUtils` retained as a deprecated compatibility facade; incremental per-surface migration |
| Global top bar | **None.** Each page's existing `AppBar` remains the top-bar mechanism |
| Secondary destinations | Stay on current drill-down paths (navigation-IA change is out of scope) |

## 3. Window-class model

Replaces the device-name model (`DeviceType {phone, tablet, desktop}`), which
reads the whole window and is therefore wrong inside a detail pane or an
embedded web view.

| Window class | Width |
|---|---|
| `compact` | < 600 |
| `medium` | 600–899 |
| `expanded` | 900–1199 |
| `large` | ≥ 1200 |

Two entry points, with a strict rule about which to use:

- **`WindowClass.of(context)`** — MediaQuery-based. Permitted **only** for
  shell-level decisions (which navigation affordance to show). This is the one
  place where reading the window is correct.
- **`WindowClass.fromWidth(constraints.maxWidth)`** — fed by a `LayoutBuilder`.
  Required for **every** surface-level decision (grid columns, one-vs-two
  column, card internals). A surface inside a 400px pane on a 1920px monitor
  must report `compact`.

**Non-negotiable:** a blanket `DeviceType` → `WindowClass.of(context)` swap would
preserve the original defect under a new name. Surfaces whose layout depends on
local width get a real `LayoutBuilder`.

## 4. Per-surface max-width tokens

Named by **content role**, not device, so there is one obvious choice per
surface. All are **maximum** constraints — every surface still shrinks
gracefully on smaller screens.

| Token | Max width | Used by |
|---|---|---|
| `prose` | ~680 | Text-heavy pages, settings, help, safety, privacy |
| `form` | ~560 single-column / ~900 two-column | Registration wizard, preferences, auth forms |
| `feed` | unbounded (grid fills; column count and card width adapt) | Discover, matches, search results |
| `detail` | ~1200 | Profile detail two-column |

Ultrawide protection moves from one global clamp to these per-surface
constraints: content never stretches edge-to-edge at 3440px, while grids and
master-detail can genuinely use the space.

### 4.1 Usable content width derivation (required rule)

Usable content width must **never** be computed from the full window. The
derivation order is:

```
window width
  − navigation width (0 compact/medium, 96 expanded, ~240 large)
  − page padding (per ResponsiveUtils.pagePadding / AppSpacing)
  − inter-item spacing (grids only)
  = usable content width
      → then clamp by the surface's max-width token
```

In practice this is enforced structurally: the rail is a sibling of the content
in a `Row`, so the content's `LayoutBuilder` already receives the post-rail
width. Surfaces must take their width from that `LayoutBuilder`'s constraints,
never from `MediaQuery.sizeOf(context).width`.

Worked check at the tightest rail case (900px, safeguard 4):
`900 − 96 rail − (2 × 32 page padding) = 740px` usable — comfortable for the
`form` token (560) and for a 2-column grid.

## 5. Shell and navigation

| Window class | Navigation |
|---|---|
| `compact` (<600) | Floating bottom pill — **unchanged** |
| `medium` (600–899) | Floating bottom pill — retained |
| `expanded` (900–1199) | 96px icon rail |
| `large` (≥1200) | ~240px extended rail, icon + text label |

The rail threshold moves from 1024 (`isDesktop`) to **900** (`expanded`), so a
1024×768 tablet in landscape and a small laptop window both get the rail. This
is the one behavior change affecting existing tablet-landscape users, and is
deliberate.

Safeguards:

1. **Preserve navigation behavior.** Reuse `_NavItem`, unread badges,
   accessibility labels (incl. the "Inbox, 3 unread messages" announcement), and
   `goBranch(index, initialLocation: index == currentIndex)` tab logic. Change
   presentation, not routing semantics.
2. **Explicit rail sizing.** ~240px extended rail; icons and labels consistently
   aligned; long/localized labels must not overflow.
3. **Preserve keys.** Keep `ValueKey('desktop-nav-rail')`; add a distinct key for
   the extended variant.
4. **Protect tablet layouts.** Verify post-rail content width at 900 (see §4.1).
5. **Preserve compact behavior.** Floating pill, its `SafeArea`, `extendBody`,
   and branch switching unchanged below 900.
6. **No new global top bar.** No duplicated page titles or actions.

`_DesktopRail` becomes `NmNavigationRail` with an `extended` flag.

### 5.1 `NmAppFrame` removal

Verified: `NmAppFrame` is the **sole** `MaterialApp.builder` wrapper, and its
only responsibilities are (a) the width clamp, (b) the inner `MediaQuery`
override, and (c) a `ColoredBox(AppColors.background)` filling the letterbox
gutter. Responsibility (c) exists only to fill the gutter the clamp creates —
with no clamp there is no gutter, so it needs no rehoming. No alignment or
inherited styling is lost. The widget is removed from `builder`;
`NmContentConstraint` remains and is superseded in use by the §4 tokens.

## 6. Priority surfaces

### 6.1 Discover grid (`feed`)

Single-column feed becomes a responsive grid. **Column count is derived from the
actual local width after padding and spacing** (§4.1) against a nominal target
card width — not a breakpoint→count lookup table — so intermediate widths and
continuous browser resizing behave correctly.

Both **column count and card width are capped**, so a very wide pane does not
produce a few absurdly wide cards. Existing profile-card composition and photo
`AspectRatio` are preserved; only arrangement changes.

### 6.2 Chat master-detail (own commit)

At `expanded`/`large`: conversation list in a ~360px pane + chat in the
remainder. Below that: unchanged two-route push navigation.

**The URL remains authoritative.**

| Route | Desktop (≥900) | Mobile (<900) |
|---|---|---|
| `/inbox` | List + empty detail pane | List |
| `/inbox/:id` | List + selected conversation | Full-screen chat |

Selecting a conversation **navigates** (the URL changes); it does not push a new
screen at desktop widths. Requirements:

1. Selection updates URL and browser history correctly.
2. Refreshing `/inbox/:id` restores the selected conversation.
3. Back/forward restore the correct selection without duplicate routes or stale
   detail state.
4. Crossing the 900px boundary does not needlessly lose selection or draft state.
5. Invalid / unavailable / unauthorized conversation IDs produce the **existing**
   error behavior, not a broken master-detail layout.
6. List and chat panes scroll independently, with no nested-scroll conflicts.

This is the most intricate piece of the task and the likeliest source of
regressions. It ships as **its own commit**, with route, browser-history,
resize-transition, and authorization regression tests. It is **not** merged into
the shell change.

### 6.3 Profile detail (`detail`, ~1200)

At `large`: photo gallery + key facts in a left column; detail sections
(family, lifestyle, horoscope, preferences, verification, timeline) in a right
column; max 1200px, centered beyond. At `expanded` and below: unchanged single
column.

**Reading and keyboard order must stay logical** — visual two-column placement
must not produce confusing focus traversal or a scrambled semantics tree.

### 6.4 Forms and text-heavy pages

Apply `prose`/`form` tokens. Single-column and narrow even at 3440px: wide
screens give them margin, not stretched fields. Mostly applying a constraint,
not restructuring.

## 7. Boundary and resize behavior

Required explicit behavior (no ambiguity at the seams):

- Classification uses **half-open intervals**: `[0,600)` compact,
  `[600,900)` medium, `[900,1200)` expanded, `[1200,∞)` large. So 599→compact,
  600→medium, 899→medium, 900→expanded, 1199→expanded, 1200→large.
- **Crossing a boundary rebuilds the affected subtree only.** Window-class
  computation is cheap and derived; no resize listeners, no stored state, no
  animation on class change.
- **Continuous resizing** must not accumulate state or drop frames into an
  invalid layout. Grid column counts recompute from constraints each build.
- **Resize across 900 with a chat conversation open:** the URL is the source of
  truth, so the selected conversation survives. `/inbox/:id` shrinking below 900
  becomes the full-screen chat for that id; widening above 900 becomes
  list + that id selected. No conversation loss in either direction.
- **Short viewports** (e.g. 900×600) must keep the rail usable and the page
  scrollable without overflow.

## 8. Testing

Shared `test/support/responsive_harness.dart`: pump-at-size helpers, the brief's
viewport matrix as named constants, a boundary-pair matrix
(599/600, 899/900, 1023/1024, 1199/1200), and an overflow guard asserting on
`RenderFlex` overflow via `tester.takeException()` plus explicit bounds checks.

Shell matrix: 599, 600, 899, 900, 1023, 1024, 1199, 1200, 1440, 1920 — plus
**900×short-height**. Assert navigation transitions, badge semantics, branch
switching, and usable content width.

Rules:

- **No suppressing genuine overflow.** Real overflow is fixed in the layout, not
  silenced, and no assertions are weakened to make a test pass.
- Existing suites are **updated to the intended behavior, not rewritten to
  pass**. Specifically `responsive_desktop_shell_test.dart` asserts
  `probe.width == 960` at 1920px, which encoded the clamp; it becomes an
  assertion that content fills the window minus the rail, with per-surface
  tokens verified separately. Every changed assertion is named and justified in
  the final report.
- Mobile regression suites stay **unchanged**: `responsive_audit_test.dart`,
  `responsive_pages_audit_test.dart`, `light_mode_only_test.dart`,
  `bottom_nav_clearance_test.dart`. They are the proof mobile did not regress.
- Legacy `ResponsiveUtils` methods get tests so the facade's behavior cannot
  silently change during migration.

## 9. Verification — and its limits

**Will be run:** `flutter analyze --no-fatal-infos`, `dart format`, targeted
test files, and `flutter build web --release`.

**Browser verification: NOT PERFORMED.** The Chrome automation tooling
disconnected during this session and is unavailable. The following are therefore
**not verified** and must not be reported as passing:

- real-browser continuous resize behavior
- actual browser back/forward history
- browser zoom at 80% / 100% / 125% / 150%
- keyboard focus and visible focus states in a real browser
- console errors and failed asset loads
- real embedded-web-view behavior

Widget and router tests cover the logic (including simulated resize and
router-level history), but cannot substitute for the above.

Per-surface `ResponsiveUtils` migration is incremental; the facade is removed
only after all meaningful callers have migrated and tests confirm it is safe.

## 10. Scope of the 55 pages

The shared system (§3–§5) benefits all 55 pages automatically. Beyond that:

1. Priority surfaces (§6) get real desktop layouts.
2. Remaining pages are audited and constrained with the right token, prioritized
   per the brief: auth/onboarding, registration wizard, filters/search,
   settings/premium.
3. Pages with no issues get a token and a test, **not** a redesign.

The final report will state explicitly, per page: **inspected / changed /
tested / unaudited**. Pages not reached are named as unaudited, never silently
claimed.

## 11. Commits and safety

Dedicated branch `feat/responsive-adaptive-layout` off a clean tree.
Incremental commits:

1. Window-class system + tokens + `NmAppFrame` removal
2. Adaptive navigation rail (icon + extended)
3. Discover grid + profile detail two-column
4. Chat master-detail (**isolated**)
5. Remaining screen audit + constraints
6. Responsive test suite

**No push, no merge, no deploy, no environment-variable changes** without
explicit authorization.

## 12. Acceptance criteria

Section 1:
- [ ] True viewport dimensions preserved (no global `MediaQuery` override)
- [ ] All four window classes have boundary tests
- [ ] Local-width classification works inside narrow panes on large screens
- [ ] Existing `ResponsiveUtils` callers still compile
- [ ] `NmAppFrame` no longer globally clamps the app
- [ ] Per-surface constraints work at narrow and ultrawide widths

Section 2:
- [ ] Shell tested at 599/600/899/900/1023/1024/1199/1200/1440/1920 + 900×short
- [ ] Badge semantics, branch switching, compact pill behavior unchanged
- [ ] Post-rail content width verified at 900

Section 3:
- [ ] Discover grid tested across intermediate widths and continuous resizing
- [ ] Chat deep links, refresh, back/forward, resize, and authorization pass
- [ ] Profile detail readable at the 1200px cap and in narrower panes;
      keyboard/reading order logical
- [ ] Forms constrained at 1440 / 1920 / 3440
- [ ] Existing mobile tests green

Overall:
- [ ] `flutter analyze --no-fatal-infos` clean
- [ ] Relevant tests pass
- [ ] `flutter build web --release` passes
- [ ] Browser verification documented as not performed
- [ ] Per-page audit table published
