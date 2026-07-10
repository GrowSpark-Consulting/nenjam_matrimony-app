/// Nenjam Matrimony — API Endpoint Constants
///
/// Centralized endpoint definitions. Backend-agnostic.
abstract final class ApiEndpoints {
  // ─── Authentication ──────────────────────────────────────────────
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String verifyOtp = '/auth/verify-otp';
  static const String resendOtp = '/auth/resend-otp';
  static const String refreshToken = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';

  // ─── Registration wizard (implemented — matches backend/apps/api/src/
  // modules/profiles) ────────────────────────────────────────────────
  static const String profileDraft = '/profiles/draft';
  static const String profileDraftBasicDetails = '/profiles/draft/basic-details';
  static const String profileDraftReligionDetails = '/profiles/draft/religion-details';
  static const String profileDraftLanguageDetails = '/profiles/draft/language-details';
  static const String profileDraftLocationDetails = '/profiles/draft/location-details';
  static const String profileDraftEducationDetails = '/profiles/draft/education-details';
  static const String profileDraftPhysicalDetails = '/profiles/draft/physical-details';
  static const String profileDraftLifestyleDetails = '/profiles/draft/lifestyle-details';
  static const String profileDraftFamilyDetails = '/profiles/draft/family-details';
  static const String profileDraftHoroscopeDetails = '/profiles/draft/horoscope-details';
  static const String profileDraftPartnerPreference = '/profiles/draft/partner-preference';
  static const String profileFinalize = '/profiles/finalize';
  static const String profileMe = '/profiles/me';

  // ─── Relationship Intelligence (Prompts / Psychology / Horoscope Compat) ──
  static const String profilePromptsBank = '/profiles/prompts/bank';
  static const String profilePromptsMe = '/profiles/prompts/me';
  static const String psychologyQuizActive = '/psychology/quiz/active';
  static const String psychologyQuizMe = '/psychology/quiz/me';
  static const String psychologyQuizSubmit = '/psychology/quiz/submit';
  static const String astroProfileMe = '/astro/profile/me';
  static String astroCompatibility(String targetUserId) =>
      '/astro/compatibility/$targetUserId';

  // ─── Profile (not yet implemented on the backend) ─────────────────
  static const String profile = '/profile';
  static const String profileUpdate = '/profile/update';
  static const String profilePhotos = '/profile/photos';
  static const String profilePreferences = '/profile/preferences';
  static const String profileCompletion = '/profile/completion';
  static const String profileVerification = '/profile/verification';
  static const String profileHoroscope = '/profile/horoscope';

  // ─── Search & Discovery ──────────────────────────────────────────
  static const String search = '/search';
  static const String searchFilters = '/search/filters';
  static const String discover = '/discover';
  static const String recommendations = '/recommendations';
  static const String aiMatches = '/ai/matches';

  // ─── Matches ─────────────────────────────────────────────────────
  static const String matches = '/matches';
  static const String matchInterest = '/matches/interest';
  static const String matchShortlist = '/matches/shortlist';
  static const String matchDecline = '/matches/decline';
  static const String matchViewed = '/matches/viewed';

  // ─── Chat ────────────────────────────────────────────────────────
  static const String conversations = '/chat/conversations';
  static const String messages = '/chat/messages';

  // ─── Notifications ───────────────────────────────────────────────
  static const String notifications = '/notifications';
  static const String notificationSettings = '/notifications/settings';
  static const String registerDevice = '/notifications/device';

  // ─── Subscription ────────────────────────────────────────────────
  static const String plans = '/subscription/plans';
  static const String subscribe = '/subscription/subscribe';
  static const String subscriptionStatus = '/subscription/status';

  // ─── Verification ────────────────────────────────────────────────
  static const String verifyId = '/verification/id';
  static const String verifyPhoto = '/verification/photo';
  static const String verificationStatus = '/verification/status';

  // ─── Settings ────────────────────────────────────────────────────
  static const String settings = '/settings';
  static const String privacySettings = '/settings/privacy';
  static const String deleteAccount = '/settings/delete-account';

  // ─── Support ─────────────────────────────────────────────────────
  static const String help = '/help';
  static const String faq = '/help/faq';
  static const String contactSupport = '/help/contact';
  static const String reportUser = '/help/report';
}
