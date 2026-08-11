// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Nenjam Matrimony';

  @override
  String get commonContinue => 'Continue';

  @override
  String get splashTagline => 'Where Hearts Meet';

  @override
  String get languageChooseTitle => 'Choose your Language';

  @override
  String get languageChooseSubtitle =>
      'Select your preferred language for matchmaking';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTamil => 'Tamil';

  @override
  String get authTagline => 'FIND YOUR FOREVER';

  @override
  String get authWelcomeTitle => 'Welcome to Nenjam Matrimony';

  @override
  String get authWelcomeSubtitle =>
      'Experience a premier matrimonial journey curated exclusively for discerning individuals seeking lifelong companionship.';

  @override
  String get authLogin => 'Login';

  @override
  String get authCreateAccount => 'Create Account';

  @override
  String get authWelcomeBack => 'Welcome Back';

  @override
  String get authJoinCommunity => 'Join Nenjam Matrimony\'s Elite Community';

  @override
  String get authSignUp => 'Sign Up';

  @override
  String get authChannelMobile => 'Mobile';

  @override
  String get authChannelEmail => 'Email';

  @override
  String get authPhoneNumber => 'Phone Number';

  @override
  String get authEmailAddress => 'Email Address';

  @override
  String get authPassword => 'Password';

  @override
  String get authForgotPassword => 'Forgot Password?';

  @override
  String get authLoginWithOtp => 'Login with OTP';

  @override
  String get authOrContinueWith => 'or continue with';

  @override
  String get authSignInWithGoogle => 'Sign in with Google';

  @override
  String get authNewHere => 'New here? ';

  @override
  String get authAlreadyHaveAccount => 'Already have an account? ';

  @override
  String get authMobileNumber => 'Mobile Number';

  @override
  String get authEnterMobileOtp => 'Enter Mobile OTP';

  @override
  String get authEnterEmailOtp => 'Enter Email OTP';

  @override
  String get authRegisteringForLabel => 'Registering for';

  @override
  String get authSendOtp => 'Send OTP';

  @override
  String get authSentStatus => 'Sent';

  @override
  String get authErrorValidMobile =>
      'Please enter valid 10-digit mobile number and details';

  @override
  String get authTrustSecure => 'SECURE';

  @override
  String get authTrustPrivate => 'PRIVATE';

  @override
  String get authTrustVerified => 'VERIFIED';

  @override
  String get authRegForMyself => 'Myself';

  @override
  String get authRegForSon => 'Son';

  @override
  String get authRegForDaughter => 'Daughter';

  @override
  String get authRegForBrother => 'Brother';

  @override
  String get authRegForSister => 'Sister';

  @override
  String get authRegForFriend => 'Friend';

  @override
  String get authVerifyMobile => 'Verify Mobile';

  @override
  String get authVerifyEmail => 'Verify Email';

  @override
  String get authEnterVerificationCode => 'Enter Verification Code';

  @override
  String authOtpSentTo(String target) {
    return 'We sent a 6-digit code to $target';
  }

  @override
  String get authVerifyAndContinue => 'Verify & Continue';

  @override
  String get authResendOtpIn => 'Resend OTP in';

  @override
  String get authResendOtp => 'Resend OTP';

  @override
  String get authUsername => 'Username';

  @override
  String get authUsernameHint => 'e.g. arun_kumar';

  @override
  String get authPasswordHint =>
      'Min 8 chars with upper, lower, number & symbol';

  @override
  String get authPasswordRequired => 'Please enter your password';

  @override
  String get authComingSoon => 'Coming soon';

  @override
  String get authGenericError => 'Something went wrong. Please try again.';

  @override
  String get authLogoutConfirm => 'Are you sure you want to log out?';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get authVerifyEmailTitle => 'Verify your email';

  @override
  String authVerifyEmailSentTo(String email) {
    return 'We sent a verification link to $email';
  }

  @override
  String get authVerifyEmailInstruction =>
      'Open the link in your inbox to verify your email, then come back here.';

  @override
  String get authIveVerified => 'I\'ve verified';

  @override
  String get authResendEmail => 'Resend email';

  @override
  String authResendEmailIn(String seconds) {
    return 'Resend email in ${seconds}s';
  }

  @override
  String get authEmailNotVerifiedYet =>
      'Email not verified yet. Please tap the link in your inbox.';

  @override
  String get authEmailVerifiedSuccess => 'Email verified!';

  @override
  String get authVerificationEmailSent => 'Verification email sent.';

  @override
  String get authVerifyPhoneTitle => 'Verify your phone';

  @override
  String get authSendingOtp => 'Sending OTP…';

  @override
  String get authPhoneVerifiedSuccess => 'Phone verified!';

  @override
  String get authForgotPasswordTitle => 'Forgot Password';

  @override
  String get authForgotPasswordSubtitle =>
      'Enter your registered email and we\'ll send you a link to reset your password.';

  @override
  String get authSendResetLink => 'Send Reset Link';

  @override
  String get authBackToLogin => 'Back to login';

  @override
  String get authResetEmailSentTitle => 'Check your email';

  @override
  String get authResetEmailSent =>
      'Password reset link has been sent to your email';

  @override
  String get navHome => 'Home';

  @override
  String get navSearch => 'Search';

  @override
  String get navMatches => 'Matches';

  @override
  String get navChat => 'Chat';

  @override
  String get navProfile => 'Profile';

  @override
  String get homeCompleteProfileTitle => 'Complete Your Profile';

  @override
  String homeProfileNextStep(String step) {
    return 'Next: $step';
  }

  @override
  String get homeStepAddPhoto => 'Add profile photo';

  @override
  String get homeAiPickBadge => 'AI Pick';

  @override
  String get discoverAiMatchLabel => 'match';

  @override
  String get discoverNewTodayLabel => 'New Today';

  @override
  String get discoverSearchingMoreLabel => 'Searching for more souls…';

  @override
  String get discoverFallbackBannerLabel =>
      'We widened your preferences slightly to show more matches.';

  @override
  String get discoverVerifiedLabel => 'Verified';

  @override
  String get discoverPremiumLabel => 'Premium';

  @override
  String get homePsychologyCompletedLabel => 'Psychology Completed';

  @override
  String get discoverChipVerifiedIdentity => 'Verified Identity';

  @override
  String get discoverChipPremiumPlus => 'Premium Plus';

  @override
  String get discoverChipNri => 'NRI';

  @override
  String get discoverChipBuildingProfile => 'Building Profile';

  @override
  String get homePhotoProtectedLabel => 'Photo Protected';

  @override
  String get discoverInterestSentLabel => 'Interest Sent';

  @override
  String get discoverRespondToInterest => 'Respond to Interest';

  @override
  String get homeAiMatchScoreLabel => 'AI Match';

  @override
  String get homeAstroMatchScoreLabel => 'Astro Match';

  @override
  String get homePsychologyMatchScoreLabel => 'Psychology Match';

  @override
  String get discoverCompatibilityLabel => 'Compatibility';

  @override
  String get actionInterested => 'Interested';

  @override
  String get actionViewProfile => 'View Profile';

  @override
  String get actionShare => 'Share';

  @override
  String get actionSave => 'Save';

  @override
  String get actionMessage => 'Message';

  @override
  String get discoverFilterLabel => 'Filter';

  @override
  String get homeProfileDetailsLabel => 'Details';

  @override
  String get navDiscover => 'Discover';

  @override
  String get navMessages => 'Inbox';

  @override
  String get navPremium => 'Premium';

  @override
  String get discoverForYouTab => 'For You';

  @override
  String get discoverNearMeTab => 'Near Me';

  @override
  String get discoverNewTab => 'New';

  @override
  String get appNameShort => 'Nenjam';

  @override
  String get discoverSearchTooltip => 'Search';

  @override
  String get discoverAiRecommendedTitle => 'AI Recommended';

  @override
  String get discoverRecentlyJoinedTitle => 'Recently Joined';

  @override
  String get discoverVerifiedProfilesTitle => 'Verified Profiles';

  @override
  String get discoverNearYouTitle => 'Near You';

  @override
  String get discoverPremiumMembersTitle => 'Premium Members';

  @override
  String get discoverViewAllButton => 'View All';

  @override
  String get discoverStatMatchLabel => 'Match';

  @override
  String get discoverStatAstroLabel => 'Astro';

  @override
  String get discoverStatTrustLabel => 'Trust';

  @override
  String get discoverUpgradeButton => 'Upgrade';

  @override
  String get discoverEliteMemberLabel => 'Elite Member';

  @override
  String get discoverConnectButton => 'Connect';

  @override
  String get matchesEmptyTitle => 'No matches yet';

  @override
  String get matchesEmptySubtitle => 'Check back soon for new profiles';

  @override
  String get matchesCategorySearch => 'Search';

  @override
  String get matchesCategoryNew => 'New';

  @override
  String get matchesCategoryDaily => 'Daily';

  @override
  String get matchesCategoryMyMatches => 'My Matches';

  @override
  String get matchesCategoryNearMe => 'Near Me';

  @override
  String get matchesCategoryMoreMatches => 'More Matches';

  @override
  String get discoverKmAwaySuffix => 'km away';

  @override
  String get premiumBannerTitle => 'Upgrade to Premium';

  @override
  String get premiumBannerSubtitle =>
      'Get unlimited access to profiles & AI matching';

  @override
  String get premiumBannerCta => 'Explore Plans';

  @override
  String get searchTitle => 'Discover Profiles';

  @override
  String get searchFilterVerifiedOnly => 'Verified Only';

  @override
  String get searchFilterNearMe => 'Near Me';

  @override
  String get searchFilterDoctor => 'Doctor';

  @override
  String get searchFilterEngineer => 'Engineer';

  @override
  String searchShowingMatches(String count) {
    return 'Showing $count Matches';
  }

  @override
  String get searchSortButton => 'Sort';

  @override
  String get searchHint => 'Name, Matrimony ID, City, Profession...';

  @override
  String get searchRecentTitle => 'Recent Searches';

  @override
  String get searchPopularTitle => 'Popular Searches';

  @override
  String get searchClearAll => 'Clear All';

  @override
  String get searchEmptyResultsTitle => 'No matching profiles found.';

  @override
  String get searchEmptyResultsSubtitle => 'Try changing your filters.';

  @override
  String get searchResetFiltersButton => 'Reset Filters';

  @override
  String get searchFilterSheetTitle => 'Filters';

  @override
  String get searchFilterReset => 'Reset';

  @override
  String get searchFilterApply => 'Apply Filters';

  @override
  String get searchFilterShowResults => 'Show Results';

  @override
  String get searchFilterSectionBasic => 'Basic';

  @override
  String get searchFilterSectionReligion => 'Religion';

  @override
  String get searchFilterSectionLocation => 'Location';

  @override
  String get searchFilterSectionEducation => 'Education';

  @override
  String get searchFilterSectionCareer => 'Career';

  @override
  String get searchFilterSectionLifestyle => 'Lifestyle';

  @override
  String get searchFilterSectionHoroscope => 'Horoscope';

  @override
  String get searchFilterSectionVerification => 'Verification';

  @override
  String get searchFilterSectionPremium => 'Premium';

  @override
  String get searchFilterSectionProfile => 'Profile';

  @override
  String get searchFilterAgeRange => 'Age Range';

  @override
  String get searchFilterGender => 'Gender';

  @override
  String get searchFilterGenderMale => 'Male';

  @override
  String get searchFilterGenderFemale => 'Female';

  @override
  String get searchFilterHeightMin => 'Min Height';

  @override
  String get searchFilterHeightMax => 'Max Height';

  @override
  String get searchFilterCommunity => 'Community';

  @override
  String get searchFilterState => 'State';

  @override
  String get searchFilterDiet => 'Diet';

  @override
  String get searchFilterSmoking => 'Smoking';

  @override
  String get searchFilterDrinking => 'Drinking';

  @override
  String get searchFilterRashi => 'Rashi';

  @override
  String get searchFilterStar => 'Star';

  @override
  String get searchFilterHoroscopeAvailable => 'Horoscope Available';

  @override
  String get searchFilterAadhaarVerified => 'Aadhaar Verified';

  @override
  String get searchFilterIncomeVerified => 'Income Verified';

  @override
  String get searchFilterNriVerified => 'NRI Verified';

  @override
  String get searchFilterPremiumOnly => 'Premium Members Only';

  @override
  String get searchFilterWithPhoto => 'With Photo';

  @override
  String get searchFilterCompletedProfile => 'Completed Profile';

  @override
  String get searchFilterOptionYes => 'Yes';

  @override
  String get searchFilterOptionNo => 'No';

  @override
  String get searchFilterOptionOccasionally => 'Occasionally';

  @override
  String get matchesTitle => 'My Matches';

  @override
  String matchesTabNew(String count) {
    return 'New ($count)';
  }

  @override
  String get matchesTabShortlisted => 'Shortlisted';

  @override
  String get matchesTabMutual => 'Mutual';

  @override
  String get matchesShortlistedEmpty => 'Shortlisted Profiles';

  @override
  String get matchesMutualEmpty => 'Mutual Likes';

  @override
  String get inboxTitle => 'Inbox';

  @override
  String get inboxNotificationsTooltip => 'Notifications';

  @override
  String get inboxFilterTooltip => 'Filters';

  @override
  String get inboxSearchHint => 'Search conversations...';

  @override
  String get inboxTabInterestsReceived => 'Received';

  @override
  String get inboxTabInterestsSent => 'Sent';

  @override
  String get inboxTabMessages => 'Messages';

  @override
  String get inboxEmptyTitle => 'No conversations yet';

  @override
  String get inboxEmptySubtitle =>
      'Start discovering matches to begin a conversation.';

  @override
  String get inboxEmptyCta => 'Discover Matches';

  @override
  String get inboxLoadError => 'Something went wrong. Pull down to try again.';

  @override
  String get inboxFilterSheetTitle => 'Filters';

  @override
  String get inboxFilterUnread => 'Unread';

  @override
  String get inboxFilterOnline => 'Online';

  @override
  String get inboxFilterVerified => 'Verified';

  @override
  String get inboxFilterPremium => 'Premium';

  @override
  String get inboxFilterRecent => 'Recent';

  @override
  String get inboxFilterArchived => 'Archived';

  @override
  String get inboxFilterBlocked => 'Blocked';

  @override
  String get inboxSmartNewMatch => 'New Match';

  @override
  String get inboxSmartInterestAccepted => 'Interest Accepted';

  @override
  String get inboxSmartInterestDeclined => 'Interest Declined';

  @override
  String get inboxSmartMessageRequest => 'Message Request';

  @override
  String get inboxSmartAiSuggested => 'AI Suggested';

  @override
  String inboxCompatibilityLabel(int percent) {
    return '$percent% Match';
  }

  @override
  String get inboxActionViewProfile => 'View Profile';

  @override
  String get inboxActionMute => 'Mute';

  @override
  String get inboxActionUnmute => 'Unmute';

  @override
  String get inboxActionArchive => 'Archive';

  @override
  String get inboxActionUnarchive => 'Unarchive';

  @override
  String get inboxActionBlock => 'Block';

  @override
  String get inboxActionUnblock => 'Unblock';

  @override
  String get inboxActionDelete => 'Delete';

  @override
  String get inboxActionPin => 'Pin';

  @override
  String get inboxActionMarkUnread => 'Mark Unread';

  @override
  String get inboxPremiumLockedName => 'Premium Member';

  @override
  String get inboxPremiumLockedMessage =>
      'Unlock Premium to continue chatting.';

  @override
  String get inboxUpgradeCta => 'Upgrade';

  @override
  String get inboxAccept => 'Accept';

  @override
  String get inboxDecline => 'Decline';

  @override
  String get inboxYesterday => 'Yesterday';

  @override
  String get inboxToday => 'Today';

  @override
  String get inboxOnline => 'Online';

  @override
  String get inboxMoreOptions => 'More options';

  @override
  String get inboxMessageFailed => 'Failed to send';

  @override
  String get inboxBlockedBanner => 'You have blocked this conversation.';

  @override
  String get inboxComposerHint => 'Type a message...';

  @override
  String get inboxComposerAttach => 'Attach';

  @override
  String get inboxComposerEmoji => 'Emoji';

  @override
  String get inboxComposerSend => 'Send';

  @override
  String get inboxComposerVoice => 'Voice message';

  @override
  String inboxBlockConfirmTitle(String name) {
    return 'Block $name?';
  }

  @override
  String get inboxBlockConfirmMessage =>
      'They won\'t be able to message you, and you won\'t see each other in Discover anymore.';

  @override
  String inboxUnblockConfirmTitle(String name) {
    return 'Unblock $name?';
  }

  @override
  String get inboxUnblockConfirmMessage =>
      'You\'ll be able to message each other again.';

  @override
  String get inboxUnblockLoading => 'Unblocking…';

  @override
  String inboxUnblockSuccess(String name) {
    return '$name has been unblocked.';
  }

  @override
  String get inboxDeleteConfirmTitle => 'Delete conversation?';

  @override
  String get inboxDeleteConfirmMessage =>
      'This removes the conversation from your inbox. This can\'t be undone.';

  @override
  String get inboxRetrySend => 'Tap to retry';

  @override
  String get inboxNewMessages => 'New messages';

  @override
  String get inboxChooseFromGallery => 'Choose from gallery';

  @override
  String get inboxTakePhoto => 'Take a photo';

  @override
  String get inboxRemoveAttachment => 'Remove';

  @override
  String get messageGateNoInterest =>
      'Send an interest first to start chatting.';

  @override
  String get messageGatePending =>
      'Your interest is pending. You can start chatting once they accept it.';

  @override
  String get messageGateRespondFirst =>
      'Respond to their interest first to start chatting.';

  @override
  String get messageGateDeclined => 'This interest was declined.';

  @override
  String get messageGateBlocked => 'You can\'t message this conversation.';

  @override
  String get messageGateError => 'Unable to open chat. Please try again.';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsMarkAllRead => 'Mark all as read';

  @override
  String get notificationsSectionToday => 'Today';

  @override
  String get notificationsSectionYesterday => 'Yesterday';

  @override
  String get notificationsSectionEarlier => 'Earlier';

  @override
  String get notificationsJustNow => 'Just now';

  @override
  String notificationsMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String notificationsHoursAgo(int count) {
    return '$count hr ago';
  }

  @override
  String notificationsDaysAgo(int count) {
    return '$count d ago';
  }

  @override
  String get notificationsEmptyTitle => 'You\'re all caught up!';

  @override
  String get notificationsEmptyMessage =>
      'New interests, matches, messages and updates will appear here.';

  @override
  String get notificationsComingSoon => 'This will be available soon.';

  @override
  String get profileTitle => 'My Profile';

  @override
  String get profileAboutMeTitle => 'About Me';

  @override
  String get profileBasicDetailsTitle => 'Basic Details';

  @override
  String get profileCardShortlist => 'Shortlist';

  @override
  String get profileCardLike => 'Like';

  @override
  String get premiumTitle => 'Upgrade to Luxury Premium';

  @override
  String get premiumHeroTitle => 'Unlock Unlimited Matches';

  @override
  String get premiumHeroSubtitle =>
      'Get access to verified contacts, AI matchmaking & horoscope details.';

  @override
  String get premiumProceedToPayment => 'Proceed to Payment';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAccountSecuritySection => 'Account & Security';

  @override
  String get settingsIdVerificationTitle => 'ID Verification';

  @override
  String get settingsIdVerificationSubtitle => 'Verify ID to get trust badge';

  @override
  String get settingsPushNotifications => 'Push Notifications';

  @override
  String get settingsAppPreferencesSection => 'App Preferences';

  @override
  String get settingsDarkMode => 'Dark Mode';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsHelpSupport => 'Help & Support';

  @override
  String get settingsLogout => 'Logout';

  @override
  String get settingsDangerZoneSection => 'Danger Zone';

  @override
  String get settingsDeleteAccount => 'Delete Account';

  @override
  String get settingsDeleteAccountSubtitle =>
      'Permanently delete your profile and all data';

  @override
  String get settingsDeleteAccountConfirmMessage =>
      'This permanently deletes your profile, photos, and all data. This action cannot be undone.';

  @override
  String get settingsDeleteAccountProgressMessage => 'Deleting your account…';

  @override
  String get settingsDeleteAccountErrorMessage =>
      'Couldn\'t delete your account. Please check your connection and try again.';

  @override
  String registrationStepIndicator(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String registrationPercentCompleted(int percent) {
    return '$percent% Completed';
  }

  @override
  String get registrationBack => 'Back';

  @override
  String get registrationSkipStep => 'Skip this step';

  @override
  String get registrationFinishLogin => 'Finish & Login';

  @override
  String get registrationRequiredFieldsHint =>
      'Please fill in all required fields to continue.';

  @override
  String get registrationStepBasicInfo => 'Basic Info';

  @override
  String get registrationStepReligion => 'Religion';

  @override
  String get registrationStepLanguage => 'Language';

  @override
  String get registrationStepLocation => 'Location';

  @override
  String get registrationStepEducation => 'Education';

  @override
  String get registrationStepPhysical => 'Physical';

  @override
  String get registrationStepLifestyle => 'Lifestyle';

  @override
  String get registrationStepFamily => 'Family';

  @override
  String get registrationStepHoroscope => 'Horoscope';

  @override
  String get registrationStepPreferences => 'Preferences';

  @override
  String get registrationStepPhotos => 'Photos';

  @override
  String get registrationStepVerification => 'Verification';

  @override
  String get registrationBasicInfoTitle => 'Basic Information';

  @override
  String get registrationBasicInfoSubtitle => 'Tell us about yourself';

  @override
  String get registrationFirstNameLabel => 'First Name';

  @override
  String get registrationFirstNameHint => 'Enter first name';

  @override
  String get registrationLastNameLabel => 'Last Name';

  @override
  String get registrationLastNameHint => 'Enter last name';

  @override
  String get registrationGenderLabel => 'Gender';

  @override
  String get registrationDobLabel => 'Date of Birth';

  @override
  String get registrationDobHint => 'DD / MM / YYYY';

  @override
  String get registrationDobError => 'Please select date of birth';

  @override
  String registrationAgeYears(int age) {
    return 'Age: $age years';
  }

  @override
  String get registrationMaritalStatusLabel => 'Marital Status';

  @override
  String get genderMale => 'Male';

  @override
  String get genderFemale => 'Female';

  @override
  String get maritalNeverMarried => 'Never Married';

  @override
  String get maritalDivorced => 'Divorced';

  @override
  String get maritalWidowed => 'Widowed';

  @override
  String get maritalAwaitingDivorce => 'Awaiting Divorce';

  @override
  String get registrationReligionTitle => 'Religion & Community';

  @override
  String get registrationReligionSubtitle => 'Your religious background';

  @override
  String get registrationReligionLabel => 'Religion';

  @override
  String get registrationSpecifyReligionLabel => 'Specify Religion';

  @override
  String get registrationSpecifyReligionHint => 'Enter your religion';

  @override
  String get registrationCasteLabel => 'Caste';

  @override
  String get registrationCasteHint => 'e.g., Iyer, Iyengar, Mudaliar';

  @override
  String get registrationSubCasteLabel => 'Sub Caste';

  @override
  String get registrationSubCasteHint => 'Enter sub caste';

  @override
  String get registrationGothraLabel => 'Gothra (Optional)';

  @override
  String get registrationGothraHint => 'Enter gothra';

  @override
  String get registrationDenominationLabel => 'Denomination (Optional)';

  @override
  String get registrationDenominationHint => 'Enter denomination';

  @override
  String get registrationCommunityLabel => 'Community';

  @override
  String get registrationCommunityHint => 'e.g., Tamil, Telugu, Kannada';

  @override
  String get religionHindu => 'Hindu';

  @override
  String get religionChristian => 'Christian';

  @override
  String get religionMuslim => 'Muslim';

  @override
  String get religionJain => 'Jain';

  @override
  String get religionSikh => 'Sikh';

  @override
  String get religionBuddhist => 'Buddhist';

  @override
  String get religionInterReligion => 'Inter-Religion';

  @override
  String get religionOther => 'Other';

  @override
  String get registrationLanguagesTitle => 'Languages';

  @override
  String get registrationLanguagesSubtitle => 'Your language preferences';

  @override
  String get registrationMotherTongueLabel => 'Mother Tongue';

  @override
  String get registrationLanguagesKnownLabel => 'Languages Known';

  @override
  String get langTamil => 'Tamil';

  @override
  String get langTelugu => 'Telugu';

  @override
  String get langMalayalam => 'Malayalam';

  @override
  String get langKannada => 'Kannada';

  @override
  String get langHindi => 'Hindi';

  @override
  String get langEnglish => 'English';

  @override
  String get langMarathi => 'Marathi';

  @override
  String get langBengali => 'Bengali';

  @override
  String get langGujarati => 'Gujarati';

  @override
  String get langUrdu => 'Urdu';

  @override
  String get langFrench => 'French';

  @override
  String get langGerman => 'German';

  @override
  String get langArabic => 'Arabic';

  @override
  String get registrationLocationTitle => 'Location';

  @override
  String get registrationLocationSubtitle => 'Where do you live?';

  @override
  String get registrationCountryLabel => 'Country';

  @override
  String get registrationStateLabel => 'State';

  @override
  String get registrationCityLabel => 'City';

  @override
  String get registrationCityHint => 'e.g., Chennai';

  @override
  String get registrationAreaLabel => 'Area';

  @override
  String get registrationAreaHint => 'e.g., T. Nagar';

  @override
  String get registrationPinLabel => 'PIN Code';

  @override
  String get registrationPinHint => '600017';

  @override
  String get registrationNativePlaceLabel => 'Native Place';

  @override
  String get registrationNativePlaceHint => 'e.g., Thanjavur';

  @override
  String get countryIndia => 'India';

  @override
  String get countryUsa => 'United States';

  @override
  String get countryUk => 'United Kingdom';

  @override
  String get countrySingapore => 'Singapore';

  @override
  String get countryUae => 'UAE';

  @override
  String get countryMalaysia => 'Malaysia';

  @override
  String get countryAustralia => 'Australia';

  @override
  String get countryCanada => 'Canada';

  @override
  String get countryOther => 'Other';

  @override
  String get stateTamilNadu => 'Tamil Nadu';

  @override
  String get stateKarnataka => 'Karnataka';

  @override
  String get stateKerala => 'Kerala';

  @override
  String get stateAndhraPradesh => 'Andhra Pradesh';

  @override
  String get stateTelangana => 'Telangana';

  @override
  String get stateMaharashtra => 'Maharashtra';

  @override
  String get stateDelhi => 'Delhi';

  @override
  String get stateGujarat => 'Gujarat';

  @override
  String get stateWestBengal => 'West Bengal';

  @override
  String get stateRajasthan => 'Rajasthan';

  @override
  String get stateUp => 'UP';

  @override
  String get stateOther => 'Other';

  @override
  String get registrationEducationTitle => 'Education & Career';

  @override
  String get registrationEducationSubtitle => 'Your professional background';

  @override
  String get registrationQualificationLabel => 'Highest Qualification';

  @override
  String get registrationSpecifyQualificationLabel => 'Specify Qualification';

  @override
  String get registrationSpecifyQualificationHint => 'e.g., B.A. History';

  @override
  String get registrationCollegeLabel => 'College / University';

  @override
  String get registrationCollegeHint => 'e.g., IIT Madras';

  @override
  String get registrationOccupationLabel => 'Occupation';

  @override
  String get registrationSpecifyOccupationLabel => 'Specify Occupation';

  @override
  String get registrationSpecifyOccupationHint => 'e.g., Freelance Designer';

  @override
  String get registrationCompanyLabel => 'Company';

  @override
  String get registrationCompanyHint => 'e.g., Google';

  @override
  String get registrationEmploymentTypeLabel => 'Employment Type';

  @override
  String get registrationAnnualIncomeLabel => 'Annual Income';

  @override
  String get registrationAnnualIncomeOtherLabel =>
      'Specify Annual Income (in Lakhs)';

  @override
  String get registrationAnnualIncomeOtherHint => 'e.g., 12';

  @override
  String get registrationWorkLocationLabel => 'Work Location';

  @override
  String get registrationWorkLocationHint => 'e.g., Bangalore';

  @override
  String get occSoftwareEngineer => 'Software Engineer';

  @override
  String get occDoctor => 'Doctor';

  @override
  String get occGovt => 'IAS / IPS / Govt';

  @override
  String get occBusinessOwner => 'Business Owner';

  @override
  String get occFinanceBanking => 'Finance / Banking';

  @override
  String get occCivilMechEngg => 'Civil / Mechanical Engg';

  @override
  String get occTeacherProfessor => 'Teacher / Professor';

  @override
  String get occLawyer => 'Lawyer';

  @override
  String get occArchitect => 'Architect';

  @override
  String get occOther => 'Other';

  @override
  String get empPrivate => 'Private';

  @override
  String get empGovernment => 'Government';

  @override
  String get empBusiness => 'Business';

  @override
  String get empSelfEmployed => 'Self-Employed';

  @override
  String get empNotWorking => 'Not Working';

  @override
  String get empStudent => 'Student';

  @override
  String get income5Below => 'Below 5 Lakhs';

  @override
  String get income5to10 => '5 - 10 Lakhs';

  @override
  String get income10to20 => '10 - 20 Lakhs';

  @override
  String get income20to50 => '20 - 50 Lakhs';

  @override
  String get income50to100 => '50 Lakhs - 1 Crore';

  @override
  String get income100Plus => '1 Crore+';

  @override
  String get incomeOther => 'Other';

  @override
  String get registrationPhysicalTitle => 'Physical Details';

  @override
  String get registrationPhysicalSubtitle => 'Describe your appearance';

  @override
  String get registrationHeightLabel => 'Height';

  @override
  String get registrationTapToSetHeightLabel =>
      'Drag the slider to set your height';

  @override
  String get registrationWeightLabel => 'Weight';

  @override
  String get registrationTapToSetWeightLabel =>
      'Drag the slider to set your weight';

  @override
  String get registrationBloodGroupLabel => 'Blood Group';

  @override
  String get registrationDisabilityLabel => 'Disability';

  @override
  String get disabilityNone => 'None';

  @override
  String get disabilityPhysical => 'Physical';

  @override
  String get disabilityHearing => 'Hearing';

  @override
  String get disabilityVisual => 'Visual';

  @override
  String get disabilitySpeech => 'Speech';

  @override
  String get disabilityOther => 'Other';

  @override
  String get registrationLifestyleTitle => 'Lifestyle';

  @override
  String get registrationLifestyleSubtitle => 'Your habits and interests';

  @override
  String get registrationEatingHabitLabel => 'Eating Habit';

  @override
  String get registrationSmokingLabel => 'Smoking';

  @override
  String get registrationDrinkingLabel => 'Drinking';

  @override
  String get registrationFitnessLabel => 'Fitness / Exercise';

  @override
  String get registrationHobbiesLabel => 'Hobbies';

  @override
  String get registrationAboutMeLabel => 'About Me';

  @override
  String get registrationAboutMeHint =>
      'Tell us about yourself, your interests, and what you are looking for...';

  @override
  String get eatVegetarian => 'Vegetarian';

  @override
  String get eatNonVegetarian => 'Non-Vegetarian';

  @override
  String get eatEggetarian => 'Eggetarian';

  @override
  String get eatVegan => 'Vegan';

  @override
  String get eatJain => 'Jain';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonOccasionally => 'Occasionally';

  @override
  String get fitnessDaily => 'Daily';

  @override
  String get fitnessRegularly => 'Regularly';

  @override
  String get hobbyReading => 'Reading';

  @override
  String get hobbyTravelling => 'Travelling';

  @override
  String get hobbyCooking => 'Cooking';

  @override
  String get hobbyMusic => 'Music';

  @override
  String get hobbySports => 'Sports';

  @override
  String get hobbyGaming => 'Gaming';

  @override
  String get hobbyPhotography => 'Photography';

  @override
  String get hobbyPainting => 'Painting';

  @override
  String get hobbyDancing => 'Dancing';

  @override
  String get hobbyYoga => 'Yoga';

  @override
  String get hobbyMovies => 'Movies';

  @override
  String get hobbyGardening => 'Gardening';

  @override
  String get commonDontKnow => 'Don\'t Know';

  @override
  String get commonPleaseSpecifyLabel => 'Please specify';

  @override
  String get commonPleaseSpecifyHint => 'Type your answer';

  @override
  String get commonRequiredFieldLabel => 'Required field';

  @override
  String get registrationFamilyTitle => 'Family Details';

  @override
  String get registrationFamilySubtitle => 'Tell us about your family';

  @override
  String get registrationFatherSectionLabel => 'Father';

  @override
  String get registrationFatherNameLabel => 'Father\'s Name (Optional)';

  @override
  String get registrationFatherNameHint => 'Enter father\'s name';

  @override
  String get registrationFatherAgeLabel => 'Father\'s Age (Optional)';

  @override
  String get registrationFatherAgeHint => 'Enter father\'s age';

  @override
  String get registrationFatherOccLabel => 'Father\'s Occupation (Optional)';

  @override
  String get registrationFatherOccHint => 'e.g., Retired Government Officer';

  @override
  String get registrationMotherSectionLabel => 'Mother';

  @override
  String get registrationMotherNameLabel => 'Mother\'s Name (Optional)';

  @override
  String get registrationMotherNameHint => 'Enter mother\'s name';

  @override
  String get registrationMotherAgeLabel => 'Mother\'s Age (Optional)';

  @override
  String get registrationMotherAgeHint => 'Enter mother\'s age';

  @override
  String get registrationMotherOccLabel => 'Mother\'s Occupation (Optional)';

  @override
  String get registrationMotherOccHint => 'e.g., Homemaker';

  @override
  String get registrationFamilyTypeLabel => 'Family Type';

  @override
  String get registrationFamilyValuesLabel => 'Family Values';

  @override
  String get registrationFamilyStatusLabel => 'Family Status';

  @override
  String get registrationSiblingsSectionLabel => 'Siblings';

  @override
  String get registrationSiblingBrotherLabel => 'Brother';

  @override
  String get registrationSiblingSisterLabel => 'Sister';

  @override
  String get registrationRemoveSiblingLabel => 'Remove';

  @override
  String get registrationSiblingNameLabel => 'Name (Optional)';

  @override
  String get registrationSiblingNameHint => 'Enter sibling\'s name';

  @override
  String get registrationSiblingAgeLabel => 'Age (Optional)';

  @override
  String get registrationSiblingAgeHint => 'Enter sibling\'s age';

  @override
  String get registrationSiblingOccupationLabel => 'Occupation (Optional)';

  @override
  String get registrationSiblingOccupationHint => 'Enter sibling\'s occupation';

  @override
  String get registrationAddSiblingLabel => 'Add Sibling';

  @override
  String get famJoint => 'Joint Family';

  @override
  String get famNuclear => 'Nuclear Family';

  @override
  String get famTraditional => 'Traditional';

  @override
  String get famModerate => 'Moderate';

  @override
  String get famLiberal => 'Liberal';

  @override
  String get famMiddleClass => 'Middle Class';

  @override
  String get famUpperMiddleClass => 'Upper Middle Class';

  @override
  String get famRich => 'Rich';

  @override
  String get famAffluent => 'Affluent';

  @override
  String get registrationHoroscopeTitle => 'Horoscope';

  @override
  String get registrationHoroscopeSubtitle =>
      'Astrological information (optional)';

  @override
  String get registrationHoroscopeAvailable => 'Horoscope Available?';

  @override
  String get registrationBirthTimeLabel => 'Birth Time';

  @override
  String get registrationBirthTimeHint => 'Tap to select';

  @override
  String get registrationBirthPlaceLabel => 'Birth Place';

  @override
  String get registrationBirthPlaceHint => 'e.g., Chennai';

  @override
  String get registrationRashiLabel => 'Rashi (Moon Sign)';

  @override
  String get registrationNakshatraLabel => 'Nakshatra';

  @override
  String get registrationStarLabel => 'Star';

  @override
  String get registrationManglikLabel => 'Manglik / Sevvai';

  @override
  String get registrationDoshamLabel => 'Dosham';

  @override
  String get rashiMesha => 'Mesha';

  @override
  String get rashiVrishabha => 'Vrishabha';

  @override
  String get rashiMithuna => 'Mithuna';

  @override
  String get rashiKataka => 'Kataka';

  @override
  String get rashiSimha => 'Simha';

  @override
  String get rashiKanya => 'Kanya';

  @override
  String get rashiTula => 'Tula';

  @override
  String get rashiVrischika => 'Vrischika';

  @override
  String get rashiDhanu => 'Dhanu';

  @override
  String get rashiMakara => 'Makara';

  @override
  String get rashiKumbha => 'Kumbha';

  @override
  String get rashiMeena => 'Meena';

  @override
  String get commonAny => 'Any';

  @override
  String get registrationPartnerTitle => 'Partner Preferences';

  @override
  String get registrationPartnerSubtitle =>
      'What are you looking for in a partner?';

  @override
  String get registrationPrefAgeLabel => 'Preferred Age Range';

  @override
  String get registrationPrefHeightLabel => 'Preferred Height';

  @override
  String get registrationPrefReligionLabel => 'Religion';

  @override
  String get registrationPrefCasteLabel => 'Caste';

  @override
  String get registrationPrefEducationLabel => 'Education';

  @override
  String get registrationPrefOccupationLabel => 'Occupation';

  @override
  String get registrationPrefIncomeLabel => 'Annual Income';

  @override
  String get registrationPrefLocationLabel => 'Location';

  @override
  String get registrationPrefMotherTongueLabel => 'Mother Tongue';

  @override
  String get registrationPrefMaritalLabel => 'Marital Status';

  @override
  String get registrationPartnerPrefSetLabel =>
      'Your partner preferences are set';

  @override
  String get registrationPartnerPrefNotSetLabel =>
      'You haven\'t set your partner preferences yet';

  @override
  String get registrationSetPartnerPrefButton => 'Set Partner Preferences';

  @override
  String get registrationEditPartnerPrefButton => 'Edit Partner Preferences';

  @override
  String get prefCasteSame => 'Same Caste';

  @override
  String get prefCasteAny => 'Any Caste';

  @override
  String get prefCasteInter => 'Inter-Caste OK';

  @override
  String get prefEduAnyDegree => 'Any Degree';

  @override
  String get prefOccSoftwareIt => 'Software / IT';

  @override
  String get prefLocSameCity => 'Same City';

  @override
  String get prefLocSameState => 'Same State';

  @override
  String get prefLocAnywhereIndia => 'Anywhere in India';

  @override
  String get prefLocNri => 'NRI OK';

  @override
  String get prefTongueSame => 'Same Mother Tongue';

  @override
  String get prefMaritalDoesntMatter => 'Doesn\'t Matter';

  @override
  String get partnerPrefPageTitle => 'Partner Preferences';

  @override
  String get partnerPrefSaveButton => 'Save Preferences';

  @override
  String get partnerPrefSavedSnackbar => 'Partner preferences saved';

  @override
  String get partnerPrefSaveErrorSnackbar =>
      'Could not save preferences. Check your connection.';

  @override
  String get partnerPrefNotSetPlaceholder => 'Not set';

  @override
  String get partnerPrefDoesntMatter => 'Doesn\'t Matter';

  @override
  String get partnerPrefSectionBasic => 'Basic Preferences';

  @override
  String get partnerPrefSectionReligionCommunity => 'Religion & Community';

  @override
  String get partnerPrefSectionEducationCareer => 'Education & Career';

  @override
  String get partnerPrefSectionFamily => 'Family';

  @override
  String get partnerPrefSectionProfile => 'Profile Preferences';

  @override
  String get partnerPrefSectionLifestyle => 'Lifestyle';

  @override
  String get partnerPrefSectionLocation => 'Location Preferences';

  @override
  String get partnerPrefSectionSpecialCases => 'Special Cases';

  @override
  String get partnerPrefSectionVerification => 'Verification & Other';

  @override
  String get partnerPrefEthnicityLabel => 'Ethnicity / Community';

  @override
  String get partnerPrefSubCasteLabel => 'Sub-Caste';

  @override
  String get partnerPrefMangalikLabel => 'Mangalik Status';

  @override
  String get partnerPrefMinEducationLabel => 'Minimum Education';

  @override
  String get partnerPrefEducationLevelsLabel => 'Preferred Education Levels';

  @override
  String get partnerPrefCollegesLabel => 'Preferred Colleges / Universities';

  @override
  String get partnerPrefFieldOfStudyLabel => 'Field of Study';

  @override
  String get partnerPrefIndustryLabel => 'Industry';

  @override
  String get partnerPrefEmploymentTypeLabel => 'Employment Type';

  @override
  String get partnerPrefFamilyStatusLabel => 'Family Status';

  @override
  String get partnerPrefFamilyTypeLabel => 'Family Type';

  @override
  String get partnerPrefFamilyValuesLabel => 'Family Values';

  @override
  String get partnerPrefProfileManagedByLabel => 'Profile Managed By';

  @override
  String get partnerPrefDietLabel => 'Diet';

  @override
  String get partnerPrefDrinkingLabel => 'Drinking';

  @override
  String get partnerPrefSmokingLabel => 'Smoking';

  @override
  String get partnerPrefCountryLabel => 'Country';

  @override
  String get partnerPrefStateLabel => 'State';

  @override
  String get partnerPrefCityLabel => 'City';

  @override
  String get partnerPrefWillingToRelocateLabel => 'Willing to Relocate';

  @override
  String get partnerPrefNriAcceptedLabel => 'NRI Accepted';

  @override
  String get partnerPrefDivorcedAcceptedLabel => 'Divorced Accepted';

  @override
  String get partnerPrefWidowedAcceptedLabel => 'Widowed Accepted';

  @override
  String get partnerPrefAwaitingDivorceAcceptedLabel =>
      'Awaiting Divorce Accepted';

  @override
  String get partnerPrefPhysicallyChallengedAcceptedLabel =>
      'Physically Challenged Accepted';

  @override
  String get partnerPrefAnySpecialCaseLabel => 'Any Special Case';

  @override
  String get partnerPrefHoroscopeMatchRequiredLabel =>
      'Horoscope Match Required';

  @override
  String get partnerPrefVerifiedProfilesOnlyLabel => 'Verified Profiles Only';

  @override
  String get partnerPrefHasProfilePhotoLabel => 'Has Profile Photo';

  @override
  String get partnerPrefHasHoroscopeLabel => 'Has Horoscope';

  @override
  String get partnerPrefAadhaarVerifiedLabel => 'Aadhaar Verified';

  @override
  String get partnerPrefPhoneVerifiedLabel => 'Phone Verified';

  @override
  String get partnerPrefMangalikMustBe => 'Must be Mangalik';

  @override
  String get partnerPrefMangalikNon => 'Non-Mangalik';

  @override
  String get partnerPrefDietVegetarian => 'Vegetarian';

  @override
  String get partnerPrefDietEggetarian => 'Eggetarian';

  @override
  String get partnerPrefDietVegan => 'Vegan';

  @override
  String get partnerPrefDietNonVegetarian => 'Non-Vegetarian';

  @override
  String get partnerPrefDrinkingNever => 'Never';

  @override
  String get partnerPrefDrinkingOccasionally => 'Occasionally';

  @override
  String get partnerPrefDrinkingSocially => 'Socially';

  @override
  String get partnerPrefDrinkingRegularly => 'Regularly';

  @override
  String get partnerPrefSmokingNever => 'Never';

  @override
  String get partnerPrefSmokingOccasionally => 'Occasionally';

  @override
  String get partnerPrefSmokingRegularly => 'Regularly';

  @override
  String get partnerPrefFamilyStatusMiddleClass => 'Middle Class';

  @override
  String get partnerPrefFamilyStatusUpperMiddleClass => 'Upper Middle Class';

  @override
  String get partnerPrefFamilyStatusRich => 'Rich';

  @override
  String get partnerPrefFamilyStatusAffluent => 'Affluent';

  @override
  String get partnerPrefFamilyTypeJoint => 'Joint Family';

  @override
  String get partnerPrefFamilyTypeNuclear => 'Nuclear Family';

  @override
  String get partnerPrefFamilyValuesTraditional => 'Traditional';

  @override
  String get partnerPrefFamilyValuesModerate => 'Moderate';

  @override
  String get partnerPrefFamilyValuesLiberal => 'Liberal';

  @override
  String get partnerPrefManagedBySelf => 'Self';

  @override
  String get partnerPrefManagedByParent => 'Parent';

  @override
  String get partnerPrefManagedBySibling => 'Sibling';

  @override
  String get partnerPrefManagedByRelative => 'Relative';

  @override
  String get partnerPrefManagedByGuardian => 'Guardian';

  @override
  String get partnerPrefAcceptanceAccepted => 'Accepted';

  @override
  String get partnerPrefAcceptanceNotAccepted => 'Not Accepted';

  @override
  String get partnerPrefRequirementRequired => 'Required';

  @override
  String get partnerPrefRequirementOptional => 'Optional';

  @override
  String get drawerPartnerPreferences => 'Partner Preferences';

  @override
  String get registrationPhotosTitle => 'Photos';

  @override
  String get registrationPhotosSubtitle =>
      'Add photos to get 10x more responses';

  @override
  String get registrationPrimaryPhoto => 'Primary Photo';

  @override
  String get registrationGalleryPhotos => 'Gallery Photos';

  @override
  String get registrationPhotosLocalNote =>
      'Photos will be uploaded when backend integration is complete. Currently stored locally.';

  @override
  String get registrationAddPhoto => 'Add Photo';

  @override
  String get registrationCamera => 'Camera';

  @override
  String get registrationCameraSubtitle => 'Take a new photo';

  @override
  String get registrationGallery => 'Gallery';

  @override
  String get registrationGallerySubtitle => 'Choose from gallery';

  @override
  String get registrationVerificationTitle => 'Verification & Trust';

  @override
  String get registrationVerificationSubtitle =>
      'Get verified badges to build trust with matches';

  @override
  String get registrationVerifyMobileTitle => 'Mobile Number Verification';

  @override
  String get registrationVerifyMobileSubtitle =>
      'Mandatory for contacting profiles';

  @override
  String get registrationVerifyEmailTitle => 'Email Verification';

  @override
  String get registrationVerifyEmailSubtitle =>
      'Receive match alerts and account updates';

  @override
  String get registrationVerifyFaceTitle => 'AI Face Selfie Verification';

  @override
  String get registrationVerifyFaceSubtitle =>
      'Get a blue tick badge on your profile photo';

  @override
  String get registrationVerifyIdTitle => 'Government ID / Aadhaar';

  @override
  String get registrationVerifyIdSubtitle =>
      'Verify your age and identity securely';

  @override
  String get registrationVerifyIncomeTitle => 'Income Verification';

  @override
  String get registrationVerifyIncomeSubtitle =>
      'Upload a document to verify your income';

  @override
  String get registrationVerifyAssetTitle => 'Asset Verification';

  @override
  String get registrationVerifyAssetSubtitle =>
      'Upload proof of assets for verification';

  @override
  String get registrationVerifyNriTitle => 'NRI Verification';

  @override
  String get registrationVerifyNriSubtitle =>
      'Upload proof of your overseas residency status';

  @override
  String get registrationPrivacyTitle => '100% Privacy Guaranteed';

  @override
  String get registrationPrivacySubtitle =>
      'Your identity documents are encrypted and never shown publicly to any user.';

  @override
  String get registrationVerifyButton => 'Verify';

  @override
  String get registrationVerificationRetryButton => 'Retry';

  @override
  String get registrationVerificationPendingLabel => 'Pending Review';

  @override
  String get registrationVerificationRejectedLabel => 'Verification Rejected';

  @override
  String get registrationVerificationFailedLabel => 'Upload Failed';

  @override
  String get registrationVerifyMobileRequiredHint =>
      'Verify your mobile number to finish registration.';

  @override
  String get registrationProfileForTitle =>
      'Who are you creating this profile for?';

  @override
  String get registrationProfileForSubtitle => 'Select the relationship';

  @override
  String get profileForRelative => 'Relative';

  @override
  String get profileForMyselfSub => 'I am looking for a match for myself';

  @override
  String get profileForSonSub => 'Finding a match for my son';

  @override
  String get profileForDaughterSub => 'Finding a match for my daughter';

  @override
  String get profileForBrotherSub => 'Finding a match for my brother';

  @override
  String get profileForSisterSub => 'Finding a match for my sister';

  @override
  String get profileForRelativeSub => 'Finding a match for a relative';

  @override
  String get profileForFriendSub => 'Finding a match for a friend';

  @override
  String get registrationProfileCreatedForLabel => 'Profile Created For';

  @override
  String get relationSelf => 'Self';

  @override
  String get registrationFullNameLabel => 'Full Name';

  @override
  String get registrationFullNameHint => 'Enter full name';

  @override
  String get registrationRegisterContinue => 'Register & Continue';

  @override
  String get registrationReviewTitle => 'Review Your Profile';

  @override
  String get registrationProfileSummary => 'Profile Summary';

  @override
  String get registrationEnterApp => 'Enter Nenjam Matrimony';

  @override
  String get registrationEditButton => 'Edit';

  @override
  String get registrationNoInfoYet => 'No information added yet.';

  @override
  String registrationProfileCompletePct(int percent) {
    return 'Profile $percent% Complete';
  }

  @override
  String get registrationCompleteExcellent =>
      'Excellent! Your profile is ready to find matches.';

  @override
  String get registrationCompleteMore =>
      'Complete more sections to attract better matches.';

  @override
  String get registrationWelcomeHeadline => 'Let\'s build your story ❤️';

  @override
  String get registrationWelcomeSubtitle =>
      'We\'ll get to know you a little better so we can introduce you to someone truly compatible.';

  @override
  String get registrationWelcomeCta => 'Begin My Journey';

  @override
  String get registrationMilestoneGettingStarted => 'Getting Started';

  @override
  String get registrationMilestoneAboutYou => 'About You';

  @override
  String get registrationMilestoneYourWorld => 'Your World';

  @override
  String get registrationMilestoneLifestyle => 'Lifestyle';

  @override
  String get registrationMilestoneCompatibility => 'Compatibility';

  @override
  String get registrationMilestoneReady => 'Ready';

  @override
  String registrationTimeRemainingMinutes(int minutes) {
    return 'About $minutes min left';
  }

  @override
  String get registrationTimeRemainingLessThanMinute =>
      'Less than a minute remaining';

  @override
  String get registrationContinueYourStory => 'Continue Your Story';

  @override
  String get registrationMotivationStep1 => 'You\'re doing great.';

  @override
  String get registrationMotivationStep2 => 'We\'re getting to know you.';

  @override
  String get registrationMotivationStep3 =>
      'This helps us recommend better matches.';

  @override
  String get registrationMotivationStep4 => 'You\'re off to a wonderful start.';

  @override
  String get registrationMotivationStep5 =>
      'Every detail helps us find the right match.';

  @override
  String get registrationMotivationStep6 =>
      'Halfway there — you\'re doing wonderfully.';

  @override
  String get registrationMotivationStep7 =>
      'This helps us understand what matters to you.';

  @override
  String get registrationMotivationStep8 => 'Almost there.';

  @override
  String get registrationMotivationStep9 => 'Just a few more details.';

  @override
  String get registrationMotivationQuiz =>
      'This helps us understand what makes you, you.';

  @override
  String get registrationMotivationStep10 =>
      'You\'ve already completed most of your story.';

  @override
  String get registrationMotivationStep11 =>
      'So close to meeting your matches.';

  @override
  String get registrationMotivationStep12 =>
      'One last step to complete your story.';

  @override
  String get registrationTipBasicInfo =>
      'Your age is only used to improve compatibility.';

  @override
  String get registrationTipReligion =>
      'This helps us match you within your community preferences.';

  @override
  String get registrationTipLanguage =>
      'Shared languages make conversations easier from day one.';

  @override
  String get registrationTipLocation =>
      'We use this to suggest matches nearby or wherever you\'d like.';

  @override
  String get registrationTipEducation =>
      'Your background helps us find someone who complements your journey.';

  @override
  String get registrationTipPhysical =>
      'These details help us fine-tune your compatibility profile.';

  @override
  String get registrationTipLifestyle =>
      'Shared lifestyles often lead to stronger relationships.';

  @override
  String get registrationTipFamily =>
      'Family details help us recommend compatible families.';

  @override
  String get registrationTipHoroscope =>
      'This step is optional but improves astrology compatibility.';

  @override
  String get registrationTipQuiz =>
      'This step is optional but improves match quality.';

  @override
  String get registrationTipPartnerPref => 'You can always update these later.';

  @override
  String get registrationTipPhotos =>
      'Natural, smiling photos receive more interest.';

  @override
  String get registrationTipVerification =>
      'Verified profiles earn more trust and better responses.';

  @override
  String get registrationWizardBasicInfoHeadline => 'Tell us about yourself ❤️';

  @override
  String get registrationWizardBasicInfoHook =>
      'Every great relationship starts with a simple introduction.';

  @override
  String get registrationWizardReligionHeadline => 'Your roots & beliefs';

  @override
  String get registrationWizardReligionHook =>
      'Help us understand where you come from.';

  @override
  String get registrationWizardLanguageHeadline =>
      'The languages of your heart';

  @override
  String get registrationWizardLanguageHook =>
      'Tell us how you love to communicate.';

  @override
  String get registrationWizardLocationHeadline =>
      'Where your story is unfolding';

  @override
  String get registrationWizardLocationHook => 'Let us know where to find you.';

  @override
  String get registrationWizardEducationHeadline => 'Your journey so far';

  @override
  String get registrationWizardEducationHook =>
      'Tell us about your studies and career.';

  @override
  String get registrationWizardPhysicalHeadline =>
      'A little about your appearance';

  @override
  String get registrationWizardPhysicalHook =>
      'Just a few details to complete the picture.';

  @override
  String get registrationWizardLifestyleHeadline =>
      'How do you spend your days?';

  @override
  String get registrationWizardLifestyleHook =>
      'Help us understand your lifestyle and what makes you, you.';

  @override
  String get registrationWizardFamilyHeadline => 'Tell us about your family';

  @override
  String get registrationWizardFamilyHook =>
      'Family is an important part of every journey.';

  @override
  String get registrationWizardHoroscopeHeadline =>
      'Your stars can tell part of the story';

  @override
  String get registrationWizardHoroscopeHook =>
      'This step is optional but helps us improve compatibility.';

  @override
  String get registrationWizardQuizHeadline => 'What makes you, you?';

  @override
  String get registrationWizardQuizHook =>
      'A short personality assessment to help us find someone truly compatible.';

  @override
  String get registrationWizardPartnerHeadline => 'Who are you hoping to meet?';

  @override
  String get registrationWizardPartnerHook =>
      'Tell us about the kind of person you\'re looking for.';

  @override
  String get registrationWizardPhotosHeadline =>
      'Let your smile tell your story';

  @override
  String get registrationWizardPhotosHook =>
      'People connect with genuine photos.';

  @override
  String get registrationWizardVerificationHeadline =>
      'Building trust, together';

  @override
  String get registrationWizardVerificationHook =>
      'A few quick checks to keep everyone\'s story safe.';

  @override
  String get registrationCompletingHeadline =>
      'Creating your compatibility profile...';

  @override
  String get registrationCompletingSubtitle => 'This will only take a moment.';

  @override
  String get registrationCompletingStage1 => 'Saving your profile';

  @override
  String get registrationCompletingStage2 =>
      'Preparing your compatibility profile';

  @override
  String get registrationCompletingStage3 => 'Finding meaningful matches';

  @override
  String get registrationCompletingStage4 => 'Personalizing your experience';

  @override
  String get registrationCompletingErrorTitle => 'Something went wrong';

  @override
  String get registrationCompletingErrorMessage =>
      'We couldn\'t save your profile. Please check your connection and try again.';

  @override
  String get registrationCompletingRetryCta => 'Back to Review';

  @override
  String get registrationSuccessHeadline => 'Welcome to Nenjam ❤️';

  @override
  String get registrationSuccessSubtitle =>
      'Your story is ready. We\'ve already started finding meaningful connections for you.';

  @override
  String registrationSuccessCompletionCard(int percent) {
    return 'Profile $percent% Complete';
  }

  @override
  String get registrationSuccessPhotosAdded => 'Photos Added';

  @override
  String get registrationSuccessPhotosSkipped => 'Photos Skipped';

  @override
  String get registrationSuccessHoroscopeDone => 'Horoscope Ready';

  @override
  String get registrationSuccessHoroscopeSkipped => 'Horoscope Skipped';

  @override
  String get registrationSuccessPartnerPrefSaved => 'Partner Preferences Saved';

  @override
  String get registrationSuccessCta => 'Meet Your First Match';

  @override
  String get profileCompletionScreenTitle => 'Profile Strength';

  @override
  String get profileCompletionScreenSubtitle =>
      'See how complete your story is — and what to do next.';

  @override
  String get profileCompletionTierBuilding => 'Building';

  @override
  String get profileCompletionTierGood => 'Good';

  @override
  String get profileCompletionTierStrong => 'Strong';

  @override
  String get profileCompletionTierExceptional => 'Exceptional';

  @override
  String get profileCompletionHighestImpactLabel =>
      'Highest Impact Improvement';

  @override
  String get profileCompletionCompletedSectionsTitle => 'Your Story So Far';

  @override
  String get profileCompletionMissingSectionsTitle => 'Still Growing';

  @override
  String get profileCompletionFutureGrowthTitle => 'Keep Growing Your Profile';

  @override
  String get profileCompletionFutureGrowthSubtitle =>
      'Even a complete profile can go further.';

  @override
  String get profileCompletionModuleRegistration => 'Your Story';

  @override
  String get profileCompletionTipRegistration =>
      'Every detail helps us find your best match.';

  @override
  String get profileCompletionActionRegistration => 'Complete Your Story';

  @override
  String get profileCompletionActionPhotos => 'Boost Your Match Quality';

  @override
  String get profileCompletionActionPartnerPref => 'Sharpen Your Matches';

  @override
  String get profileCompletionActionVerification => 'Build Trust';

  @override
  String get profileCompletionActionHoroscope => 'Deepen Your Compatibility';

  @override
  String get profileCompletionActionEducation =>
      'Complete Your Education & Career';

  @override
  String get profileCompletionActionPhysical => 'Add Your Physical Details';

  @override
  String get profileCompletionActionLifestyle => 'Share Your Lifestyle';

  @override
  String get profileCompletionActionFamily => 'Complete Your Family Details';

  @override
  String get profileCompletionActionPsychology =>
      'Take the Psychology Assessment';

  @override
  String get profileCompletionGrowthPsychology => 'Psychology Assessment';

  @override
  String get profileCompletionGrowthPsychologySubtitle =>
      'Discover your personality profile.';

  @override
  String get profileCompletionGrowthHoroscope => 'Horoscope Compatibility';

  @override
  String get profileCompletionGrowthHoroscopeSubtitle =>
      'See your astrological match insights.';

  @override
  String get profileCompletionGrowthPrompts => 'Profile Prompts';

  @override
  String get profileCompletionGrowthPromptsSubtitle =>
      'Add a few words that sound like you.';

  @override
  String get profileCompletionGrowthPremium => 'Nenjam Premium';

  @override
  String get profileCompletionGrowthPremiumSubtitle =>
      'Get 5x more visibility.';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingGetStarted => 'Get Started';

  @override
  String get onboardingAiTitle => 'AI Matchmaking';

  @override
  String get onboardingAiDescription =>
      'Find your perfect partner with our advanced AI-driven compatibility engine.';

  @override
  String get onboardingAiBadge => 'AI Matching';

  @override
  String get onboardingAiBadgeSub => 'Optimal compatibility';

  @override
  String get onboardingVerifiedTitle => 'Verified Profiles';

  @override
  String get onboardingVerifiedDescription =>
      'Every profile is manually verified to ensure a safe and trustworthy experience.';

  @override
  String get onboardingVerifiedBadge => 'Secure';

  @override
  String get onboardingAstroTitle => 'Astro Compatibility';

  @override
  String get onboardingAstroDescription =>
      'Discover celestial alignment with detailed Kundli and Guna matching.';

  @override
  String get onboardingAstroBadgeGuna => '36/36 Guna';

  @override
  String get onboardingAstroBadgeKundli => 'Kundli Match';

  @override
  String get onboardingAstroSync => 'Astro Sync';

  @override
  String get drawerProfile => 'My Profile';

  @override
  String get drawerEditProfile => 'Edit Profile';

  @override
  String get drawerProfileIntelligence => 'Profile Intelligence';

  @override
  String get drawerVerificationCenter => 'Verification Center';

  @override
  String get drawerTrustScore => 'Trust Score';

  @override
  String get drawerInterestSent => 'Interests Sent';

  @override
  String get drawerInterestReceived => 'Interests Received';

  @override
  String get drawerShortlist => 'Shortlisted Profiles';

  @override
  String get shortlistRemoveButton => 'Remove from Shortlist';

  @override
  String get shortlistEmptyTitle => 'No shortlisted profiles yet';

  @override
  String get shortlistEmptyMessage =>
      'Save profiles you\'re interested in and find them here.';

  @override
  String get shortlistExploreProfiles => 'Explore Profiles';

  @override
  String get shortlistActionFailed =>
      'Failed to update shortlist. Please try again.';

  @override
  String get profileViewersTitle => 'Profile Viewers';

  @override
  String get profileViewersEmptyTitle => 'No one has viewed your profile yet';

  @override
  String get profileViewersEmptyMessage =>
      'Complete your profile and send interests to get noticed.';

  @override
  String get profileViewersViewedJustNow => 'Viewed just now';

  @override
  String profileViewersViewedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return 'Viewed $_temp0';
  }

  @override
  String profileViewersViewedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return 'Viewed $_temp0';
  }

  @override
  String profileViewersViewedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return 'Viewed $_temp0';
  }

  @override
  String get privacyVisibilitySection => 'Profile Visibility';

  @override
  String get privacyPremiumOnlyTitle => 'Show Profile to Premium Members Only';

  @override
  String get privacyPremiumOnlySubtitle =>
      'Only premium members can view your full profile';

  @override
  String get privacyHidePhotosTitle => 'Hide Photos from Non-Connections';

  @override
  String get privacyHidePhotosSubtitle =>
      'Only accepted connections can see your photos';

  @override
  String get privacyLoadErrorMessage =>
      'Privacy settings aren\'t available from the backend yet.';

  @override
  String get privacySaveErrorMessage =>
      'Couldn\'t save your changes. Please try again.';

  @override
  String get privacyBlockedSection => 'Blocked Profiles';

  @override
  String get privacyBlockedEmptyTitle => 'No Blocked Profiles';

  @override
  String get privacyBlockedEmptyMessage =>
      'Profiles you block will appear here.';

  @override
  String get privacyUnblockLabel => 'Unblock';

  @override
  String get privacyBlockedStatusLabel => 'Blocked';

  @override
  String privacyBlockedOnLabel(String date) {
    return 'Blocked on $date';
  }

  @override
  String get drawerLanguage => 'Language';

  @override
  String get drawerSettings => 'Account Settings';

  @override
  String get drawerPrivacy => 'Privacy & Safety';

  @override
  String get drawerHelp => 'Help & Support';

  @override
  String get drawerLogout => 'Logout';

  @override
  String get supportContactTitle => 'Contact Support';

  @override
  String get supportBugReportTitle => 'Report a Bug';

  @override
  String get supportFeatureRequestTitle => 'Feature Request';

  @override
  String get supportAppFeedbackTitle => 'App Feedback';

  @override
  String get supportEmailTitle => 'Email Support';

  @override
  String get supportEmailSubtitle => 'support@nenjammatrimony.com';

  @override
  String get supportTicketHistoryTitle => 'Ticket History';

  @override
  String get supportTicketFormSubjectLabel => 'Subject';

  @override
  String get supportTicketFormSubjectHint => 'Briefly describe your request';

  @override
  String get supportTicketFormMessageLabel => 'Message';

  @override
  String get supportTicketFormMessageHint => 'Share as much detail as you can';

  @override
  String get supportTicketFormSubmit => 'Submit';

  @override
  String get supportTicketFormValidationError => 'Please fill in both fields';

  @override
  String get supportTicketFormSuccessTitle => 'Submitted';

  @override
  String get supportTicketFormSuccessMessage =>
      'Thanks — we\'ve received your request.';

  @override
  String get supportTicketFormErrorMessage =>
      'Couldn\'t submit your request — this feature isn\'t live on the backend yet.';

  @override
  String get supportTicketHistoryEmptyTitle => 'No Tickets Yet';

  @override
  String get supportTicketHistoryEmptyMessage =>
      'Requests you submit will show up here.';

  @override
  String get supportTicketHistoryErrorMessage =>
      'Ticket history isn\'t available from the backend yet.';

  @override
  String get drawerProfileStrength => 'Profile Strength';

  @override
  String get drawerCompleteProfile => 'Complete Profile';

  @override
  String get drawerPremiumTitle => 'Nenjam Premium';

  @override
  String get drawerPremiumSubtitle => 'Get 5x more visibility';

  @override
  String get drawerUpgrade => 'Upgrade Now';

  @override
  String get drawerVersionLabel => 'Nenjam Matrimony';

  @override
  String get drawerManagePhotosTitle => 'Manage Photos';

  @override
  String get drawerChangePhotoSemanticLabel => 'Change profile photo';

  @override
  String get profileDetailSendInterest => 'Send Interest';

  @override
  String get profileDetailInterestSent => 'Interest Sent';

  @override
  String get profileDetailStartConversation => 'Start Conversation';

  @override
  String get profileDetailVideoCall => 'Video Call';

  @override
  String get profileDetailVideoComingSoon => 'Video calling is coming soon';

  @override
  String get profileDetailShareComingSoon => 'Share coming soon';

  @override
  String get interestStatusPending => 'Pending';

  @override
  String get interestStatusAccepted => 'Accepted';

  @override
  String get interestStatusDeclined => 'Declined';

  @override
  String get interestsWithdraw => 'Withdraw';

  @override
  String get interestsActionFailed => 'Something went wrong. Please try again.';

  @override
  String get interestsReceivedEmptyTitle => 'No new interests yet';

  @override
  String get interestsReceivedEmptyMessage =>
      'When someone sends you an interest, it will show up here.';

  @override
  String get interestsSentEmptyTitle => 'No interests sent yet';

  @override
  String get interestsSentEmptyMessage =>
      'Interests you send will show up here so you can track their status.';

  @override
  String get profileDetailTabAbout => 'About';

  @override
  String get profileDetailTabPhotos => 'Photos';

  @override
  String get profileDetailTabFamily => 'Family';

  @override
  String get profileDetailTabLifestyle => 'Lifestyle';

  @override
  String get profileDetailTabHoroscope => 'Horoscope';

  @override
  String get profileDetailTabPreferences => 'Preferences';

  @override
  String get profileDetailTabVerification => 'Verification';

  @override
  String get profileDetailTabTimeline => 'Timeline';

  @override
  String get profileDetailProfileNotAvailable => 'Profile not available';

  @override
  String get profileDetailActionBlock => 'Block User';

  @override
  String get profileDetailActionUnblock => 'Unblock User';

  @override
  String get profileDetailActionReport => 'Report User';

  @override
  String get profileDetailUnblockConfirmTitle => 'Unblock this member?';

  @override
  String get profileDetailUnblockConfirmMessage =>
      'You\'ll be able to see each other again in Discover, Matches, and Search, and can send interests and messages.';

  @override
  String get profileDetailUnblockConfirmButton => 'Unblock';

  @override
  String get profileDetailUnblockLoading => 'Unblocking member…';

  @override
  String profileDetailUnblockSuccess(String name) {
    return '$name has been unblocked.';
  }

  @override
  String get profileDetailBlockConfirmTitle => 'Block this member?';

  @override
  String get profileDetailBlockConfirmMessage =>
      'They will disappear from Discover, Matches and Search. Existing chat remains available with a blocked banner. You can unblock later from Chat.';

  @override
  String get profileDetailBlockConfirmButton => 'Block';

  @override
  String get profileDetailBlockLoading => 'Blocking member…';

  @override
  String profileDetailBlockSuccess(String name) {
    return '$name has been blocked.';
  }

  @override
  String profileDetailReportReasonTitle(String name) {
    return 'Why are you reporting $name?';
  }

  @override
  String get profileDetailReportReasonFakeProfile => 'Fake Profile';

  @override
  String get profileDetailReportReasonSpam => 'Spam';

  @override
  String get profileDetailReportReasonHarassment => 'Harassment';

  @override
  String get profileDetailReportReasonInappropriateContent =>
      'Inappropriate Photos';

  @override
  String get profileDetailReportReasonUnderage => 'Underage';

  @override
  String get profileDetailReportReasonOther => 'Other';

  @override
  String get profileDetailReportDescriptionLabel =>
      'Additional details (optional)';

  @override
  String get profileDetailReportDescriptionHint =>
      'Add any extra context that could help our review team';

  @override
  String get profileDetailReportSubmit => 'Submit';

  @override
  String get profileDetailReportLoading => 'Submitting your report…';

  @override
  String get profileDetailReportSuccess =>
      'Thanks — your report has been submitted.';

  @override
  String get profileDetailMoreLabel => 'More';

  @override
  String get safetyErrorNetwork =>
      'No internet connection. Please check your network and try again.';

  @override
  String get safetyErrorUnauthorized =>
      'Your session has expired. Please sign in again.';

  @override
  String get safetyErrorValidation =>
      'Something about this request wasn\'t valid. Please try again.';

  @override
  String get safetyErrorNotFound => 'This member is no longer available.';

  @override
  String get safetyErrorConflict => 'This was already done for this member.';

  @override
  String get safetyErrorGeneric => 'Something went wrong. Please try again.';
}
