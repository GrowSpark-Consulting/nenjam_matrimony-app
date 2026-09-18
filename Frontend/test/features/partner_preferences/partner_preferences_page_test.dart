import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nenjam_matrimony/core/widgets/buttons/primary_button.dart';
import 'package:nenjam_matrimony/features/partner_preferences/domain/repositories/partner_preferences_repository.dart';
import 'package:nenjam_matrimony/features/partner_preferences/presentation/pages/partner_preferences_page.dart';
import 'package:nenjam_matrimony/features/partner_preferences/presentation/providers/partner_preferences_provider.dart';
import 'package:nenjam_matrimony/features/partner_preferences/presentation/widgets/preference_row.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Widget-level coverage for [PartnerPreferencesPage]'s backend wiring:
/// loading, populating the form from `GET /discover/preferences`, the Save
/// button's disabled-until-loaded gate, and the Save action itself calling
/// `updatePreferences`. Request-shape and parsing details are covered by
/// partner_preferences_repository_test.dart / _provider_test.dart, so this
/// file does not repeat them.
void main() {
  group('PartnerPreferencesPage', () {
    testWidgets('shows a loading indicator before the backend responds',
        (tester) async {
      final repo = _FakeRepository(loaded: const PartnerPreference());
      // Deliberately no pump beyond pumpWidget's own first frame — the
      // repository's Future has had no chance to resolve yet, so this is
      // the true "request in flight" state.
      await tester.pumpWidget(_app(repository: repo));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button =
          tester.widget<NmPrimaryButton>(find.byType(NmPrimaryButton));
      expect(button.onPressed, isNull, reason: 'not loaded yet');
    });

    testWidgets('populates the form from the backend once loaded, and '
        'enables Save', (tester) async {
      final repo = _FakeRepository(
        loaded: const PartnerPreference(preferredAgeRange: '26-30'),
      );
      await tester.pumpWidget(_app(repository: repo));
      await tester.pumpAndSettle();

      final l10n = _l10nOf(tester);
      expect(
        _rowValue(tester, l10n.registrationPrefAgeLabel),
        '26-30',
      );
      expect(_saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('tapping Save calls updatePreferences and shows the saved '
        'snackbar', (tester) async {
      final repo = _FakeRepository(
        loaded: const PartnerPreference(religionPref: 'Hindu'),
      );
      await tester.pumpWidget(_app(repository: repo));
      await tester.pumpAndSettle();

      final l10n = _l10nOf(tester);
      await tester.tap(find.widgetWithText(NmPrimaryButton, l10n.partnerPrefSaveButton));
      await tester.pumpAndSettle();

      expect(repo.updateCalls, 1);
      expect(repo.updateRequests.single.religionPref, 'Hindu');
      expect(find.text('Partner preferences saved'), findsOneWidget);
    });

    testWidgets('a load failure shows an error state with a working retry',
        (tester) async {
      var fail = true;
      final repo = _FakeRepository(
        loaded: const PartnerPreference(preferredAgeRange: '30-35'),
        getPreferencesOverride: () async {
          if (fail) throw Exception('network down');
          return const PartnerPreference(preferredAgeRange: '30-35');
        },
      );
      await tester.pumpWidget(_app(repository: repo));
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsOneWidget);
      // Two NmPrimaryButtons are on screen here: the page's own (disabled)
      // Save button, and NmErrorWidget's internal (enabled) Retry button —
      // _saveButton disambiguates by label.
      expect(_saveButton(tester).onPressed, isNull);

      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsNothing);
      final l10n = _l10nOf(tester);
      expect(
        _rowValue(tester, l10n.registrationPrefAgeLabel),
        '30-35',
      );
    });
  });
}

/// The single [PreferenceRow] labelled [label]'s current display value.
String _rowValue(WidgetTester tester, String label) {
  final row = tester.widget<PreferenceRow>(
    find.byWidgetPredicate((w) => w is PreferenceRow && w.label == label),
  );
  return row.value;
}

/// The page's own bottom Save button — distinct from [NmErrorWidget]'s
/// internal Retry button, which is also an [NmPrimaryButton] and is on
/// screen at the same time during the error state.
NmPrimaryButton _saveButton(WidgetTester tester) {
  final l10n = _l10nOf(tester);
  return tester.widget<NmPrimaryButton>(
    find.byWidgetPredicate(
      (w) => w is NmPrimaryButton && w.label == l10n.partnerPrefSaveButton,
    ),
  );
}

AppLocalizations _l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(PartnerPreferencesPage)));

/// A [PartnerPreferencesRepository] fake that returns [loaded] from
/// `getPreferences` (or defers to [getPreferencesOverride] when set, for the
/// retry-recovery test) and records every `updatePreferences` call.
class _FakeRepository implements PartnerPreferencesRepository {
  _FakeRepository({required this.loaded, this.getPreferencesOverride});

  final PartnerPreference loaded;
  final Future<PartnerPreference> Function()? getPreferencesOverride;
  int updateCalls = 0;
  final List<PartnerPreference> updateRequests = [];

  @override
  Future<PartnerPreference> getPreferences() =>
      getPreferencesOverride?.call() ?? Future.value(loaded);

  @override
  Future<PartnerPreference> updatePreferences(PartnerPreference preferences) async {
    updateCalls++;
    updateRequests.add(preferences);
    return preferences;
  }
}

/// A minimal [Notifier] override for `registrationProvider` — this page
/// only reads `partnerPreference.extended` from it (see the page's own doc
/// comment on why), so an otherwise-default [ProfileDraft] is sufficient.
class _FakeRegistrationNotifier extends Notifier<ProfileDraft>
    implements RegistrationNotifier {
  @override
  ProfileDraft build() => const ProfileDraft();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app({required PartnerPreferencesRepository repository}) {
  return ProviderScope(
    overrides: [
      partnerPreferencesRepositoryProvider.overrideWithValue(repository),
      registrationProvider.overrideWith(_FakeRegistrationNotifier.new),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PartnerPreferencesPage(),
    ),
  );
}
