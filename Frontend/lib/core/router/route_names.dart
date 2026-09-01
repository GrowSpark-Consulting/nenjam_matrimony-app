/// Nenjam Matrimony — Named Route Constants
///
/// All route paths and names used by GoRouter.
abstract final class RouteNames {
  // ─── Route Paths ─────────────────────────────────────────────────
  static const String splash = '/';
  static const String language = '/language';
  static const String authSelection = '/auth-selection';
  static const String registrationLanding = '/registration-landing';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String loginOtp = '/login-otp';
  static const String verifyEmail = '/verify-email';
  static const String verifyPhone = '/verify-phone';
  static const String forgotPassword = '/forgot-password';
  static const String registration = '/registration';
  static const String createProfileFor = '/create-profile-for';
  static const String registrationWelcome = '/registration/welcome';
  static const String registrationWizard = '/registration/wizard';
  static const String psychologyQuiz = '/registration/psychology-quiz';
  static const String profileReview = '/profile-review';
  static const String registrationCompleting = '/registration/completing';
  static const String registrationSuccess = '/registration/success';
  static const String discover = '/discover';
  static const String search = '/search';
  static const String matches = '/matches';
  static const String messages = '/messages';
  static const String notifications = '/notifications';
  static const String profile = '/profile';
  static const String profileMenu = '/profile-menu';
  static const String profileCompletion = '/profile-completion';
  static const String premium = '/premium';
  static const String settings = '/settings';
  static const String verification = '/verification';
  static const String subscription = '/subscription';
  static const String help = '/help';
  static const String supportTicketForm = '/help/ticket';
  static const String ticketHistory = '/help/tickets';
  static const String privacy = '/privacy';
  static const String about = '/about';
  static const String partnerPreferences = '/partner-preferences';
  static const String interestsSent = '/interests-sent';
  static const String interestsReceived = '/interests-received';
  static const String shortlisted = '/shortlisted';
  static const String nearby = '/nearby';
  static const String profileViewers = '/profile-viewers';
  static const String profileDetail = '/profile-detail';
  static const String chatDetail = '/chat-detail';

  // ─── Relationship Intelligence (independent of registration) ──────
  static const String profileIntelligence = '/profile-intelligence';
  static const String choosePrompt = '/profile-prompts/choose';
  static const String horoscopeMatching = '/horoscope-matching';

  // ─── Named Routes ───────────────────────────────────────────────
  static const String splashName = 'splash';
  static const String languageName = 'language';
  static const String authSelectionName = 'authSelection';
  static const String registrationLandingName = 'registrationLanding';
  static const String onboardingName = 'onboarding';
  static const String loginName = 'login';
  static const String otpName = 'otp';
  static const String loginOtpName = 'loginOtp';
  static const String verifyEmailName = 'verifyEmail';
  static const String verifyPhoneName = 'verifyPhone';
  static const String forgotPasswordName = 'forgotPassword';
  static const String registrationName = 'registration';
  static const String createProfileForName = 'createProfileFor';
  static const String registrationWelcomeName = 'registrationWelcome';
  static const String registrationWizardName = 'registrationWizard';
  static const String psychologyQuizName = 'psychologyQuiz';
  static const String profileReviewName = 'profileReview';
  static const String registrationCompletingName = 'registrationCompleting';
  static const String registrationSuccessName = 'registrationSuccess';
  static const String discoverName = 'discover';
  static const String searchName = 'search';
  static const String matchesName = 'matches';
  static const String messagesName = 'messages';
  static const String notificationsName = 'notifications';
  static const String profileName = 'profile';
  static const String profileMenuName = 'profileMenu';
  static const String profileCompletionName = 'profileCompletion';
  static const String premiumName = 'premium';
  static const String settingsName = 'settings';
  static const String verificationName = 'verification';
  static const String subscriptionName = 'subscription';
  static const String helpName = 'help';
  static const String supportTicketFormName = 'supportTicketForm';
  static const String ticketHistoryName = 'ticketHistory';
  static const String privacyName = 'privacy';
  static const String aboutName = 'about';
  static const String partnerPreferencesName = 'partnerPreferences';
  static const String interestsSentName = 'interestsSent';
  static const String interestsReceivedName = 'interestsReceived';
  static const String shortlistedName = 'shortlisted';
  static const String nearbyName = 'nearby';
  static const String profileViewersName = 'profileViewers';
  static const String profileDetailName = 'profileDetail';
  static const String chatDetailName = 'chatDetail';

  static const String profileIntelligenceName = 'profileIntelligence';
  static const String choosePromptName = 'choosePrompt';
  static const String horoscopeMatchingName = 'horoscopeMatching';

  // ─── Query Parameters ───────────────────────────────────────────────

  /// Marks a route as having been opened by a notification tap, so the page
  /// knows to send Back to the Notification Center when there is nothing on
  /// the stack beneath it. A query parameter rather than `extra` because it
  /// has to survive the restoration path a cold-start tap takes.
  static const String openedFromNotificationParam = 'openedFromNotification';

  // ─── Auth Guard ─────────────────────────────────────────────────────
  //
  // Screens reachable without an active Firebase session — everything else
  // is treated as protected by GoRouter's redirect (see app_router.dart)
  // and by NenjamMatrimonyApp's resume check (see main.dart). Single
  // source of truth so the two never drift apart.
  static const Set<String> publicRoutes = {
    splash,
    language,
    authSelection,
    registrationLanding,
    onboarding,
    login,
    otp,
    loginOtp,
    verifyEmail,
    verifyPhone,
    forgotPassword,
    registration,
  };
}
