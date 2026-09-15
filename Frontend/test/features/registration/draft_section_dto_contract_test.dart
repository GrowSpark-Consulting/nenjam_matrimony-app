import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';

/// The wire contract between each draft section model and the NestJS DTO that
/// guards its `PATCH /profiles/draft/<section>` endpoint.
///
/// The backend runs one global `ValidationPipe({ whitelist: true,
/// forbidNonWhitelisted: true })` (backend/apps/api/src/main.ts). Under
/// `forbidNonWhitelisted`, a body carrying ONE property the DTO does not
/// declare is not trimmed — the whole request is rejected 400. So a field
/// added to a model here and not to its DTO does not degrade gracefully; it
/// takes the entire section down.
///
/// That is not hypothetical. `5b83562` gave [LocationDetails] the master-data
/// `countryCode`/`stateCode`/`cityCode` and taught `toJson` to send them, but
/// `LocationDetailsDto` never declared them — even though
/// `ProfileService.writeProfileFromDraft` already read all three to connect
/// `countryRef`/`stateRef`/`cityRef`. Every location PATCH 400ed from that day
/// on.
///
/// The damage came from where that call sits. Phone signup has no session
/// until the OTP step, so `flushOnboardingToBackend` is the only writer, and
/// it sends sections in order inside one `try`. Location is 4th of 7; the
/// throw skipped the remaining three — including the single call that runs
/// with `skipMaterialize: false` and therefore the only one that materialises
/// `user_profiles`. Members finished registration with no profile row at all,
/// `registration_steps.current_step` frozen at 2, and Discover correctly
/// reporting `INCOMPLETE_SELF_PROFILE` to a brand-new account.
///
/// These read the real DTO files, so they fail on the drift itself rather
/// than on a copy of it that could rot in the opposite direction.
void main() {
  const dtoDir = '../backend/apps/api/src/modules/profiles/dto';

  /// The property names a DTO declares, e.g. `stateCode?: string;` -> stateCode.
  Set<String> declaredProperties(String dtoFile) {
    final file = File('$dtoDir/$dtoFile');
    expect(
      file.existsSync(),
      isTrue,
      reason: '$dtoFile not found — has the backend moved? ${file.absolute}',
    );
    final body = file.readAsStringSync();
    return RegExp(r'^\s{2}(\w+)\??\s*:\s*[\w\[\]<>| ]+;', multiLine: true)
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet();
  }

  void expectAccepted(
    String label,
    Map<String, dynamic> payload,
    String dtoFile,
  ) {
    final declared = declaredProperties(dtoFile);
    expect(declared, isNotEmpty, reason: 'parsed no properties from $dtoFile');

    final undeclared = payload.keys.toSet().difference(declared);
    expect(
      undeclared,
      isEmpty,
      reason:
          '$label sends $undeclared, which $dtoFile does not declare. Under '
          'forbidNonWhitelisted the whole PATCH is rejected 400 — not just '
          'these fields. Add them to the DTO or stop sending them.',
    );
  }

  test('LocationDetails — the section that broke registration', () {
    // Every field populated, so `toJson`'s `if (x.isNotEmpty)` guards all pass
    // and the payload is the widest one the app can actually send.
    final payload = const LocationDetails(
      country: 'India',
      state: 'Tamil Nadu',
      city: 'Chennai',
      area: 'Adyar',
      pinCode: '600020',
      nativePlace: 'Madurai',
      countryCode: 'IN',
      stateCode: 'IN-TN',
      cityCode: 'IN-TN-CHE',
    ).toJson();

    // Guards the regression directly: the three codes must survive.
    expect(payload.keys, containsAll(['countryCode', 'stateCode', 'cityCode']));
    expectAccepted('LocationDetails', payload, 'location-details.dto.ts');
  });

  test('every section flushOnboardingToBackend sends is accepted', () {
    // The exact seven calls, in the order flushOnboardingToBackend makes them.
    // A 400 on any one of them silently drops every section after it.
    final sections = <String, (Map<String, dynamic>, String)>{
      'BasicDetails': (
        BasicDetails(
          firstName: 'Arjun',
          lastName: 'Krishnan',
          gender: 'Male',
          dob: DateTime(1996, 4, 12),
          maritalStatus: 'Never Married',
          profileCreatedFor: 'Myself',
        ).toJson(),
        'basic-details.dto.ts',
      ),
      'ReligionDetails': (
        const ReligionDetails(
          religion: 'Hindu',
          caste: 'Iyer',
          subCaste: 'Vadama',
          gothra: 'Bharadwaj',
          denomination: '',
          community: 'Brahmin',
        ).toJson(),
        'religion-details.dto.ts',
      ),
      'LanguageDetails': (
        const LanguageDetails(
          motherTongue: 'Tamil',
          languagesKnown: ['Tamil', 'English'],
        ).toJson(),
        'language-details.dto.ts',
      ),
      'PhysicalDetails': (
        const PhysicalDetails(
          height: "5'8\"",
          weight: '70 kg',
          bloodGroup: 'O+',
          disability: 'None',
        ).toJson(),
        'physical-details.dto.ts',
      ),
      'EducationDetails': (
        const EducationDetails(
          qualification: 'B.E',
          college: 'Anna University',
          occupation: 'Engineer',
          company: 'Zoho',
          employmentType: 'Private',
          workIndustry: 'Software',
          annualIncome: '12 Lakhs',
          workLocation: 'Chennai',
        ).toJson(),
        'education-details.dto.ts',
      ),
      'LifestyleDetails': (
        const LifestyleDetails(
          eatingHabit: 'Vegetarian',
          smoking: 'No',
          drinking: 'No',
          fitness: 'Regular',
          hobbies: ['Reading'],
          aboutMe: 'Hello.',
        ).toJson(),
        'lifestyle-details.dto.ts',
      ),
    };

    sections.forEach((label, entry) {
      expectAccepted(label, entry.$1, entry.$2);
    });
  });
}
