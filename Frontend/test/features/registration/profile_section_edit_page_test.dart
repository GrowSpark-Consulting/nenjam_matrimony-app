import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/widgets/inputs/birth_date_field.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_section_edit_page.dart';

import 'edit_profile_test_support.dart';
import 'onboarding_test_support.dart';

/// What every section edit page owes the member: their saved values on open,
/// a Save that writes that one section and nothing else, a Back that writes
/// nothing, and an error that keeps them — and their edits — on the page.
///
/// Each page shows only the fields registration collects for its section.
/// The section's other stored fields are not shown, and must survive a save
/// untouched.
void main() {
  late EditProfileHarness harness;

  Future<void> openSection(
    WidgetTester tester,
    String route, {
    EditProfileRepository? repository,
  }) async {
    harness = EditProfileHarness(repository: repository);
    await harness.pump(tester);
    await harness.open(tester, route);
  }

  Future<void> type(WidgetTester tester, String current, String next) async {
    await tester.enterText(find.widgetWithText(TextFormField, current), next);
    await tester.pump();
  }

  group('each section loads its saved values and saves only itself', () {
    testWidgets('Basic Information', (tester) async {
      await openSection(tester, RouteNames.basicInfoEdit);
      expect(find.text('Meera'), findsOneWidget);
      expect(find.text('Rajan'), findsOneWidget);
      expect(find.text('1995'), findsOneWidget);
      expect(find.text('Never Married'), findsOneWidget);

      await type(tester, 'Meera', 'Meenakshi');
      await tapSave(tester);

      expect(harness.repository.savedSections, ['basicDetails']);
      final sent = harness.repository.savedBasic!;
      expect(sent.firstName, 'Meenakshi');
      expect(sent.lastName, 'Rajan');
      expect(sent.gender, 'Female');
      expect(sent.dob, DateTime(1995, 3, 21));
      expect(sent.profileCreatedFor, 'Myself');
    });

    testWidgets('Religion & Community', (tester) async {
      await openSection(tester, RouteNames.religionCommunityEdit);
      expect(find.text('Hindu'), findsOneWidget);
      expect(find.text('Iyer'), findsOneWidget);
      expect(find.text('Vadama'), findsOneWidget);

      await type(tester, 'Vadama', 'Vathima');
      await tapSave(tester);

      expect(harness.repository.savedSections, ['religionDetails']);
      final sent = harness.repository.savedReligion!;
      expect(sent.subCaste, 'Vathima');
      // Codes survive an unrelated edit.
      expect(sent.religionCode, 'HINDU');
      expect(sent.communityCode, 'HINDU-IYER');
      // Not shown, and untouched.
      expect(sent.caste, 'Brahmin');
      expect(sent.gothra, 'Kashyapa');
    });

    testWidgets('Location', (tester) async {
      await openSection(tester, RouteNames.locationEdit);
      expect(find.text('India'), findsOneWidget);
      expect(find.text('Tamil Nadu'), findsOneWidget);
      expect(find.text('Chennai'), findsOneWidget);

      await pickLocation(tester, 'State', 'Gujarat');
      await pickLocation(tester, 'City', 'Ahmedabad');
      await tapSave(tester);

      expect(harness.repository.savedSections, ['locationDetails']);
      final sent = harness.repository.savedLocation!;
      expect(sent.stateCode, 'IN-GJ');
      expect(sent.city, 'Ahmedabad');
      expect(sent.cityCode, 'IN-GJ-AHMEDABAD');
      expect(sent.pinCode, '600001');
    });

    testWidgets('Education & Work', (tester) async {
      await openSection(tester, RouteNames.educationWorkEdit);
      expect(find.text('B.E.'), findsOneWidget);
      expect(find.text('Anna University'), findsOneWidget);
      expect(find.text('Acme'), findsOneWidget);

      await type(tester, 'Acme', 'Globex');
      await tapSave(tester);

      expect(harness.repository.savedSections, ['educationDetails']);
      final sent = harness.repository.savedEducation!;
      expect(sent.company, 'Globex');
      expect(sent.qualification, 'B.E.');
      expect(sent.employmentType, 'Private');
      expect(sent.annualIncome, '10-15 Lakhs');
    });

    testWidgets('Physical Details', (tester) async {
      await openSection(tester, RouteNames.physicalDetailsEdit);
      expect(find.text("5'4\""), findsOneWidget);
      // Registration asks height only.
      expect(find.byType(TextFormField), findsNothing);

      await tapSave(tester);

      expect(harness.repository.savedSections, ['physicalDetails']);
      expect(harness.repository.savedPhysical!.height, "5'4\"");
      expect(harness.repository.savedPhysical!.weight, '55');
    });

    testWidgets('Lifestyle & About', (tester) async {
      await openSection(tester, RouteNames.lifestyleAboutEdit);
      expect(find.text('Vegetarian'), findsOneWidget);
      expect(find.text('I love music.'), findsOneWidget);

      await type(tester, 'I love music.', 'I love music and travel.');
      await tapSave(tester);

      expect(harness.repository.savedSections, ['lifestyleDetails']);
      final sent = harness.repository.savedLifestyle!;
      expect(sent.aboutMe, 'I love music and travel.');
      expect(sent.eatingHabit, 'Vegetarian');
      expect(sent.smoking, 'No');
    });

    testWidgets('Family Details', (tester) async {
      await openSection(tester, RouteNames.familyDetailsEdit);
      expect(find.text('Suresh'), findsOneWidget);

      await type(tester, 'Suresh', 'Suresh Kumar');
      await tapSave(tester);

      expect(harness.repository.savedSections, ['familyDetails']);
      expect(harness.repository.savedFamily!.father.name, 'Suresh Kumar');
    });

    testWidgets('Horoscope', (tester) async {
      await openSection(tester, RouteNames.horoscopeDetailsEdit);
      expect(
        find.text('Your stars can tell part of the story'),
        findsOneWidget,
      );

      await tapSave(tester);

      expect(harness.repository.savedSections, ['horoscopeDetails']);
      expect(harness.repository.savedHoroscope!.rashi, 'Mesha');
    });

    testWidgets('Photos: managed directly, with no Save', (tester) async {
      await openSection(tester, RouteNames.photosEdit);
      expect(find.byType(PhotosEditPage), findsOneWidget);
      expect(find.text(AppLocalizationsEnLabels.save), findsNothing);
    });
  });

  group('the section pages only show fields registration collects', () {
    testWidgets('no weight, gothra, PIN code, smoking or languages', (
      tester,
    ) async {
      for (final route in [
        RouteNames.basicInfoEdit,
        RouteNames.religionCommunityEdit,
        RouteNames.locationEdit,
        RouteNames.educationWorkEdit,
        RouteNames.physicalDetailsEdit,
        RouteNames.lifestyleAboutEdit,
      ]) {
        await openSection(tester, route);
        for (final hidden in ['55', 'Kashyapa', 'Brahmin', '600001', 'No']) {
          expect(find.text(hidden), findsNothing, reason: '$hidden on $route');
        }
        expect(find.textContaining('Mother Tongue'), findsNothing);
        expect(find.textContaining('Languages'), findsNothing);
      }
    });
  });

  group('success returns to where the page was opened from', () {
    testWidgets('with a confirmation, and the draft updated', (tester) async {
      await openSection(tester, RouteNames.educationWorkEdit);
      await type(tester, 'Acme', 'Globex');
      await tapSave(tester);

      expect(find.text('PROFILE'), findsOneWidget);
      expect(find.byType(EducationWorkEditPage), findsNothing);
      expect(find.text(AppLocalizationsEnLabels.updated), findsOneWidget);
      expect(harness.draft.educationDetails.company, 'Globex');
    });
  });

  group('back saves nothing', () {
    testWidgets('the AppBar arrow leaves, sends nothing, keeps the draft', (
      tester,
    ) async {
      await openSection(tester, RouteNames.basicInfoEdit);
      await type(tester, 'Meera', 'Changed');

      await tapBack(tester);

      expect(find.text('PROFILE'), findsOneWidget);
      expect(harness.repository.savedSections, isEmpty);
      expect(harness.draft.basicDetails.firstName, 'Meera');
    });
  });

  group('a failed save keeps the member on the page', () {
    testWidgets('with an error and their edits, and nothing committed', (
      tester,
    ) async {
      final repository = EditProfileRepository()..failSaves = true;
      await openSection(
        tester,
        RouteNames.locationEdit,
        repository: repository,
      );
      await pickLocation(tester, 'City', 'Chennai');
      await tapSave(tester);

      expect(find.byType(LocationEditPage), findsOneWidget);
      expect(find.text(AppLocalizationsEnLabels.saveError), findsOneWidget);
      expect(find.text(AppLocalizationsEnLabels.updated), findsNothing);
      expect(harness.draft.locationDetails.city, 'Chennai');
    });

    testWidgets('a date of birth that names no date blocks the save', (
      tester,
    ) async {
      await openSection(tester, RouteNames.basicInfoEdit);
      final boxes = find.descendant(
        of: find.byType(NmBirthDateField),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(boxes.at(0), '31');
      await tester.enterText(boxes.at(1), '02');
      await tester.pump();

      await tapSave(tester);

      expect(find.byType(BasicInfoEditPage), findsOneWidget);
      expect(harness.repository.savedSections, isEmpty);
      expect(find.text('Please enter a valid date of birth.'), findsWidgets);
    });
  });

  group('every error status keeps the member on the editor', () {
    // What the real repository throws for each: a 4xx comes back as a
    // response and becomes an ApiException carrying the server's message; a
    // 5xx is raised by Dio. Neither may read as success, commit the edit
    // locally, or leave the page — and Save must work again once the backend
    // does.
    final errors = <String, Object>{
      for (final status in [400, 401, 403, 404, 409])
        'HTTP $status': ApiException(status, 'rejected with $status'),
      'HTTP 500': DioException(
        requestOptions: RequestOptions(
          path: '/profiles/draft/location-details',
        ),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(
            path: '/profiles/draft/location-details',
          ),
          statusCode: 500,
        ),
      ),
    };

    for (final entry in errors.entries) {
      testWidgets('${entry.key}: error shown, nothing committed, retry works', (
        tester,
      ) async {
        final repository = EditProfileRepository()
          ..failSaves = true
          ..saveError = entry.value;
        await openSection(
          tester,
          RouteNames.locationEdit,
          repository: repository,
        );
        await pickLocation(tester, 'City', 'Chennai');
        await pickLocation(tester, 'State', 'Gujarat');
        await pickLocation(tester, 'City', 'Ahmedabad');
        await tapSave(tester);

        expect(find.byType(LocationEditPage), findsOneWidget);
        expect(find.text(AppLocalizationsEnLabels.updated), findsNothing);
        final error = entry.value;
        expect(
          find.text(
            error is ApiException
                ? 'Could not save your profile: ${error.message}'
                : AppLocalizationsEnLabels.saveError,
          ),
          findsOneWidget,
        );
        expect(harness.draft.locationDetails.city, 'Chennai');
        expect(harness.repository.savedSections, isEmpty);

        // The backend recovers; the member's edit is still on screen.
        repository.failSaves = false;
        ScaffoldMessenger.of(
          tester.element(find.byType(LocationEditPage)),
        ).clearSnackBars();
        await settle(tester);
        await tapSave(tester);

        expect(find.text('PROFILE'), findsOneWidget);
        expect(harness.repository.savedLocation!.city, 'Ahmedabad');
        expect(harness.draft.locationDetails.city, 'Ahmedabad');
      });
    }
  });

  group('opened cold, with nothing loaded', () {
    testWidgets('loads the saved values rather than an empty form', (
      tester,
    ) async {
      harness = EditProfileHarness();
      await harness.pump(tester, mode: null);
      await harness.open(tester, RouteNames.lifestyleAboutEdit);

      expect(harness.repository.getDraftCalls, 1);
      expect(find.text('I love music.'), findsOneWidget);
    });

    testWidgets('a failed load shows Retry, not a blank form', (tester) async {
      final repository = EditProfileRepository()..failGetDraft = true;
      harness = EditProfileHarness(repository: repository);
      await harness.pump(tester, mode: null);
      await harness.open(tester, RouteNames.lifestyleAboutEdit);

      expect(find.text(AppLocalizationsEnLabels.loadError), findsOneWidget);
      expect(find.text(AppLocalizationsEnLabels.save), findsNothing);

      repository.failGetDraft = false;
      await tester.tap(find.text(AppLocalizationsEnLabels.retry));
      await settle(tester);

      expect(find.text('I love music.'), findsOneWidget);
    });
  });

  group('cascades', () {
    testWidgets('changing religion clears the community and its code', (
      tester,
    ) async {
      await openSection(tester, RouteNames.religionCommunityEdit);
      await pickLocation(tester, 'Religion', 'Jain');
      expect(find.text('Iyer'), findsNothing);

      await pickLocation(tester, 'Community', 'Digambar');
      await tapSave(tester);

      final sent = harness.repository.savedReligion!;
      expect(sent.religionCode, 'JAIN');
      expect(sent.community, 'Digambar');
      expect(sent.communityCode, 'JAIN-DIGAMBAR');
    });

    testWidgets('changing country clears state and city', (tester) async {
      await openSection(tester, RouteNames.locationEdit);
      await pickLocation(tester, 'Living in', 'Canada');
      await tapSave(tester);

      final sent = harness.repository.savedLocation!;
      expect(sent.countryCode, 'CA');
      expect(sent.state, isEmpty);
      expect(sent.city, isEmpty);
    });
  });
}
