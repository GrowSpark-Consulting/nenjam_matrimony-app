import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/edit_profile_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_section_edit_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/features/registration/presentation/utils/open_edit_profile.dart';

import 'edit_profile_test_support.dart';
import 'onboarding_test_support.dart';

/// Edit Profile is a **section list**: one row per registration section, and
/// each row's pencil opens that section's own edit page. There is no page
/// that edits every section at once, and no Save that writes them all.
void main() {
  Finder row(String id) => find.byKey(ValueKey('edit-profile-section-$id'));

  Future<void> tapPencil(WidgetTester tester, String id) async {
    // The card's own "✎ Edit" button, not merely anywhere on the card.
    final pencil = find.descendant(
      of: row(id),
      matching: find.widgetWithText(TextButton, 'Edit'),
    );
    await tester.ensureVisible(pencil);
    await tester.tap(pencil);
    await settle(tester);
  }

  group('the section list', () {
    testWidgets('lists the seven registration sections, in order', (
      tester,
    ) async {
      final harness = EditProfileHarness();
      await harness.pump(tester);
      await harness.open(tester, RouteNames.editProfile);

      final ids = [
        'basic',
        'religion',
        'location',
        'education',
        'physical',
        'lifestyle',
        'photos',
      ];
      var lastDy = double.negativeInfinity;
      for (final id in ids) {
        expect(row(id), findsOneWidget, reason: 'missing row "$id"');
        final dy = tester.getTopLeft(row(id)).dy;
        expect(dy, greaterThan(lastDy), reason: '"$id" is out of order');
        lastDy = dy;
      }
      expect(EditProfileSection.all.map((s) => s.id).toList(), ids);
    });

    testWidgets('summarises each section from the saved profile', (
      tester,
    ) async {
      final harness = EditProfileHarness();
      await harness.pump(tester);
      await harness.open(tester, RouteNames.editProfile);

      // Every card lists its saved answers as label / value rows.
      final expected = <String, Map<String, String>>{
        'basic': {
          'First Name': 'Meera',
          'Last Name': 'Rajan',
          'Date of Birth': '21/03/1995',
          'Profile for': 'Myself',
          'Gender': 'Female',
          'Marital Status': 'Never Married',
        },
        'religion': {
          'Religion': 'Hindu',
          'Community': 'Iyer',
          'Sub-community': 'Vadama',
        },
        'location': {
          'Country': 'India',
          'State': 'Tamil Nadu',
          'City': 'Chennai',
        },
        'education': {
          'Highest Qualification': 'B.E.',
          'College / University': 'Anna University',
          'Annual Income': '10-15 Lakhs',
          'You work with': 'Private',
          'Occupation': 'Software Engineer',
          'Company': 'Acme',
        },
        'physical': {'Height': "5'4\""},
        'lifestyle': {'Diet': 'Vegetarian', 'About Me': 'I love music.'},
      };
      for (final card in expected.entries) {
        for (final field in card.value.entries) {
          for (final text in [field.key, field.value]) {
            expect(
              find.descendant(of: row(card.key), matching: find.text(text)),
              findsOneWidget,
              reason: '"$text" missing from the ${card.key} card',
            );
          }
        }
      }
      // No photos yet.
      expect(
        find.descendant(
          of: row('photos'),
          matching: find.text('No information added yet.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows no field registration does not collect', (tester) async {
      final harness = EditProfileHarness();
      await harness.pump(tester);
      await harness.open(tester, RouteNames.editProfile);

      for (final label in [
        'Weight',
        'Blood Group',
        'Body Type',
        'Complexion',
        'Disability',
        'Smoking',
        'Drinking',
        'Fitness',
        'Hobbies',
        'Caste',
        'Gothra',
        'Area',
        'PIN Code',
        'Native Place',
        'Mother Tongue',
        'Languages Known',
      ]) {
        expect(find.text(label), findsNothing, reason: '"$label" is shown');
      }
      // The saved values behind those fields are not shown either.
      for (final value in ['55', 'Brahmin', 'Kashyapa', '600001', 'No']) {
        expect(find.text(value), findsNothing, reason: '"$value" is shown');
      }
    });

    testWidgets('holds no form, no Save, and none of the separate sections', (
      tester,
    ) async {
      final harness = EditProfileHarness();
      await harness.pump(tester);
      await harness.open(tester, RouteNames.editProfile);

      // Nothing is edited on this page itself.
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text(AppLocalizationsEnLabels.save), findsNothing);
      expect(find.text('Save Changes'), findsNothing);
      // Each card's action is Edit — one per section.
      expect(find.widgetWithText(TextButton, 'Edit'), findsNWidgets(7));

      // Languages is not part of registration, so not part of Edit Profile.
      expect(find.text('Languages'), findsNothing);
      expect(row('language'), findsNothing);
      // The separate profile sections have pages of their own.
      for (final title in [
        'Family Details',
        'Horoscope',
        'Partner Preferences',
        'Psychology',
        'Verification',
      ]) {
        expect(find.text(title), findsNothing, reason: '"$title" is listed');
      }
      expect(find.text('Tell us about your family'), findsNothing);
      expect(find.text('Your stars can tell part of the story'), findsNothing);
    });
  });

  group('each pencil opens its own section page', () {
    final pages = <String, Type>{
      'basic': BasicInfoEditPage,
      'religion': ReligionCommunityEditPage,
      'location': LocationEditPage,
      'education': EducationWorkEditPage,
      'physical': PhysicalDetailsEditPage,
      'lifestyle': LifestyleAboutEditPage,
      'photos': PhotosEditPage,
    };

    for (final entry in pages.entries) {
      testWidgets('${entry.key} → ${entry.value}', (tester) async {
        final harness = EditProfileHarness();
        await harness.pump(tester);
        await harness.open(tester, RouteNames.editProfile);

        await tapPencil(tester, entry.key);
        expect(find.byType(entry.value), findsOneWidget);
        expect(find.byType(EditProfilePage), findsNothing);

        // Back returns to the list, having saved nothing.
        await tapBack(tester);
        expect(find.byType(EditProfilePage), findsOneWidget);
        expect(harness.repository.savedSections, isEmpty);
      });
    }
  });

  group('the separate sections open their own pages', () {
    testWidgets('horoscope, family, partner preferences, psychology, '
        'verification', (tester) async {
      final harness = EditProfileHarness();
      await harness.pump(tester);

      final expected = <int, Finder>{
        7: find.byType(FamilyDetailsEditPage),
        8: find.byType(HoroscopeDetailsEditPage),
        9: find.text('PSYCHOLOGY QUIZ PAGE'),
        10: find.text('PARTNER PREFERENCES PAGE'),
        12: find.text('VERIFICATION PAGE'),
      };
      for (final entry in expected.entries) {
        await tester.tap(find.text('open section ${entry.key}'));
        await settle(tester);
        expect(entry.value, findsOneWidget, reason: 'section ${entry.key}');
        harness.router.pop();
        await settle(tester);
      }
    });

    testWidgets('openEditProfile loads the profile, then opens Family', (
      tester,
    ) async {
      final harness = EditProfileHarness();
      await harness.pump(tester, mode: null);

      await tester.tap(find.text('open family via openEditProfile'));
      await settle(tester);

      expect(harness.repository.getDraftCalls, 1);
      expect(find.byType(FamilyDetailsEditPage), findsOneWidget);
      expect(find.text('Suresh'), findsOneWidget);
    });

    test('every section index has a page of its own', () {
      expect(profileSectionRoute(null), RouteNames.editProfile);
      expect(profileSectionRoute(0), RouteNames.basicInfoEdit);
      expect(profileSectionRoute(1), RouteNames.religionCommunityEdit);
      // Languages: not collected at registration, no page — the list.
      expect(profileSectionRoute(2), RouteNames.editProfile);
      expect(profileSectionRoute(3), RouteNames.locationEdit);
      expect(profileSectionRoute(4), RouteNames.educationWorkEdit);
      expect(profileSectionRoute(5), RouteNames.physicalDetailsEdit);
      expect(profileSectionRoute(6), RouteNames.lifestyleAboutEdit);
      expect(profileSectionRoute(7), RouteNames.familyDetailsEdit);
      expect(profileSectionRoute(8), RouteNames.horoscopeDetailsEdit);
      expect(profileSectionRoute(9), RouteNames.psychologyQuiz);
      expect(profileSectionRoute(10), RouteNames.partnerPreferences);
      expect(profileSectionRoute(11), RouteNames.photosEdit);
      expect(profileSectionRoute(12), RouteNames.verification);
    });
  });

  testWidgets('a saved section returns to Edit Profile, showing the change', (
    tester,
  ) async {
    final harness = EditProfileHarness();
    await harness.pump(tester);
    await harness.open(tester, RouteNames.editProfile);

    await tapPencil(tester, 'location');
    // State first: changing it clears the city, which is then re-picked.
    await pickLocation(tester, 'State', 'Gujarat');
    await pickLocation(tester, 'City', 'Bhavnagar');
    await tapSave(tester);

    expect(find.byType(EditProfilePage), findsOneWidget);
    expect(find.text(AppLocalizationsEnLabels.updated), findsOneWidget);
    for (final value in ['Bhavnagar', 'Gujarat', 'India']) {
      expect(
        find.descendant(of: row('location'), matching: find.text(value)),
        findsOneWidget,
      );
    }
    expect(find.text('Chennai'), findsNothing);
    expect(harness.repository.savedSections, ['locationDetails']);
  });

  group('the old all-in-one editor is gone', () {
    test('no page, route or navigation to it remains', () {
      expect(
        File(
          'lib/features/registration/presentation/pages/profile_edit_page.dart',
        ).existsSync(),
        isFalse,
      );
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final code = entity.readAsStringSync();
        expect(code, isNot(contains('ProfileEditPage(')), reason: entity.path);
        expect(code, isNot(contains("'/profile-edit'")), reason: entity.path);
        expect(
          code,
          isNot(contains('RouteNames.profileEdit')),
          reason: entity.path,
        );
      }
    });
  });

  group('the end-of-registration review', () {
    testWidgets('editing a section there keeps the registration in CREATE '
        'mode and does not re-fetch its draft', (tester) async {
      final harness = EditProfileHarness();
      await harness.pump(tester, mode: ProfileFlowMode.create);

      await harness.open(tester, profileSectionRoute(0));
      expect(find.byType(BasicInfoEditPage), findsOneWidget);
      expect(find.text('Meera'), findsOneWidget);
      expect(harness.repository.getDraftCalls, 0);

      await tapSave(tester);
      expect(harness.repository.savedSections, ['basicDetails']);
      expect(
        harness.container.read(profileFlowModeProvider),
        ProfileFlowMode.create,
      );
    });
  });
}
