import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile_photos/data/repositories/photo_repository.dart';
import 'package:nenjam_matrimony/features/profile_photos/domain/models/user_photo.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/photo_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_edit_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/features/registration/presentation/widgets/registration_sticky_bottom_bar.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// **Editing a profile carries no required-field gate.**
///
/// Edit Profile inherited the wizard's rule that every required field had to
/// be present before Save would light up. That rule belongs to *completing a
/// registration*, not to editing: a member who wants to change their
/// occupation should not have to fill in sections they never opened, and one
/// whose profile predates a newer required field would have been locked out
/// of editing anything at all.
///
/// Nothing downstream needed it. The section PATCH DTOs are `@IsOptional()`
/// field by field, and edit-mode save does not call `POST /profiles/finalize`
/// — which is where the end-of-signup rules live, unchanged, for CREATE mode.
void main() {
  Future<RegistrationStickyBottomBar> pumpAndReadBar(
    WidgetTester tester, {
    required ProfileDraft draft,
  }) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const size = Size(390, 844);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    await tester.binding.setSurfaceSize(size);

    final container = ProviderContainer(
      overrides: [
        photoRepositoryProvider.overrideWithValue(_EmptyPhotoRepository()),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(registrationProvider.notifier)
        .restore(draft, ProfileFlowMode.edit);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProfileEditPage(),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    return tester.widget<RegistrationStickyBottomBar>(
      find.byType(RegistrationStickyBottomBar),
    );
  }

  testWidgets('an entirely empty profile can still be saved', (tester) async {
    // Nothing filled in at all — the case the old gate rejected outright.
    final bar = await pumpAndReadBar(tester, draft: const ProfileDraft());

    expect(
      bar.onNext,
      isNotNull,
      reason: 'Save must be available with no fields filled in',
    );
    expect(
      bar.validationHint,
      isNull,
      reason: 'no required-fields hint belongs on Edit Profile',
    );
  });

  testWidgets('one changed field with the rest empty can be saved', (
    tester,
  ) async {
    // "User changes only their occupation" — every other section untouched
    // and incomplete, which the old gate treated as unsaveable.
    final bar = await pumpAndReadBar(
      tester,
      draft: const ProfileDraft(
        educationDetails: EducationDetails(occupation: 'Architect'),
      ),
    );

    expect(bar.onNext, isNotNull);
    expect(bar.validationHint, isNull);
  });

  testWidgets('a half-filled optional section can be saved', (tester) async {
    // A section touched but left partly empty. `PhysicalDetails.isValid` is
    // false here (touched-but-incomplete), which used to disable Save across
    // the whole page.
    const draft = ProfileDraft(
      physicalDetails: PhysicalDetails(height: '170'),
    );
    expect(
      draft.physicalDetails.isValid,
      isFalse,
      reason: 'guards the premise: this is the shape the old gate rejected',
    );

    final bar = await pumpAndReadBar(tester, draft: draft);

    expect(bar.onNext, isNotNull);
    expect(bar.validationHint, isNull);
  });

  testWidgets('Save is still blocked while a save is already in flight', (
    tester,
  ) async {
    // The one reason left to disable it — not a validation rule.
    final bar = await pumpAndReadBar(tester, draft: const ProfileDraft());
    expect(bar.isLoading, isFalse);
    expect(bar.onNext, isNotNull);
    expect(bar.onBack, isNotNull);
  });
}

class _EmptyPhotoRepository implements PhotoRepository {
  @override
  Future<List<UserPhoto>> fetchPhotos() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
