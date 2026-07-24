import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile_completion/domain/profile_completion_aggregator.dart';

/// The "Step 13 max 25%, 5% per verified flag" contract, plus the overall
/// weighting rules from the product spec, are now enforced entirely by the
/// backend's ProfileCompletionService (see
/// `backend/apps/api/src/modules/profiles/tests/profile-completion.service.
/// spec.ts` for that coverage) — the Flutter app no longer computes any
/// weight or completion rule of its own. What's left to verify here is only
/// that [profileCompletionFromBackend] faithfully reshapes whatever the
/// backend's `completionPercentage` / `completionBreakdown` response says,
/// without silently re-deriving or disagreeing with it.
void main() {
  group('profileCompletenessFromBackend', () {
    test('passes the backend percentage through unchanged', () {
      final result = profileCompletenessFromBackend(65, const [
        {'id': 'registration', 'weight': 20, 'isComplete': true, 'wizardStep': 0},
      ]);

      expect(result.percentage, 65);
    });

    test('splits modules into completed vs missing using the backend flag only', () {
      final result = profileCompletenessFromBackend(30, const [
        {'id': 'registration', 'weight': 20, 'isComplete': true, 'wizardStep': 0},
        {'id': 'verification', 'weight': 25, 'isComplete': false, 'wizardStep': 12},
        {'id': 'photos', 'weight': 12, 'isComplete': false, 'wizardStep': 11},
      ]);

      expect(result.completedModules.map((e) => e.module.id), ['registration']);
      expect(
        result.missingModules.map((e) => e.module.id),
        containsAll(['verification', 'photos']),
      );
    });

    test('highest-impact module is the heaviest-weighted incomplete one', () {
      final result = profileCompletenessFromBackend(30, const [
        {'id': 'photos', 'weight': 12, 'isComplete': false, 'wizardStep': 11},
        {'id': 'verification', 'weight': 25, 'isComplete': false, 'wizardStep': 12},
        {'id': 'family', 'weight': 10, 'isComplete': false, 'wizardStep': 7},
      ]);

      expect(result.highestImpactModule?.module.id, 'verification');
    });

    test('highest-impact module is null once every module is complete', () {
      final result = profileCompletenessFromBackend(100, const [
        {'id': 'registration', 'weight': 20, 'isComplete': true, 'wizardStep': 0},
        {'id': 'photos', 'weight': 12, 'isComplete': true, 'wizardStep': 11},
      ]);

      expect(result.highestImpactModule, isNull);
      expect(result.missingModules, isEmpty);
    });

    test('tier tracks the backend percentage, matching the same bands as the hero display', () {
      expect(profileCompletenessFromBackend(0, const []).tier, ProfileStrengthTier.building);
      expect(profileCompletenessFromBackend(45, const []).tier, ProfileStrengthTier.good);
      expect(profileCompletenessFromBackend(75, const []).tier, ProfileStrengthTier.strong);
      expect(profileCompletenessFromBackend(95, const []).tier, ProfileStrengthTier.exceptional);
    });

    test('wizardStep is carried through for the "jump to fix" action', () {
      final result = profileCompletenessFromBackend(20, const [
        {'id': 'education', 'weight': 10, 'isComplete': false, 'wizardStep': 4},
      ]);

      expect(result.missingModules.single.status.wizardStep, 4);
    });
  });
}
