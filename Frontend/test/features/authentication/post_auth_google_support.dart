import 'package:firebase_auth/firebase_auth.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/firebase_auth_service.dart';

/// Fixtures for the Google routing tests.
///
/// A Google session is a specific shape — an address Google has already
/// vouched for, no phone credential, and an account that may be seconds old
/// — and the resolver has branches for each of those. Building it here keeps
/// the flow tests about routing rather than about impersonating Firebase.

/// A signed-in Google account.
///
/// `emailVerified` is true because Google asserts the address: that is what
/// makes the verify-email gate evaluate false and lets the routing under test
/// be reached at all. [establishedAt] separates a returning member from one
/// who signed up moments ago — the resolver consults that only as a fallback
/// when the backend cannot be reached.
class GoogleSignedInAuthService implements FirebaseAuthService {
  GoogleSignedInAuthService({this.brandNew = false, this.contactable = true});

  /// Creation and last-sign-in within the resolver's two-minute window, i.e.
  /// an account whose very first sign-in this is.
  final bool brandNew;

  /// Whether the account carries a mobile number.
  ///
  /// The Email + Mobile step sits in the middle of onboarding, and the
  /// resolver gates on it for any signup that is not yet finished. A member
  /// resuming at a step *after* it has necessarily answered it, so that is
  /// the default here — otherwise every later-step test would be measuring
  /// the contact gate instead of the step it means to.
  final bool contactable;

  @override
  User? get currentUser =>
      GoogleUser(brandNew: brandNew, contactable: contactable);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class GoogleUser implements User {
  GoogleUser({bool brandNew = false, bool contactable = true})
      : phoneNumber = contactable ? '+919876543210' : '',
        metadata = _Metadata(
          DateTime(2024, 6, 1),
          brandNew ? DateTime(2024, 6, 1) : DateTime(2026, 1, 1),
        );

  @override
  String get uid => 'google-uid-1';

  /// Google always supplies one, and it is always verified.
  @override
  final String? email = 'arjun@gmail.com';

  @override
  final bool emailVerified = true;

  /// Set from `contactable`. Empty models a signup that has not yet reached
  /// the Email + Mobile step.
  @override
  final String? phoneNumber;

  @override
  final UserMetadata metadata;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Metadata implements UserMetadata {
  _Metadata(this.creationTime, this.lastSignInTime);

  @override
  final DateTime? creationTime;
  @override
  final DateTime? lastSignInTime;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What `GET /profiles/draft` returns for an account the backend has just
/// created: a row exists, and every section is absent.
Map<String, dynamic> emptyDraft() => <String, dynamic>{
      'currentStep': 0,
      'isComplete': false,
      'data': <String, dynamic>{},
    };

/// A fully answered onboarding draft, with any field settable to `''` to
/// model a member who stopped at that step.
///
/// Mirrors what the Google signup path actually writes: Profile For and
/// gender first, then name and date of birth, then religion, then the
/// "Let's build your Profile" step's state/city/caste/mother tongue, and so
/// on — the same sequence the mobile and email signups walk.
Map<String, dynamic> googleDraft({
  String relation = 'Myself',
  String gender = 'MALE',
  String firstName = 'Arjun',
  String lastName = 'Krishnan',
  String dob = '1994-06-18T00:00:00.000Z',
  String maritalStatus = 'Never Married',
  String religion = 'Hindu',
  String caste = 'Vellalar',
  String community = 'Vellalar',
  String motherTongue = 'Tamil',
  String livingIn = 'India',
  String state = 'Tamil Nadu',
  String city = 'Chennai',
  String height = '5\'9" (175 cm)',
  String qualification = 'B.E / B.Tech',
  String annualIncome = '10 - 20 Lakhs',
  String aboutMe = 'A short description.',
}) {
  Map<String, dynamic> section(Map<String, String> fields) => {
        for (final e in fields.entries)
          if (e.value.isNotEmpty) e.key: e.value,
      };

  return <String, dynamic>{
    'currentStep': 0,
    'isComplete': false,
    'data': <String, dynamic>{
      'basicDetails': section({
        'profileCreatedFor': relation,
        'gender': gender,
        'firstName': firstName,
        'lastName': lastName,
        'dob': dob,
        'maritalStatus': maritalStatus,
      }),
      'religionDetails': section({
        'religion': religion,
        'caste': caste,
        'community': community,
      }),
      'languageDetails': section({'motherTongue': motherTongue}),
      'locationDetails': section({
        'country': livingIn,
        'state': state,
        'city': city,
      }),
      'physicalDetails': section({'height': height}),
      'educationDetails': section({
        'qualification': qualification,
        'annualIncome': annualIncome,
      }),
      'lifestyleDetails': section({'aboutMe': aboutMe}),
    },
  };
}
