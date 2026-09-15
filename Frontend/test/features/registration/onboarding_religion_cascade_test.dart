import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/location/domain/models/location_models.dart';
import 'package:nenjam_matrimony/features/location/presentation/providers/location_providers.dart';
import 'package:nenjam_matrimony/features/location/presentation/widgets/location_picker_field.dart';
import 'package:nenjam_matrimony/features/religion/data/religion_repository.dart';
import 'package:nenjam_matrimony/features/religion/presentation/providers/religion_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_religion_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// Religion → Community, the second reference-data cascade.
///
/// These pin the same properties the country → state → city tests do, because
/// the failure modes are the same ones: a stale child surviving a parent
/// change, a slow reply overwriting a newer selection, and an empty list
/// looking identical to a failed request.

/// Serves canned lists and records what was asked for, so a test can assert
/// that changing a parent did not re-request the same child twice.
class _StubReligionRepository implements ReligionRepository {
  _StubReligionRepository({
    Map<String, List<LocationOption>>? communities,
    this.communityDelay = const {},
  }) : byReligion = communities ?? const {};

  static const hindu = LocationOption(code: 'HINDU', label: 'Hindu');
  static const jain = LocationOption(code: 'JAIN', label: 'Jain');
  static const interReligion =
      LocationOption(code: 'INTER-RELIGION', label: 'Inter-Religion');

  /// Keyed by religion code. Named `byReligion` rather than `communities`
  /// because the interface method below already owns that name.
  final Map<String, List<LocationOption>> byReligion;

  /// Per-religion delay, for the stale-response test.
  final Map<String, Duration> communityDelay;

  final List<String> requested = [];
  Object? religionsError;
  Object? communitiesError;

  @override
  Future<List<LocationOption>> religions({dynamic cancelToken}) async {
    requested.add('religions');
    if (religionsError != null) throw religionsError!;
    return const [hindu, interReligion, jain];
  }

  @override
  Future<List<LocationOption>> communities(
    String religionCode, {
    dynamic cancelToken,
  }) async {
    requested.add('communities:$religionCode');
    final delay = communityDelay[religionCode];
    if (delay != null) await Future<void>.delayed(delay);
    if (communitiesError != null) throw communitiesError!;
    return byReligion[religionCode] ?? const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _hinduCommunities = [
  LocationOption(code: 'HINDU-IYER', label: 'Iyer', parentCode: 'HINDU'),
  LocationOption(code: 'HINDU-NADAR', label: 'Nadar', parentCode: 'HINDU'),
  LocationOption(code: 'HINDU-TAMIL', label: 'Tamil', parentCode: 'HINDU'),
];
const _jainCommunities = [
  LocationOption(code: 'JAIN-DIGAMBAR', label: 'Digambar', parentCode: 'JAIN'),
  // Deliberately shares a label with a Hindu community: the codes differ, so
  // carrying the answer across a religion change would send the server a pair
  // it rejects.
  LocationOption(code: 'JAIN-TAMIL', label: 'Tamil', parentCode: 'JAIN'),
];

void main() {
  GoRouter religionRouter() => GoRouter(
        initialLocation: RouteNames.onboardingReligion,
        routes: [
          GoRoute(
            path: RouteNames.onboardingReligion,
            builder: (_, _) => const OnboardingReligionPage(),
          ),
          GoRoute(
            path: RouteNames.onboardingContact,
            builder: (_, _) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: RouteNames.onboardingNameDob,
            builder: (_, _) => const SizedBox.shrink(),
          ),
        ],
      );

  Future<ProviderContainer> pumpReligionStep(
    WidgetTester tester,
    _StubReligionRepository repository, {
    ProfileDraft? draft,
  }) async {
    useTallSurface(tester);
    final container = ProviderContainer(
      overrides: [
        religionRepositoryProvider.overrideWithValue(repository),
        // The country field on this screen is not what these tests are about.
        countriesProvider.overrideWith((ref) async => const <LocationOption>[]),
        if (draft != null) registrationProvider.overrideWith(() => _SeededDraft(draft)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container, religionRouter()));
    await tester.pumpAndSettle();
    return container;
  }

  /// Opens the picker with [label] and taps [option] in the sheet.
  Future<void> pick(WidgetTester tester, String label, String option) async {
    final picker = find.ancestor(
      of: find.text(label),
      matching: find.byType(LocationPickerField),
    );
    final target = find.descendant(of: picker, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, option).last);
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester, String label) async {
    final picker = find.ancestor(
      of: find.text(label),
      matching: find.byType(LocationPickerField),
    );
    final target = find.descendant(of: picker, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  // ─── Religion ─────────────────────────────────────────────────────────

  testWidgets('religions load from the API, not a hardcoded list', (tester) async {
    final repo = _StubReligionRepository();
    await pumpReligionStep(tester, repo);

    await openPicker(tester, 'Religion *');
    expect(find.widgetWithText(ListTile, 'Hindu'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Jain'), findsOneWidget);
    expect(repo.requested, contains('religions'));
  });

  testWidgets('a failed religion request offers a retry rather than an empty list',
      (tester) async {
    final repo = _StubReligionRepository()..religionsError = Exception('boom');
    await pumpReligionStep(tester, repo);

    // An empty dropdown would look identical to "there are no religions".
    expect(find.text('Could not load'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  // ─── Community depends on religion ────────────────────────────────────

  testWidgets('community is disabled until a religion is chosen', (tester) async {
    final repo = _StubReligionRepository(communities: {'HINDU': _hinduCommunities});
    await pumpReligionStep(tester, repo);

    // Nothing to list yet, so no request is made for it either.
    expect(repo.requested.where((r) => r.startsWith('communities:')), isEmpty);

    await openPicker(tester, 'Community *');
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('choosing a religion loads exactly that religion\'s communities',
      (tester) async {
    final repo = _StubReligionRepository(
      communities: {'HINDU': _hinduCommunities, 'JAIN': _jainCommunities},
    );
    await pumpReligionStep(tester, repo);

    await pick(tester, 'Religion *', 'Hindu');

    expect(repo.requested, contains('communities:HINDU'));
    expect(repo.requested, isNot(contains('communities:JAIN')));

    await openPicker(tester, 'Community *');
    expect(find.widgetWithText(ListTile, 'Iyer'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Digambar'), findsNothing);
  });

  testWidgets('changing religion clears the chosen community', (tester) async {
    final repo = _StubReligionRepository(
      communities: {'HINDU': _hinduCommunities, 'JAIN': _jainCommunities},
    );
    final container = await pumpReligionStep(tester, repo);

    await pick(tester, 'Religion *', 'Hindu');
    await pick(tester, 'Community *', 'Tamil');
    expect(find.text('Tamil'), findsOneWidget);

    // Both religions offer a community labelled "Tamil", but they are
    // different rows (HINDU-TAMIL vs JAIN-TAMIL). Carrying the answer over
    // would send the server a pair it rejects, so it must be cleared outright
    // even though the label would still have been valid.
    await pick(tester, 'Religion *', 'Jain');

    // The field is empty again, so the step is incomplete and Continue will
    // not save — which is the correct consequence of clearing a required
    // field, and why this asserts on the form rather than on the draft.
    expect(find.text('Tamil'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      container.read(registrationProvider).religionDetails.religionCode,
      isEmpty,
      reason: 'an incomplete step must not persist a half-answered cascade',
    );

    // Answering the new religion's community completes it again.
    await pick(tester, 'Community *', 'Digambar');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final religion = container.read(registrationProvider).religionDetails;
    expect(religion.religionCode, 'JAIN');
    expect(religion.communityCode, 'JAIN-DIGAMBAR');
  });

  testWidgets('never shows a community from the previous religion', (tester) async {
    final repo = _StubReligionRepository(
      communities: {'HINDU': _hinduCommunities, 'JAIN': _jainCommunities},
    );
    await pumpReligionStep(tester, repo);

    await pick(tester, 'Religion *', 'Hindu');
    await pick(tester, 'Religion *', 'Jain');

    await openPicker(tester, 'Community *');
    expect(find.widgetWithText(ListTile, 'Digambar'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Iyer'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Nadar'), findsNothing);
  });

  testWidgets('a religion with no communities is an empty list, not an error',
      (tester) async {
    final repo = _StubReligionRepository(communities: const {});
    await pumpReligionStep(tester, repo);

    await pick(tester, 'Religion *', 'Inter-Religion');

    expect(find.text('Could not load'), findsNothing);
    await openPicker(tester, 'Community *');
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('a failed community request offers a retry', (tester) async {
    final repo = _StubReligionRepository(communities: {'HINDU': _hinduCommunities});
    await pumpReligionStep(tester, repo);
    repo.communitiesError = Exception('boom');

    await pick(tester, 'Religion *', 'Hindu');

    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('re-picking the same religion does not re-request its communities',
      (tester) async {
    final repo = _StubReligionRepository(communities: {'HINDU': _hinduCommunities});
    await pumpReligionStep(tester, repo);

    await pick(tester, 'Religion *', 'Hindu');
    await pick(tester, 'Religion *', 'Hindu');

    expect(
      repo.requested.where((r) => r == 'communities:HINDU').length,
      1,
      reason: 'the cached list should be reused',
    );
  });

  // ─── Stale responses ──────────────────────────────────────────────────

  testWidgets('a slow reply for the old religion cannot overwrite the new one',
      (tester) async {
    // Hindu is slow, Jain is instant. Selecting Hindu then immediately Jain
    // means Hindu's response lands LAST — and must be ignored.
    final repo = _StubReligionRepository(
      communities: {'HINDU': _hinduCommunities, 'JAIN': _jainCommunities},
      communityDelay: const {'HINDU': Duration(seconds: 2)},
    );
    await pumpReligionStep(tester, repo);

    await tester.tap(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('Religion *'),
              matching: find.byType(LocationPickerField),
            ),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Hindu').last);
    await tester.pump(); // Hindu's request is now in flight, unresolved.

    await pick(tester, 'Religion *', 'Jain');

    // Let Hindu's slow response arrive.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await openPicker(tester, 'Community *');
    expect(find.widgetWithText(ListTile, 'Digambar'), findsOneWidget);
    expect(
      find.widgetWithText(ListTile, 'Iyer'),
      findsNothing,
      reason: 'the late Hindu response must not replace the Jain list',
    );
  });

  // ─── Legacy drafts ────────────────────────────────────────────────────

  testWidgets('a draft with labels but no codes keeps showing its answers',
      (tester) async {
    // Every profile written before the religion master data existed looks
    // exactly like this: free text, no codes.
    final repo = _StubReligionRepository(communities: {'HINDU': _hinduCommunities});
    await pumpReligionStep(
      tester,
      repo,
      draft: const ProfileDraft(
        religionDetails: ReligionDetails(religion: 'Hindu', community: 'Iyer'),
      ),
    );

    // Matched against the API's own list, so the codes are recovered.
    expect(find.text('Hindu'), findsOneWidget);
    expect(find.text('Iyer'), findsOneWidget);
    expect(repo.requested, contains('communities:HINDU'));
  });

  testWidgets('a religion the API does not offer is kept, not blanked',
      (tester) async {
    final repo = _StubReligionRepository(communities: const {});
    await pumpReligionStep(
      tester,
      repo,
      draft: const ProfileDraft(
        religionDetails: ReligionDetails(religion: 'Zoroastrian'),
      ),
    );

    // Shown as the member's own answer rather than an empty field — nothing
    // is invented, and the value survives until they replace it.
    expect(find.text('Zoroastrian'), findsOneWidget);
  });

  // ─── Submission ───────────────────────────────────────────────────────

  testWidgets('saves both the codes and the labels', (tester) async {
    final repo = _StubReligionRepository(communities: {'HINDU': _hinduCommunities});
    final container = await pumpReligionStep(tester, repo);

    await pick(tester, 'Religion *', 'Hindu');
    await pick(tester, 'Community *', 'Nadar');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final religion = container.read(registrationProvider).religionDetails;
    expect(religion.religion, 'Hindu');
    expect(religion.religionCode, 'HINDU');
    expect(religion.community, 'Nadar');
    expect(religion.communityCode, 'HINDU-NADAR');
  });

  testWidgets('the draft payload carries the codes', (tester) async {
    final repo = _StubReligionRepository(communities: {'HINDU': _hinduCommunities});
    final container = await pumpReligionStep(tester, repo);

    await pick(tester, 'Religion *', 'Hindu');
    await pick(tester, 'Community *', 'Iyer');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final json = container.read(registrationProvider).religionDetails.toJson();
    expect(json['religionCode'], 'HINDU');
    expect(json['communityCode'], 'HINDU-IYER');
    // The free-text fields still travel too — they remain the source of truth
    // for everything that already reads them.
    expect(json['religion'], 'Hindu');
    expect(json['community'], 'Iyer');
  });

  testWidgets('sub-caste is untouched by a religion change', (tester) async {
    // It is asked two steps later as free text, has no master data behind it,
    // and is not a child of community in any dataset this project holds.
    final repo = _StubReligionRepository(
      communities: {'HINDU': _hinduCommunities, 'JAIN': _jainCommunities},
    );
    final container = await pumpReligionStep(
      tester,
      repo,
      draft: const ProfileDraft(
        religionDetails: ReligionDetails(subCaste: 'Vanniyar'),
      ),
    );

    await pick(tester, 'Religion *', 'Hindu');
    await pick(tester, 'Religion *', 'Jain');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(container.read(registrationProvider).religionDetails.subCaste, 'Vanniyar');
  });
}

/// Seeds the registration draft so a test can start from an existing profile.
class _SeededDraft extends RegistrationNotifier {
  _SeededDraft(this._seed);

  final ProfileDraft _seed;

  @override
  ProfileDraft build() {
    super.build();
    return _seed;
  }
}
