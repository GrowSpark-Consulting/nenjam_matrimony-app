import 'profile_for_relation.dart';

/// Whether a profile owes the selfie (face) verification step.
///
/// Business rule: only a member who chose **Myself** on "Who is this profile
/// for?" is asked for a selfie. Son, Daughter, Brother, Sister, Friend,
/// Relative, any value this build does not recognise, and a profile created
/// for the member by a referral partner ([referralCreated]) are all exempt.
///
/// **Referral paths treated as "referral-created"** ([referralCreated]):
///  1. an agent-added client who accepted an invitation (stored by the backend
///     as `Myself`, so the relation alone cannot exempt her);
///  2. a member whose referral code attached (`POST /registration/referral-code`
///     answered 200 or `409 ALREADY_ATTRIBUTED`);
///  3. a member who arrived by referral link — a link only pre-fills the same
///     code, so it ends in path 2.
/// This is a product reading of "referral/invitation flow"; narrowing it to
/// path 1 is a one-line change in `referral_providers.dart`.
///
/// **Backend dependency.** The backend records the attribution
/// (`ReferralAttribution.source`: ADDED_BY_AGENT / CODE_AT_SIGNUP /
/// LINK_OR_QR) but exposes no member-facing read of it, so [referralCreated]
/// comes from a device-local marker written only after the backend confirmed
/// attribution. It is a fallback: it is lost on reinstall or a new device,
/// where such a Myself member would be gated again. A field on `/profiles/me`
/// or the draft would replace it; nothing here invents that response.
///
/// [profileCreatedFor] is the canonical stored answer
/// (`BasicDetails.profileCreatedFor`) and the only input about ownership —
/// nothing is inferred from a name or phone number. An empty/unanswered value
/// is not "Myself", so it is not required either; the "profile is for" step
/// itself is what collects the answer.
///
/// Pure and synchronous so every caller (the post-auth gate, the profile tile,
/// the Verification Center, the face page) applies the same rule.
bool selfieVerificationRequired({
  required String? profileCreatedFor,
  bool referralCreated = false,
}) {
  if (referralCreated) return false;
  return ProfileForRelation.fromStorage(profileCreatedFor) ==
      ProfileForRelation.myself;
}
