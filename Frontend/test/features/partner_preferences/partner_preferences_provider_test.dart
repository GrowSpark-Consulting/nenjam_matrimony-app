import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/partner_preferences/domain/repositories/partner_preferences_repository.dart';
import 'package:nenjam_matrimony/features/partner_preferences/presentation/providers/partner_preferences_provider.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';

/// Records every call so a test can assert exactly what the provider asked
/// the server for, and how many times.
class _RecordingRepository implements PartnerPreferencesRepository {
  _RecordingRepository({PartnerPreference? initial, this.getError})
      : _stored = initial ?? const PartnerPreference();

  PartnerPreference _stored;
  Object? getError;
  Object? updateError;
  int getCalls = 0;
  int updateCalls = 0;

  /// Lets a test observe the concurrency at the moment the (async) update
  /// call is in flight — e.g. to assert only one PUT ever actually starts.
  final List<PartnerPreference> updateRequests = [];

  @override
  Future<PartnerPreference> getPreferences() async {
    getCalls++;
    if (getError != null) throw getError!;
    return _stored;
  }

  @override
  Future<PartnerPreference> updatePreferences(PartnerPreference preferences) async {
    updateCalls++;
    updateRequests.add(preferences);
    if (updateError != null) throw updateError!;
    _stored = preferences;
    return _stored;
  }
}

ProviderContainer _container(_RecordingRepository repo) {
  final container = ProviderContainer(
    overrides: [partnerPreferencesRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  container.listen(partnerPreferencesProvider, (_, __) {});
  return container;
}

void main() {
  group('partnerPreferencesProvider — loading', () {
    test('build() calls getPreferences exactly once', () async {
      final repo = _RecordingRepository(
        initial: const PartnerPreference(preferredAgeRange: '26-30'),
      );
      final container = _container(repo);

      final result = await container.read(partnerPreferencesProvider.future);

      expect(repo.getCalls, 1);
      expect(result.preferredAgeRange, '26-30');
    });

    test('a failed load surfaces as AsyncError, not a crash', () async {
      final repo = _RecordingRepository(getError: ApiException(500, 'boom'));
      final container = _container(repo);

      await expectLater(
        container.read(partnerPreferencesProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(partnerPreferencesProvider).hasError, isTrue);
    });

    test('retry() re-fetches and can recover from a prior failure', () async {
      final repo = _RecordingRepository(
        getError: ApiException(500, 'boom'),
        initial: const PartnerPreference(preferredAgeRange: '30-35'),
      );
      final container = _container(repo);
      await expectLater(
        container.read(partnerPreferencesProvider.future),
        throwsA(isA<ApiException>()),
      );

      repo.getError = null;
      await container.read(partnerPreferencesProvider.notifier).retry();

      expect(repo.getCalls, 2);
      expect(container.read(partnerPreferencesProvider).hasError, isFalse);
      expect(
        container.read(partnerPreferencesProvider).value!.preferredAgeRange,
        '30-35',
      );
    });
  });

  group('partnerPreferencesProvider — save', () {
    test('save() calls updatePreferences with exactly what was passed',
        () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      await container.read(partnerPreferencesProvider.future);

      const edited = PartnerPreference(religionPref: 'Hindu', castePref: 'Same Caste');
      await container.read(partnerPreferencesProvider.notifier).save(edited);

      expect(repo.updateCalls, 1);
      expect(repo.updateRequests.single, edited);
    });

    test('a successful save updates provider state to the server\'s '
        'response', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      await container.read(partnerPreferencesProvider.future);

      final saved = await container
          .read(partnerPreferencesProvider.notifier)
          .save(const PartnerPreference(preferredAgeRange: '26-30'));

      expect(saved.preferredAgeRange, '26-30');
      expect(
        container.read(partnerPreferencesProvider).value!.preferredAgeRange,
        '26-30',
      );
    });

    test('a failed save rethrows and leaves provider state at its prior '
        'value, not AsyncError', () async {
      final repo = _RecordingRepository(
        initial: const PartnerPreference(preferredAgeRange: '30-35'),
      );
      final container = _container(repo);
      await container.read(partnerPreferencesProvider.future);

      repo.updateError = ApiException(400, 'minAge must not be less than 18');
      await expectLater(
        container
            .read(partnerPreferencesProvider.notifier)
            .save(const PartnerPreference(preferredAgeRange: '5-10')),
        throwsA(isA<ApiException>()),
      );

      // State is left exactly as it was before the failed save — no error
      // flash, no silently-adopted bad value.
      expect(container.read(partnerPreferencesProvider).hasError, isFalse);
      expect(
        container.read(partnerPreferencesProvider).value!.preferredAgeRange,
        '30-35',
      );
    });

    test('does not fire a second update while one is already in flight',
        () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      await container.read(partnerPreferencesProvider.future);
      final notifier = container.read(partnerPreferencesProvider.notifier);

      // Two overlapping saves started back-to-back, synchronously — the
      // second must observe the in-flight guard before the first's
      // microtask completes.
      final first = notifier.save(const PartnerPreference(religionPref: 'Hindu'));
      final second = notifier.save(const PartnerPreference(religionPref: 'Muslim'));
      await Future.wait([first, second]);

      expect(repo.updateCalls, 1,
          reason: 'the second call must be a no-op while the first is '
              'still in flight');
    });

    test('after the in-flight save completes, a later save is allowed '
        'through', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      await container.read(partnerPreferencesProvider.future);
      final notifier = container.read(partnerPreferencesProvider.notifier);

      await notifier.save(const PartnerPreference(religionPref: 'Hindu'));
      await notifier.save(const PartnerPreference(religionPref: 'Muslim'));

      expect(repo.updateCalls, 2);
      expect(repo.updateRequests.last.religionPref, 'Muslim');
    });
  });
}
