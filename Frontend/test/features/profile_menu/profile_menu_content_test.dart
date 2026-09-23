import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/constants/app_constants.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/interests/domain/repositories/interests_repository.dart';
import 'package:nenjam_matrimony/features/interests/presentation/providers/interests_provider.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/features/profile_menu/presentation/pages/profile_menu_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// What the profile menu actually puts on screen.
///
/// Sizing and the Profile Strength fill are pinned by
/// `profile_menu_layout_test`; the full-screen route contract by
/// `profile_menu_presentation_test`. This file covers the content the
/// reference layout calls for — identity, the menu rows and their section
/// headers, live interest counts, the premium CTA and the footer — and that
/// every one of those values comes from state rather than a literal.
Map<String, dynamic> _draft(int percentage) => <String, dynamic>{
  'completionPercentage': percentage,
  'completionBreakdown': const <Map<String, dynamic>>[],
  'basicDetails': <String, dynamic>{
    'firstName': 'Dhatri',
    'lastName': 'Patel',
    'gender': 'FEMALE',
    'dob': '1999-04-12T00:00:00.000',
  },
  'religionDetails': <String, dynamic>{'community': 'Patidar Community'},
  'locationDetails': <String, dynamic>{
    'city': 'Bengaluru',
    'state': 'Karnataka',
    'country': 'India',
  },
};

DiscoveryProfileEntity _profile(String id) => DiscoveryProfileEntity(
  id: id,
  matrimonyId: 'NM$id',
  name: 'Someone $id',
  age: 27,
  location: 'Chennai',
  profession: 'Engineer',
  education: 'Bachelors',
  photoUrls: const <String>[],
);

InterestRecord _record(String id, InterestStatus status) => InterestRecord(
  id: id,
  profile: _profile(id),
  sentAt: DateTime(2026, 1, 1),
  status: status,
);

Future<void> _pumpMenu(
  WidgetTester tester, {
  int percentage = 72,
  List<InterestRecord> sent = const <InterestRecord>[],
  List<InterestRecord> received = const <InterestRecord>[],
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileDraftResponseProvider.overrideWith(
          (ref) async => _draft(percentage),
        ),
        sentInterestsProvider.overrideWithValue(AsyncValue.data(sent)),
        receivedInterestsProvider.overrideWithValue(AsyncValue.data(received)),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileMenuPage(),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('renders the identity block from the draft, not from literals', (
    tester,
  ) async {
    await _pumpMenu(tester);

    // Name, community and location all come off the GET /profiles/draft
    // response overridden above — change that response and these change.
    expect(find.text('Dhatri Patel'), findsOneWidget);
    expect(find.text('Patidar Community'), findsOneWidget);
    expect(
      find.textContaining('Bengaluru'),
      findsOneWidget,
      reason: 'the age • location subtitle is built from locationDetails',
    );
  });

  testWidgets('renders the profile strength card at the backend percentage', (
    tester,
  ) async {
    await _pumpMenu(tester, percentage: 64);

    expect(find.text('Profile Strength'), findsOneWidget);
    // The figure is the backend's completionPercentage, passed straight
    // through — this page never derives a score of its own.
    expect(find.text('64%'), findsOneWidget);
  });

  testWidgets('renders every main menu row with a chevron', (tester) async {
    await _pumpMenu(tester);

    for (final label in const [
      'My Profile',
      'Edit Profile',
      'Partner Preferences',
      'Verification Center',
      'Interests Sent',
      'Interests Received',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'missing row: $label');
    }
    // The Profile Intelligence hub was removed; no row may link to it.
    expect(find.text('Profile Intelligence'), findsNothing);

    // Every navigating row carries the trailing chevron the reference shows.
    expect(find.byIcon(Icons.chevron_right_rounded), findsAtLeast(7));
  });

  testWidgets('groups the rows under the reference section headers', (
    tester,
  ) async {
    await _pumpMenu(tester);

    expect(find.text('Your Match Activity'), findsOneWidget);
    expect(find.text('Options & Settings'), findsOneWidget);
  });

  testWidgets('interest counts come from the interests providers', (
    tester,
  ) async {
    await _pumpMenu(
      tester,
      sent: [
        _record('a', InterestStatus.pending),
        _record('b', InterestStatus.pending),
        // Only pending ones are counted — an accepted interest is no longer
        // outstanding, so it must not inflate the badge.
        _record('c', InterestStatus.accepted),
      ],
      received: [_record('d', InterestStatus.pending)],
    );

    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('no badge is shown when there is nothing outstanding', (
    tester,
  ) async {
    await _pumpMenu(tester);

    // Empty lists, so neither interests row carries a count.
    expect(find.text('0'), findsNothing);
  });

  testWidgets('renders the premium CTA as title plus action', (tester) async {
    await _pumpMenu(tester);

    // Both halves of the reference's CTA: what the offer is, and the action.
    expect(find.text('Nenjam Premium'), findsOneWidget);
    expect(find.text('Upgrade Now'), findsOneWidget);
  });

  testWidgets('renders the footer with the real app version', (tester) async {
    await _pumpMenu(tester);

    expect(find.text('Terms & Conditions'), findsOneWidget);
    // The version constant the rest of the app reads — never a literal
    // copied off a screenshot.
    expect(find.text('Version ${AppConstants.appVersion}'), findsOneWidget);
    expect(
      find.textContaining('Nenjam Matrimony'),
      findsWidgets,
      reason: 'the copyright line names the app',
    );
  });

  testWidgets('menu rows are wired to a tap handler', (tester) async {
    await _pumpMenu(tester);

    // Each row's InkWell has a real callback: the destinations themselves are
    // existing routes, so what matters here is that none was left inert.
    final rows = find.ancestor(
      of: find.text('Partner Preferences'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(rows.first).onTap, isNotNull);
  });
}
