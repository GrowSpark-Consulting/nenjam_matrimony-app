import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/features/profile_photos/data/repositories/photo_repository.dart';
import 'package:nenjam_matrimony/features/profile_photos/domain/models/user_photo.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/photo_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/edit_profile_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_section_edit_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/features/registration/presentation/utils/open_edit_profile.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'onboarding_test_support.dart';

/// A registered member's saved profile, with a value in every section — the
/// registration fields the edit pages show, and the ones they do not (weight,
/// gothra, smoking, ...), so a test can prove a save leaves those alone.
ProfileDraft savedProfile() => ProfileDraft(
  basicDetails: BasicDetails(
    firstName: 'Meera',
    lastName: 'Rajan',
    gender: 'Female',
    dob: DateTime(1995, 3, 21),
    maritalStatus: 'Never Married',
    profileCreatedFor: 'Myself',
  ),
  religionDetails: const ReligionDetails(
    religion: 'Hindu',
    religionCode: 'HINDU',
    community: 'Iyer',
    communityCode: 'HINDU-IYER',
    subCaste: 'Vadama',
    caste: 'Brahmin',
    gothra: 'Kashyapa',
  ),
  locationDetails: const LocationDetails(
    country: 'India',
    countryCode: 'IN',
    state: 'Tamil Nadu',
    stateCode: 'IN-TN',
    city: 'Chennai',
    cityCode: 'IN-TN-CHENNAI',
    pinCode: '600001',
  ),
  educationDetails: const EducationDetails(
    qualification: 'B.E.',
    college: 'Anna University',
    occupation: 'Software Engineer',
    company: 'Acme',
    employmentType: 'Private',
    annualIncome: '10-15 Lakhs',
  ),
  physicalDetails: const PhysicalDetails(height: "5'4\"", weight: '55'),
  lifestyleDetails: const LifestyleDetails(
    eatingHabit: 'Vegetarian',
    aboutMe: 'I love music.',
    smoking: 'No',
  ),
  familyDetails: const FamilyDetails(
    father: FamilyMember(name: 'Suresh', age: 58, occupation: 'Engineer'),
    familyType: 'Nuclear',
  ),
  horoscopeDetails: const HoroscopeDetails(rashi: 'Mesha'),
);

/// Records section saves (see [RecordingRegistrationRepository]) and serves
/// [savedProfile] as `GET /profiles/draft`. Either can be told to fail.
class EditProfileRepository extends RecordingRegistrationRepository {
  bool failGetDraft = false;
  bool failSaves = false;

  /// What a failing save throws; a generic exception when null.
  Object? saveError;
  int getDraftCalls = 0;

  @override
  Future<Map<String, dynamic>> getDraft() async {
    getDraftCalls++;
    if (failGetDraft) throw Exception('offline');
    return savedProfile().toJson();
  }

  @override
  Future<void> updateBasicDetails(
    BasicDetails details, {
    bool skipMaterialize = false,
  }) async {
    if (failSaves) throw saveError ?? Exception('save failed');
    return super.updateBasicDetails(details, skipMaterialize: skipMaterialize);
  }

  @override
  Future<void> updateLocationDetails(
    LocationDetails details, {
    bool skipMaterialize = false,
  }) async {
    if (failSaves) throw saveError ?? Exception('save failed');
    return super.updateLocationDetails(
      details,
      skipMaterialize: skipMaterialize,
    );
  }

  @override
  Future<void> updateFamilyDetails(
    FamilyDetails details, {
    bool skipMaterialize = false,
  }) async {
    if (failSaves) throw saveError ?? Exception('save failed');
    return super.updateFamilyDetails(details, skipMaterialize: skipMaterialize);
  }
}

class EmptyPhotoRepository implements PhotoRepository {
  @override
  Future<List<UserPhoto>> fetchPhotos() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The app's Edit Profile routes, for real, plus stand-ins for the pages
/// that live in other features. The initial route is a PROFILE stand-in
/// with one button per way into the edit pages, so back navigation has
/// somewhere real to return to.
class EditProfileHarness {
  EditProfileHarness({EditProfileRepository? repository})
    : repository = repository ?? EditProfileRepository();

  final EditProfileRepository repository;
  late final ProviderContainer container;
  late final GoRouter router;

  ProfileDraft get draft => container.read(registrationProvider);

  /// [mode]: EDIT (Edit Profile opened from the Profile screen, draft
  /// already loaded — the normal case), CREATE with a draft (the
  /// end-of-registration review), or null for a cold start with nothing
  /// loaded at all.
  Future<void> pump(
    WidgetTester tester, {
    ProfileFlowMode? mode = ProfileFlowMode.edit,
  }) async {
    useTallSurface(tester);
    container = ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(repository),
        profileDraftResponseProvider.overrideWith(
          (ref) async => <String, dynamic>{},
        ),
        photoRepositoryProvider.overrideWithValue(EmptyPhotoRepository()),
        ...locationOverrides(FakeLocationRepository()),
      ],
    );
    addTearDown(container.dispose);
    if (mode != null) {
      container
          .read(registrationProvider.notifier)
          .restore(savedProfile(), mode);
    }

    Widget stub(String text) => Scaffold(body: Center(child: Text(text)));

    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ListView(
                children: [
                  const Text('PROFILE'),
                  TextButton(
                    onPressed: () => context.push(RouteNames.editProfile),
                    child: const Text('open edit profile'),
                  ),
                  for (final step in [7, 8, 9, 10, 12])
                    TextButton(
                      onPressed: () => context.push(profileSectionRoute(step)),
                      child: Text('open section $step'),
                    ),
                  TextButton(
                    onPressed: () =>
                        openEditProfile(context, ref, wizardStep: 7),
                    child: const Text('open family via openEditProfile'),
                  ),
                ],
              ),
            ),
          ),
        ),
        GoRoute(
          path: RouteNames.editProfile,
          builder: (_, _) => const EditProfilePage(),
        ),
        GoRoute(
          path: RouteNames.basicInfoEdit,
          builder: (_, _) => const BasicInfoEditPage(),
        ),
        GoRoute(
          path: RouteNames.religionCommunityEdit,
          builder: (_, _) => const ReligionCommunityEditPage(),
        ),
        GoRoute(
          path: RouteNames.locationEdit,
          builder: (_, _) => const LocationEditPage(),
        ),
        GoRoute(
          path: RouteNames.educationWorkEdit,
          builder: (_, _) => const EducationWorkEditPage(),
        ),
        GoRoute(
          path: RouteNames.physicalDetailsEdit,
          builder: (_, _) => const PhysicalDetailsEditPage(),
        ),
        GoRoute(
          path: RouteNames.lifestyleAboutEdit,
          builder: (_, _) => const LifestyleAboutEditPage(),
        ),
        GoRoute(
          path: RouteNames.photosEdit,
          builder: (_, _) => const PhotosEditPage(),
        ),
        GoRoute(
          path: RouteNames.familyDetailsEdit,
          builder: (_, _) => const FamilyDetailsEditPage(),
        ),
        GoRoute(
          path: RouteNames.horoscopeDetailsEdit,
          builder: (_, _) => const HoroscopeDetailsEditPage(),
        ),
        GoRoute(
          path: RouteNames.psychologyQuiz,
          builder: (_, _) => stub('PSYCHOLOGY QUIZ PAGE'),
        ),
        GoRoute(
          path: RouteNames.partnerPreferences,
          builder: (_, _) => stub('PARTNER PREFERENCES PAGE'),
        ),
        GoRoute(
          path: RouteNames.verification,
          builder: (_, _) => stub('VERIFICATION PAGE'),
        ),
        GoRoute(
          path: RouteNames.registrationCompleting,
          builder: (_, _) => stub('COMPLETING PAGE'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await settle(tester);
  }

  /// Opens [route] on top of the PROFILE stand-in.
  Future<void> open(WidgetTester tester, String route) async {
    router.push(route);
    await settle(tester);
  }
}

/// pumpAndSettle, then past the flutter_animate entrance delays the section
/// widgets start on a timer, which pumpAndSettle does not wait out.
Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// Taps the page's primary action (Save).
Future<void> tapSave(WidgetTester tester) async {
  final save = find.text(AppLocalizationsEnLabels.save);
  await tester.ensureVisible(save);
  await tester.tap(save);
  await settle(tester);
}

/// Taps the AppBar's back arrow.
Future<void> tapBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await settle(tester);
}

/// The English strings the tests assert on, in one place.
abstract final class AppLocalizationsEnLabels {
  static const save = 'Save';
  static const updated = 'Profile updated successfully';
  static const saveError =
      'Could not save your profile. Check your connection.';
  static const loadError =
      'Could not load your profile. Check your connection.';
  static const retry = 'Retry';
}
