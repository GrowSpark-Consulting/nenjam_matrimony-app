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

  /// The email/password form. No longer the auth entry — Welcome Back and
  /// Sign Up are — but still the screen those two open for the email and
  /// password routes, so the working forms are reused rather than rebuilt.
  static const String loginForm = '/login/form';
  static const String otp = '/otp';
  static const String loginOtp = '/login-otp';
  static const String verifyEmail = '/verify-email';
  static const String verifyPhone = '/verify-phone';
  static const String forgotPassword = '/forgot-password';
  static const String registration = '/registration';
  static const String createProfileFor = '/create-profile-for';
  // ─── Onboarding (the screens between signup and Discover) ─────────
  static const String onboardingNameDob = '/registration/name';
  static const String onboardingReligion = '/registration/religion';
  static const String onboardingContact = '/registration/contact';
  static const String profileBasics = '/registration/profile-basics';
  static const String onboardingMarital = '/registration/marital-status';
  static const String onboardingEducation = '/registration/education';
  static const String onboardingIncome = '/registration/income';
  static const String onboardingPhotos = '/registration/photos';
  static const String onboardingAbout = '/registration/about';
  static const String onboardingVerifyMobile = '/registration/verify-mobile';
  static const String registrationWelcome = '/registration/welcome';
  // ─── Edit Profile: a section list, and one editor per section ─────
  static const String editProfile = '/edit-profile';
  static const String basicInfoEdit = '/edit-profile/basic-info';
  static const String religionCommunityEdit = '/edit-profile/religion';
  static const String locationEdit = '/edit-profile/location';
  static const String educationWorkEdit = '/edit-profile/education-work';
  static const String physicalDetailsEdit = '/edit-profile/physical';
  static const String lifestyleAboutEdit = '/edit-profile/lifestyle-about';
  static const String photosEdit = '/edit-profile/photos';
  static const String familyDetailsEdit = '/family-details';
  static const String horoscopeDetailsEdit = '/horoscope-details';
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
  static const String faceVerification = '/verification/face';
  static const String subscription = '/subscription';
  static const String membershipHistory = '/membership/history';
  static const String help = '/help';
  static const String supportTicketForm = '/help/ticket';
  static const String ticketHistory = '/help/tickets';
  static const String partnerProgramHelp = '/help/partner-program';
  static const String privacy = '/privacy';
  static const String partnerPreferences = '/partner-preferences';
  static const String interestsSent = '/interests-sent';
  static const String interestsReceived = '/interests-received';
  static const String shortlisted = '/shortlisted';
  static const String nearby = '/nearby';
  static const String profileViewers = '/profile-viewers';

  /// Base paths of the two id-carrying routes. The routes themselves are
  /// registered at [profileDetailPattern] / [chatDetailPattern] so the id is
  /// in the URL — a browser refresh, a copied link or a bookmark then still
  /// says *which* profile or conversation, instead of depending on the
  /// in-memory `extra` object a reload throws away.
  static const String profileDetail = '/profile-detail';
  static const String chatDetail = '/chat-detail';
  static const String profileDetailPattern = '$profileDetail/:profileId';
  static const String chatDetailPattern = '$chatDetail/:conversationId';

  /// Concrete locations for the two patterns above.
  static String profileDetailPath(String profileId) =>
      '$profileDetail/${Uri.encodeComponent(profileId)}';
  static String chatDetailPath(String conversationId) =>
      '$chatDetail/${Uri.encodeComponent(conversationId)}';

  /// Whether [location] is a Chat Detail / Profile Detail location, with or
  /// without an id segment.
  static bool isChatDetailLocation(String? location) =>
      location == chatDetail || (location?.startsWith('$chatDetail/') ?? false);
  static bool isProfileDetailLocation(String? location) =>
      location == profileDetail ||
      (location?.startsWith('$profileDetail/') ?? false);

  // ─── Relationship Intelligence (independent of registration) ──────
  static const String horoscopeMatching = '/horoscope-matching';

  // ─── Named Routes ───────────────────────────────────────────────
  static const String splashName = 'splash';
  static const String languageName = 'language';
  static const String authSelectionName = 'authSelection';
  static const String registrationLandingName = 'registrationLanding';
  static const String onboardingName = 'onboarding';
  static const String loginName = 'login';
  static const String loginFormName = 'loginForm';
  static const String otpName = 'otp';
  static const String loginOtpName = 'loginOtp';
  static const String verifyEmailName = 'verifyEmail';
  static const String verifyPhoneName = 'verifyPhone';
  static const String forgotPasswordName = 'forgotPassword';
  static const String registrationName = 'registration';
  static const String createProfileForName = 'createProfileFor';
  static const String onboardingNameDobName = 'onboardingNameDob';
  static const String onboardingReligionName = 'onboardingReligion';
  static const String onboardingContactName = 'onboardingContact';
  static const String profileBasicsName = 'profileBasics';
  static const String onboardingMaritalName = 'onboardingMarital';
  static const String onboardingEducationName = 'onboardingEducation';
  static const String onboardingIncomeName = 'onboardingIncome';
  static const String onboardingPhotosName = 'onboardingPhotos';
  static const String onboardingAboutName = 'onboardingAbout';
  static const String onboardingVerifyMobileName = 'onboardingVerifyMobile';
  static const String registrationWelcomeName = 'registrationWelcome';
  static const String editProfileName = 'editProfile';
  static const String basicInfoEditName = 'basicInfoEdit';
  static const String religionCommunityEditName = 'religionCommunityEdit';
  static const String locationEditName = 'locationEdit';
  static const String educationWorkEditName = 'educationWorkEdit';
  static const String physicalDetailsEditName = 'physicalDetailsEdit';
  static const String lifestyleAboutEditName = 'lifestyleAboutEdit';
  static const String photosEditName = 'photosEdit';
  static const String familyDetailsEditName = 'familyDetailsEdit';
  static const String horoscopeDetailsEditName = 'horoscopeDetailsEdit';
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
  static const String faceVerificationName = 'faceVerification';
  static const String subscriptionName = 'subscription';
  static const String membershipHistoryName = 'membershipHistory';
  static const String helpName = 'help';
  static const String supportTicketFormName = 'supportTicketForm';
  static const String ticketHistoryName = 'ticketHistory';
  static const String partnerProgramHelpName = 'partnerProgramHelp';
  static const String privacyName = 'privacy';
  static const String partnerPreferencesName = 'partnerPreferences';
  static const String interestsSentName = 'interestsSent';
  static const String interestsReceivedName = 'interestsReceived';
  static const String shortlistedName = 'shortlisted';
  static const String nearbyName = 'nearby';
  static const String profileViewersName = 'profileViewers';
  static const String profileDetailName = 'profileDetail';
  static const String chatDetailName = 'chatDetail';

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
    loginForm,
    createProfileFor,
    onboardingNameDob,
    onboardingReligion,
    onboardingContact,
    profileBasics,
    onboardingMarital,
    onboardingEducation,
    onboardingIncome,
    onboardingPhotos,
    onboardingAbout,
    onboardingVerifyMobile,
    otp,
    loginOtp,
    verifyEmail,
    verifyPhone,
    forgotPassword,
    registration,
    faceVerification,
  };
}
