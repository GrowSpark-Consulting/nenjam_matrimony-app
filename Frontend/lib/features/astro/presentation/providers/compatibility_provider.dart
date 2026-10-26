import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_l10n.dart';
import '../../../profile/presentation/providers/profile_dashboard_providers.dart';
import '../../domain/models/compatibility_result.dart';
import '../../domain/repositories/compatibility_repository.dart';
import '../../data/repositories/mock_compatibility_repository.dart';

/// In-memory MOCK — returns invented data, so no screen may present it as a
/// member's real horoscope or a real match. Nothing reads it today:
/// `HoroscopeMatchingPage` says the feature is unavailable, and
/// [myHoroscopeSummaryProvider] reads the member's saved profile instead.
/// Override this provider with an `ApiCompatibilityRepository` once the
/// backend's `astro` endpoints exist and are mounted.
final compatibilityRepositoryProvider = Provider<CompatibilityRepository>(
  (ref) => MockCompatibilityRepository(),
);

/// The signed-in member's own horoscope, exactly as saved on the Horoscope
/// step of their profile (`GET /profiles/draft`). Empty fields stay empty, so
/// [HoroscopeCompatibilitySection] shows its "not added yet" state rather
/// than someone else's chart. Used by ProfilePage; invalidated by the
/// Horoscope section's edit-and-save.
///
/// `matchingEnabled` reflects the member's own "horoscope available" answer
/// — the only persisted horoscope-matching signal there is (no separate
/// opt-in setting exists on the backend).
final myHoroscopeSummaryProvider = FutureProvider.autoDispose<HoroscopeSummary>(
  (ref) async {
    final draft = await ref.watch(myProfileDraftProvider.future);
    final h = draft.horoscopeDetails;
    String? orNull(String v) => v.trim().isEmpty ? null : v.trim();
    return HoroscopeSummary(
      rasi: orNull(h.rashi),
      nakshatra: orNull(h.nakshatra),
      // The step records Yes / No / Don't Know. Only a "Yes" is worth a chip;
      // the widget already hides 'NONE'.
      dosham: h.dosham == 'Yes'
          ? AppL10n.current.registrationDoshamLabel
          : (h.dosham == 'No' ? 'NONE' : null),
      birthTime: orNull(h.birthTime),
      birthPlace: orNull(h.birthPlace),
      matchingEnabled: h.horoscopeAvailable,
    );
  },
);

/// A representative compatibility preview (mock data). Not read by any
/// screen — kept only so the repository contract stays exercised until the
/// real astro endpoints land. Must not be shown as a real result.
final compatibilityPreviewProvider =
    FutureProvider.autoDispose<CompatibilityResult>((ref) {
      return ref.watch(compatibilityRepositoryProvider).getCompatibility();
    });
