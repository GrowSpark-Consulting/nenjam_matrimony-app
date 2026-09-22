/// Nenjam Matrimony — API Endpoint Constants
///
/// Centralized endpoint definitions. Backend-agnostic.
abstract final class ApiEndpoints {
  // ─── Authentication ──────────────────────────────────────────────

  /// Unauthenticated: asked by the signup Email + Mobile step before an
  /// account exists, so it cannot carry a token.
  static const String accountExists = '/auth/account-exists';

  /// Unauthenticated: exchanges a passed dummy OTP for a real Firebase custom
  /// token. Called from the OTP screens, which run before the member has any
  /// credential — see `DummyOtpSessionService` on the backend.
  static const String dummyOtpSession = '/auth/dummy-otp/session';

  // ─── Registration wizard (implemented — matches backend/apps/api/src/
  // modules/profiles) ────────────────────────────────────────────────
  static const String profileDraft = '/profiles/draft';
  static const String profileDraftBasicDetails =
      '/profiles/draft/basic-details';
  static const String profileDraftReligionDetails =
      '/profiles/draft/religion-details';
  static const String profileDraftLanguageDetails =
      '/profiles/draft/language-details';
  static const String profileDraftLocationDetails =
      '/profiles/draft/location-details';
  static const String profileDraftEducationDetails =
      '/profiles/draft/education-details';
  static const String profileDraftPhysicalDetails =
      '/profiles/draft/physical-details';
  static const String profileDraftLifestyleDetails =
      '/profiles/draft/lifestyle-details';
  static const String profileDraftFamilyDetails =
      '/profiles/draft/family-details';
  static const String profileDraftHoroscopeDetails =
      '/profiles/draft/horoscope-details';
  static const String profileDraftPartnerPreference =
      '/profiles/draft/partner-preference';
  static const String profileFinalize = '/profiles/finalize';

  /// "Complete Your Profile" recommendation dismissals — hides a card from
  /// Home and Edit Profile without touching the data behind it. POST a
  /// `{ cardKey }` to hide, DELETE the keyed route to bring it back. The
  /// cards themselves ride on [profileDraft]'s `recommendations`, so no
  /// screen needs a second fetch to draw them.
  static const String profileCompletionDismissals =
      '/profiles/completion/dismissals';
  static String profileCompletionDismissal(String cardKey) =>
      '/profiles/completion/dismissals/$cardKey';
  static const String profileMe = '/profiles/me';

  /// Real, implemented route (backend/apps/api/src/modules/matches/
  /// controllers/nearby.controller.ts). Proximity search: pass `latitude`,
  /// `longitude` and an optional `radiusKm` (max 100). Returns the shared
  /// Discover card shape with `distanceKm` filled in, never other members'
  /// coordinates. Mounted under `profiles` on the backend, hence its place
  /// here rather than under Search & Discovery below.
  static const String profilesNearby = '/profiles/nearby';

  /// Stores the caller's own device coordinates so other members' Near Me
  /// searches can find them (backend ProfileController.updateLocation). PUT —
  /// one location per member, replaced wholesale.
  static const String profileMeLocation = '/profiles/me/location';

  // ─── Relationship Intelligence (Prompts / Psychology / Horoscope Compat) ──
  static const String profilePromptsBank = '/profiles/prompts/bank';
  static const String profilePromptsMe = '/profiles/prompts/me';

  /// `DELETE /profiles/prompts/me/:promptId` — removes one saved prompt
  /// answer (backend/apps/api/src/modules/profiles' PromptsController
  /// `deleteMine`). [promptId] is the prompt-bank id (`PromptAnswer.promptId`),
  /// not the row's own database id — the backend deletes by
  /// `(userId, promptId)`, which is unique per the schema's
  /// `@@unique([userId, promptId])`.
  static String profilePromptDelete(String promptId) =>
      '/profiles/prompts/me/$promptId';
  static const String psychologyQuizActive = '/psychology/quiz/active';
  static const String psychologyQuizMe = '/psychology/quiz/me';
  static const String psychologyQuizSubmit = '/psychology/quiz/submit';
  static const String astroProfileMe = '/astro/profile/me';
  static String astroCompatibility(String targetUserId) =>
      '/astro/compatibility/$targetUserId';

  // ─── Profile photos ────────────────────────────────────────────
  // Photo management — backend/apps/api/src/modules/profiles' PhotoController
  // (all user-scoped via FirebaseAuthGuard). List + upload live at the base;
  // per-photo routes append the id.
  static const String profilePhotos = '/profiles/me/photos';
  static const String profilePhotosReorder = '/profiles/me/photos/reorder';
  static String profilePhoto(String id) => '/profiles/me/photos/$id';
  static String profilePhotoPrimary(String id) =>
      '/profiles/me/photos/$id/primary';

  // ─── Reference data (location master data) ───────────────────────
  /// Unauthenticated by design: the location step runs during registration,
  /// before a session necessarily exists. These return ISO 3166 codes and
  /// city names — identical for every caller, nothing user-specific.
  static const String referenceCountries = '/reference-data/countries';
  static const String referenceStates = '/reference-data/states';
  static const String referenceCities = '/reference-data/cities';

  /// Religion → Community, the second reference-data cascade. Unauthenticated
  /// for the same reason: the Religion step runs before auth, which is the
  /// last onboarding step. These are the lists the app used to ship in its
  /// own binary, so there is nothing here a caller could not already see.
  static const String referenceReligions = '/reference-data/religions';
  static const String referenceCommunities = '/reference-data/communities';

  // ─── Search & Discovery ──────────────────────────────────────────
  static const String discover = '/discover';

  /// Server-side profile search (backend/apps/api/src/modules/matches/
  /// controllers/discover.controller.ts `search()`). Takes `q`, `page` and
  /// `limit` — and nothing else. It returns the same envelope as [discover],
  /// so the client parses both with one model.
  ///
  /// Mounted under `discover` rather than a top-level `/search`: the search
  /// strategy shares `buildFeedWhere` with the feed, so results are subject
  /// to the identical eligibility rules (opposite gender, saved partner
  /// preferences, and exclusion of deleted/suspended/blocked/incomplete
  /// profiles). It is the feed, narrowed by a term — not a separate index.
  static const String discoverSearch = '/discover/search';

  /// The saved-partner-preference CRUD pair (`DiscoverController.getPreferences`
  /// / `.updatePreferences`, backed by `PreferencesService` and the
  /// `partner_preferences` table). This — not the registration draft's
  /// `PATCH /profiles/draft/partner-preference` — is the source of truth for
  /// the 10 base preference fields (age/height/religion/caste/education/
  /// occupation/income/location/motherTongue/maritalStatus): it is what the
  /// Discover/Search feed filter and the compatibility scorer actually read.
  /// See `features/partner_preferences/data/repositories/
  /// partner_preferences_repository_impl.dart` for the exact field mapping.
  static const String discoverPreferences = '/discover/preferences';

  // ─── Matches ─────────────────────────────────────────────────────
  static const String matches = '/matches';
  static const String matchInterest = '/matches/interest';
  static const String matchShortlist = '/matches/shortlist';
  static const String matchDecline = '/matches/decline';
  static const String matchViewed = '/matches/viewed';

  // Real, implemented routes (backend/apps/api/src/modules/matches/
  // controllers/matches.controller.ts). `matchProfileViews` lists who viewed
  // me; `matchProfileView` records that I opened someone's profile.
  static const String matchProfileViews = '/matches/profile-views';
  static const String matchProfileView = '/matches/profile-view';

  // ─── Interests (proposed — no backend route defined yet; the
  // `interests` backend module exists but is an empty stub) ──────────
  static const String interestsReceived = '/interests/received';
  static const String interestsSent = '/interests/sent';
  // Base resource path for a single interest record — proposed
  // `DELETE {interests}/:id` to withdraw a pending sent interest.
  static const String interests = '/interests';

  // ─── Chat ────────────────────────────────────────────────────────
  static const String conversations = '/chat/conversations';
  static const String messages = '/chat/messages';

  /// Proposed — no chat attachment-upload endpoint exists on the backend
  /// yet (see docs/development/chat-backend-handoff.md, §5.8). Used by
  /// `ConversationApiRepositoryImpl.uploadVoiceAttachment` so that call is
  /// real code ready to work the moment this endpoint ships, rather than
  /// something invented and faked client-side.
  static const String chatAttachmentUpload = '/chat/attachments';

  // ─── Notifications ───────────────────────────────────────────────
  static const String notifications = '/notifications';
  static const String registerDevice = '/notifications/device';

  // ─── Verification (document-backed: income/asset/aadhaar/nri) ──────
  // backend/apps/api/src/modules/verification is scaffolded but its
  // controller/service/DTO bodies are still empty — no routes registered
  // yet (see VerificationRepositoryImpl's header comment). Mobile/email
  // verification are NOT here — they reflect the existing Firebase auth
  // session directly, not a submitted document.
  // Retry re-uses the same submit endpoint with a freshly picked file —
  // there's nothing meaningful to "retry" without new evidence, and we
  // deliberately don't cache the previous file client-side (see security
  // notes on VerificationStatusesController).
  static const String verificationDocuments = '/verification/documents';
  static const String verificationStatus = '/verification/status';

  // ─── Face verification (selfie liveness + compare-faces; AWS Rekognition
  // via backend/apps/api/src/modules/verification's real, wired-in
  // controller — see docs/development/selfie-verification-frontend-handoff.md).
  // Ships with FACE_VERIFICATION_ENABLED=false; every call 503s with code
  // NOT_AVAILABLE until the backend team turns it on.
  static const String faceVerification = '/verification/face';
  static const String faceVerificationSessions = '/verification/face/sessions';
  static const String faceVerificationComplete = '/verification/face/complete';

  // ─── Settings ────────────────────────────────────────────────────
  static const String settings = '/settings';
  static const String privacySettings = '/settings/privacy';
  static const String deleteAccount = '/settings/delete-account';

  // ─── Support ─────────────────────────────────────────────────────

  /// Support tickets — POST to submit, GET for the caller's history.
  static const String supportTickets = '/support/tickets';

  // ─── Safety (Block / Report — backend/apps/api/src/modules/blocks and
  // /reports; both keyed by the target member's user id) ────────────
  static String blockUser(String userId) => '/users/$userId/block';
  static String reportUser(String userId) => '/users/$userId/report';
  static const String blockedUsers = '/users/blocked';
}
