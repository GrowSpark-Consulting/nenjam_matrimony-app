Use the Stitch MCP server.

Open my existing Stitch project "Nenjam Matrimony".

Locate the screen named " nenjam Home Feed".

Read the existing Stitch design.

DO NOT redesign.

Implement this screen exactly as it appears in Stitch into my Flutter project.

══════════════════════════════════════

Target File

lib/features/home/presentation/pages/home_page.dart

Create reusable widgets inside

lib/features/home/presentation/widgets/

══════════════════════════════════════

The UI must match Stitch pixel-perfect.

Implement every section exactly.

Screen hierarchy:

• Custom AppBar
    - Nenjam Matrimony title
    - Search icon
    - Notification icon with badge

• New Today section
    - Horizontal avatar list
    - Story style circles
    - Name below each avatar
    - Smooth horizontal scrolling

• Featured Profile Card

The featured profile occupies around 80% of the viewport.

Include

- Rounded corners
- Full height image
- Gradient overlay
- Premium badge
- Verified badge
- Online indicator
- Name
- Age
- Location
- Profession
- Match percentage
- Like button
- Interested button
- Shortlist button
- View Profile button

All spacing must match Stitch exactly.

══════════════════════════════════════

After the featured card

Implement

Recently Joined

Horizontal cards exactly matching Stitch

Each card contains

Photo

Name

Age

Profession

Distance

Verified badge

Premium badge

══════════════════════════════════════

Next section

Second Featured Profile

Same UI

Same interactions

══════════════════════════════════════

Near You

Horizontal scroll cards

Exactly as Stitch

══════════════════════════════════════

Premium Members

Dark premium card

Premium badge

Gradient background

CTA button

══════════════════════════════════════

Bottom Navigation

Exactly as Stitch

Icons

Labels

Selected state

Animations

══════════════════════════════════════

Scrolling

Use CustomScrollView

SliverAppBar if present in Stitch

Smooth scrolling

Pull To Refresh

Infinite scroll ready

Pagination ready

══════════════════════════════════════

Animations

Match Stitch exactly.

Use

FadeTransition

SlideTransition

Hero

AnimatedContainer

AnimatedOpacity

Implicit animations

══════════════════════════════════════

Flutter Architecture

Clean Architecture

Riverpod

GoRouter

Material 3

ThemeData

ColorScheme

Responsive

No hardcoded sizes

Use

MediaQuery

LayoutBuilder

Expanded

Flexible

AspectRatio

══════════════════════════════════════

Performance

const constructors

CachedNetworkImage

RepaintBoundary

Minimal rebuilds

Lazy loading

KeepAlive

══════════════════════════════════════

Code Quality

Follow Effective Dart

No duplicate widgets

Create reusable components

ProfileCard

StoryAvatar

SectionHeader

ActionButton

HorizontalProfileList

PremiumCard

BottomNavItem

══════════════════════════════════════

Output

Generate only

home_page.dart

home_provider.dart

All reusable widgets

Necessary models

Theme integration

Navigation

flutter analyze should produce zero warnings or errors.

══════════════════════════════════════

IMPORTANT

Do NOT redesign.

Do NOT change colors.

Do NOT change spacing.

Do NOT change typography.

Do NOT simplify the layout.

Read every measurement from Stitch.

Implement pixel-perfect Flutter code.

Stop after completing ONLY the Home Feed page.

Before writing any Flutter code:

1. Read the complete Stitch design.
2. Measure every spacing, radius, font size, elevation, and padding.
3. Create a component plan.
4. Then implement the UI.

If any information is missing from Stitch, ask me before making assumptions.

Do not hallucinate the design.








# nenjam_matrimony

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
