import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ta.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ta'),
  ];

  /// Application brand name
  ///
  /// In en, this message translates to:
  /// **'Nenjam Matrimony'**
  String get appName;

  /// Generic continue / proceed action
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// Splash screen tagline
  ///
  /// In en, this message translates to:
  /// **'Where Hearts Meet'**
  String get splashTagline;

  /// No description provided for @languageChooseTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your Language'**
  String get languageChooseTitle;

  /// No description provided for @languageChooseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select your preferred language for matchmaking'**
  String get languageChooseSubtitle;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageTamil.
  ///
  /// In en, this message translates to:
  /// **'Tamil'**
  String get languageTamil;

  /// No description provided for @authTagline.
  ///
  /// In en, this message translates to:
  /// **'FIND YOUR FOREVER'**
  String get authTagline;

  /// No description provided for @authWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Nenjam Matrimony'**
  String get authWelcomeTitle;

  /// No description provided for @authWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Experience a premier matrimonial journey curated exclusively for discerning individuals seeking lifelong companionship.'**
  String get authWelcomeSubtitle;

  /// No description provided for @authLogin.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get authLogin;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get authCreateAccount;

  /// Headline on the sign-up landing screen shown to logged-out users
  ///
  /// In en, this message translates to:
  /// **'Your story starts here'**
  String get registrationLandingHeadline;

  /// No description provided for @registrationLandingNewTo.
  ///
  /// In en, this message translates to:
  /// **'New to Nenjam?'**
  String get registrationLandingNewTo;

  /// No description provided for @registrationLandingSignUpEmail.
  ///
  /// In en, this message translates to:
  /// **'Sign Up with Email'**
  String get registrationLandingSignUpEmail;

  /// No description provided for @registrationLandingSignUpMobile.
  ///
  /// In en, this message translates to:
  /// **'Sign Up with Mobile'**
  String get registrationLandingSignUpMobile;

  /// No description provided for @registrationLandingSignUpGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign Up with Google'**
  String get registrationLandingSignUpGoogle;

  /// No description provided for @registrationLandingHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get registrationLandingHaveAccount;

  /// No description provided for @authWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get authWelcomeBack;

  /// No description provided for @authJoinCommunity.
  ///
  /// In en, this message translates to:
  /// **'Join Nenjam Matrimony\'s Elite Community'**
  String get authJoinCommunity;

  /// No description provided for @authSignUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get authSignUp;

  /// No description provided for @authChannelMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get authChannelMobile;

  /// No description provided for @authChannelEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authChannelEmail;

  /// No description provided for @authPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get authPhoneNumber;

  /// No description provided for @authEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get authEmailAddress;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get authForgotPassword;

  /// No description provided for @authLoginWithOtp.
  ///
  /// In en, this message translates to:
  /// **'Login with OTP'**
  String get authLoginWithOtp;

  /// No description provided for @authOrContinueWith.
  ///
  /// In en, this message translates to:
  /// **'or continue with'**
  String get authOrContinueWith;

  /// No description provided for @authSignInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get authSignInWithGoogle;

  /// No description provided for @authNewHere.
  ///
  /// In en, this message translates to:
  /// **'New here? '**
  String get authNewHere;

  /// No description provided for @authAlreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get authAlreadyHaveAccount;

  /// No description provided for @authMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile Number'**
  String get authMobileNumber;

  /// No description provided for @authEnterMobileOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter Mobile OTP'**
  String get authEnterMobileOtp;

  /// No description provided for @authEnterEmailOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter Email OTP'**
  String get authEnterEmailOtp;

  /// No description provided for @authSendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get authSendOtp;

  /// No description provided for @authSentStatus.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get authSentStatus;

  /// No description provided for @authErrorValidMobile.
  ///
  /// In en, this message translates to:
  /// **'Please enter valid 10-digit mobile number and details'**
  String get authErrorValidMobile;

  /// No description provided for @authTrustSecure.
  ///
  /// In en, this message translates to:
  /// **'SECURE'**
  String get authTrustSecure;

  /// No description provided for @authTrustPrivate.
  ///
  /// In en, this message translates to:
  /// **'PRIVATE'**
  String get authTrustPrivate;

  /// No description provided for @authTrustVerified.
  ///
  /// In en, this message translates to:
  /// **'VERIFIED'**
  String get authTrustVerified;

  /// No description provided for @authRegForMyself.
  ///
  /// In en, this message translates to:
  /// **'Myself'**
  String get authRegForMyself;

  /// No description provided for @authRegForSon.
  ///
  /// In en, this message translates to:
  /// **'Son'**
  String get authRegForSon;

  /// No description provided for @authRegForDaughter.
  ///
  /// In en, this message translates to:
  /// **'Daughter'**
  String get authRegForDaughter;

  /// No description provided for @authRegForBrother.
  ///
  /// In en, this message translates to:
  /// **'Brother'**
  String get authRegForBrother;

  /// No description provided for @authRegForSister.
  ///
  /// In en, this message translates to:
  /// **'Sister'**
  String get authRegForSister;

  /// No description provided for @authRegForFriend.
  ///
  /// In en, this message translates to:
  /// **'Friend'**
  String get authRegForFriend;

  /// No description provided for @authVerifyMobile.
  ///
  /// In en, this message translates to:
  /// **'Verify Mobile'**
  String get authVerifyMobile;

  /// No description provided for @authVerifyEmail.
  ///
  /// In en, this message translates to:
  /// **'Verify Email'**
  String get authVerifyEmail;

  /// No description provided for @authEnterVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Enter Verification Code'**
  String get authEnterVerificationCode;

  /// No description provided for @authOtpSentTo.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {target}'**
  String authOtpSentTo(String target);

  /// No description provided for @authVerifyAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Verify & Continue'**
  String get authVerifyAndContinue;

  /// No description provided for @authResendOtpIn.
  ///
  /// In en, this message translates to:
  /// **'Resend OTP in'**
  String get authResendOtpIn;

  /// No description provided for @authResendOtp.
  ///
  /// In en, this message translates to:
  /// **'Resend OTP'**
  String get authResendOtp;

  /// No description provided for @authUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get authUsername;

  /// No description provided for @authUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. arun_kumar'**
  String get authUsernameHint;

  /// No description provided for @authPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Min 8 chars with upper, lower, number & symbol'**
  String get authPasswordHint;

  /// No description provided for @authPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password'**
  String get authPasswordRequired;

  /// No description provided for @authComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get authComingSoon;

  /// No description provided for @authGoogleNoAccount.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find a Nenjam account for that Google account. Sign up to create one.'**
  String get authGoogleNoAccount;

  /// No description provided for @authGenericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get authGenericError;

  /// No description provided for @authLogoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get authLogoutConfirm;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @authVerifyEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get authVerifyEmailTitle;

  /// No description provided for @authVerifyEmailSentTo.
  ///
  /// In en, this message translates to:
  /// **'We sent a verification link to {email}'**
  String authVerifyEmailSentTo(String email);

  /// No description provided for @authVerifyEmailInstruction.
  ///
  /// In en, this message translates to:
  /// **'Open the link in your inbox to verify your email, then come back here.'**
  String get authVerifyEmailInstruction;

  /// No description provided for @authIveVerified.
  ///
  /// In en, this message translates to:
  /// **'I\'ve verified'**
  String get authIveVerified;

  /// No description provided for @authResendEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend email'**
  String get authResendEmail;

  /// No description provided for @authResendEmailIn.
  ///
  /// In en, this message translates to:
  /// **'Resend email in {seconds}s'**
  String authResendEmailIn(String seconds);

  /// No description provided for @authEmailNotVerifiedYet.
  ///
  /// In en, this message translates to:
  /// **'Email not verified yet. Please tap the link in your inbox.'**
  String get authEmailNotVerifiedYet;

  /// No description provided for @authEmailVerifiedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Email verified!'**
  String get authEmailVerifiedSuccess;

  /// No description provided for @authVerificationEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Verification email sent.'**
  String get authVerificationEmailSent;

  /// No description provided for @authVerifyPhoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your phone'**
  String get authVerifyPhoneTitle;

  /// No description provided for @authSendingOtp.
  ///
  /// In en, this message translates to:
  /// **'Sending OTP…'**
  String get authSendingOtp;

  /// No description provided for @authPhoneVerifiedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Phone verified!'**
  String get authPhoneVerifiedSuccess;

  /// No description provided for @authForgotPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password'**
  String get authForgotPasswordTitle;

  /// No description provided for @authForgotPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your registered email and we\'ll send you a link to reset your password.'**
  String get authForgotPasswordSubtitle;

  /// No description provided for @authSendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send Reset Link'**
  String get authSendResetLink;

  /// No description provided for @authBackToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to login'**
  String get authBackToLogin;

  /// No description provided for @authResetEmailSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get authResetEmailSentTitle;

  /// No description provided for @authResetEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset link has been sent to your email'**
  String get authResetEmailSent;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navMatches.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get navMatches;

  /// No description provided for @navChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get navChat;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @homeCompleteProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete Your Profile'**
  String get homeCompleteProfileTitle;

  /// No description provided for @homeCompleteProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get better matches by adding a few more details'**
  String get homeCompleteProfileSubtitle;

  /// No description provided for @homeCompleteProfileDismissTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide this for now'**
  String get homeCompleteProfileDismissTooltip;

  /// No description provided for @homeProfileNextStep.
  ///
  /// In en, this message translates to:
  /// **'Next: {step}'**
  String homeProfileNextStep(String step);

  /// No description provided for @homeStepAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add profile photo'**
  String get homeStepAddPhoto;

  /// No description provided for @homeAiPickBadge.
  ///
  /// In en, this message translates to:
  /// **'AI Pick'**
  String get homeAiPickBadge;

  /// No description provided for @discoverAiMatchLabel.
  ///
  /// In en, this message translates to:
  /// **'match'**
  String get discoverAiMatchLabel;

  /// No description provided for @discoverNewTodayLabel.
  ///
  /// In en, this message translates to:
  /// **'New Today'**
  String get discoverNewTodayLabel;

  /// No description provided for @discoverSearchingMoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Searching for more souls…'**
  String get discoverSearchingMoreLabel;

  /// No description provided for @discoverFallbackBannerLabel.
  ///
  /// In en, this message translates to:
  /// **'We widened your preferences slightly to show more matches.'**
  String get discoverFallbackBannerLabel;

  /// No description provided for @discoverVerifiedLabel.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get discoverVerifiedLabel;

  /// No description provided for @discoverPremiumLabel.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get discoverPremiumLabel;

  /// No description provided for @discoverChipVerifiedIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verified Identity'**
  String get discoverChipVerifiedIdentity;

  /// No description provided for @discoverChipPremiumPlus.
  ///
  /// In en, this message translates to:
  /// **'Premium Plus'**
  String get discoverChipPremiumPlus;

  /// No description provided for @discoverChipNri.
  ///
  /// In en, this message translates to:
  /// **'NRI'**
  String get discoverChipNri;

  /// No description provided for @discoverChipBuildingProfile.
  ///
  /// In en, this message translates to:
  /// **'Building Profile'**
  String get discoverChipBuildingProfile;

  /// No description provided for @homePhotoProtectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Photo Protected'**
  String get homePhotoProtectedLabel;

  /// No description provided for @discoverInterestSentLabel.
  ///
  /// In en, this message translates to:
  /// **'Interest Sent'**
  String get discoverInterestSentLabel;

  /// No description provided for @discoverRespondToInterest.
  ///
  /// In en, this message translates to:
  /// **'Respond to Interest'**
  String get discoverRespondToInterest;

  /// No description provided for @homeAiMatchScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'AI Match'**
  String get homeAiMatchScoreLabel;

  /// No description provided for @homeAstroMatchScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Astro Match'**
  String get homeAstroMatchScoreLabel;

  /// No description provided for @discoverCompatibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Compatibility'**
  String get discoverCompatibilityLabel;

  /// No description provided for @actionInterested.
  ///
  /// In en, this message translates to:
  /// **'Interested'**
  String get actionInterested;

  /// No description provided for @actionViewProfile.
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get actionViewProfile;

  /// No description provided for @actionShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get actionShare;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get actionMessage;

  /// No description provided for @discoverFilterLabel.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get discoverFilterLabel;

  /// No description provided for @homeProfileDetailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get homeProfileDetailsLabel;

  /// No description provided for @navDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get navDiscover;

  /// No description provided for @navMessages.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get navMessages;

  /// No description provided for @navPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get navPremium;

  /// No description provided for @navMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// Screen-reader announcement for the unread badge on the bottom nav Inbox icon. Appended to the tab label, e.g. 'Inbox, 3 unread messages'.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{1 unread message} other{{count} unread messages}}'**
  String navUnreadMessagesSemanticLabel(int count);

  /// No description provided for @discoverForYouTab.
  ///
  /// In en, this message translates to:
  /// **'For You'**
  String get discoverForYouTab;

  /// No description provided for @discoverNearMeTab.
  ///
  /// In en, this message translates to:
  /// **'Near Me'**
  String get discoverNearMeTab;

  /// No description provided for @discoverNewTab.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get discoverNewTab;

  /// No description provided for @appNameShort.
  ///
  /// In en, this message translates to:
  /// **'Nenjam'**
  String get appNameShort;

  /// No description provided for @discoverSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get discoverSearchTooltip;

  /// No description provided for @discoverAiRecommendedTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Recommended'**
  String get discoverAiRecommendedTitle;

  /// No description provided for @discoverRecentlyJoinedTitle.
  ///
  /// In en, this message translates to:
  /// **'Recently Joined'**
  String get discoverRecentlyJoinedTitle;

  /// No description provided for @discoverVerifiedProfilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Verified Profiles'**
  String get discoverVerifiedProfilesTitle;

  /// No description provided for @discoverNearYouTitle.
  ///
  /// In en, this message translates to:
  /// **'Near You'**
  String get discoverNearYouTitle;

  /// No description provided for @discoverPremiumMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Premium Members'**
  String get discoverPremiumMembersTitle;

  /// No description provided for @discoverViewAllButton.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get discoverViewAllButton;

  /// No description provided for @discoverStatMatchLabel.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get discoverStatMatchLabel;

  /// No description provided for @discoverStatAstroLabel.
  ///
  /// In en, this message translates to:
  /// **'Astro'**
  String get discoverStatAstroLabel;

  /// No description provided for @discoverUpgradeButton.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get discoverUpgradeButton;

  /// No description provided for @discoverEliteMemberLabel.
  ///
  /// In en, this message translates to:
  /// **'Elite Member'**
  String get discoverEliteMemberLabel;

  /// No description provided for @discoverConnectButton.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get discoverConnectButton;

  /// No description provided for @matchesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No matches yet'**
  String get matchesEmptyTitle;

  /// No description provided for @matchesEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check back soon for new profiles'**
  String get matchesEmptySubtitle;

  /// No description provided for @matchesCategorySearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get matchesCategorySearch;

  /// No description provided for @matchesCategoryNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get matchesCategoryNew;

  /// No description provided for @matchesCategoryDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get matchesCategoryDaily;

  /// No description provided for @matchesCategoryMyMatches.
  ///
  /// In en, this message translates to:
  /// **'My Matches'**
  String get matchesCategoryMyMatches;

  /// No description provided for @matchesCategoryNearMe.
  ///
  /// In en, this message translates to:
  /// **'Near Me'**
  String get matchesCategoryNearMe;

  /// No description provided for @matchesCategoryMoreMatches.
  ///
  /// In en, this message translates to:
  /// **'More Matches'**
  String get matchesCategoryMoreMatches;

  /// No description provided for @discoverKmAwaySuffix.
  ///
  /// In en, this message translates to:
  /// **'km away'**
  String get discoverKmAwaySuffix;

  /// No description provided for @premiumBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Premium'**
  String get premiumBannerTitle;

  /// No description provided for @premiumBannerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get unlimited access to profiles & AI matching'**
  String get premiumBannerSubtitle;

  /// No description provided for @premiumBannerCta.
  ///
  /// In en, this message translates to:
  /// **'Explore Plans'**
  String get premiumBannerCta;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover Profiles'**
  String get searchTitle;

  /// No description provided for @searchFilterVerifiedOnly.
  ///
  /// In en, this message translates to:
  /// **'Verified Only'**
  String get searchFilterVerifiedOnly;

  /// No description provided for @searchFilterNearMe.
  ///
  /// In en, this message translates to:
  /// **'Near Me'**
  String get searchFilterNearMe;

  /// No description provided for @searchFilterDoctor.
  ///
  /// In en, this message translates to:
  /// **'Doctor'**
  String get searchFilterDoctor;

  /// No description provided for @searchFilterEngineer.
  ///
  /// In en, this message translates to:
  /// **'Engineer'**
  String get searchFilterEngineer;

  /// No description provided for @searchShowingMatches.
  ///
  /// In en, this message translates to:
  /// **'Showing {count} Matches'**
  String searchShowingMatches(String count);

  /// No description provided for @searchSortButton.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get searchSortButton;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Name, Matrimony ID, City, Profession...'**
  String get searchHint;

  /// No description provided for @searchRecentTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent Searches'**
  String get searchRecentTitle;

  /// No description provided for @searchPopularTitle.
  ///
  /// In en, this message translates to:
  /// **'Popular Searches'**
  String get searchPopularTitle;

  /// No description provided for @searchClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get searchClearAll;

  /// No description provided for @searchEmptyResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching profiles found.'**
  String get searchEmptyResultsTitle;

  /// No description provided for @searchEmptyResultsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try changing your filters.'**
  String get searchEmptyResultsSubtitle;

  /// No description provided for @searchResetFiltersButton.
  ///
  /// In en, this message translates to:
  /// **'Reset Filters'**
  String get searchResetFiltersButton;

  /// No description provided for @searchFilterSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get searchFilterSheetTitle;

  /// No description provided for @searchFilterReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get searchFilterReset;

  /// No description provided for @searchFilterApply.
  ///
  /// In en, this message translates to:
  /// **'Apply Filters'**
  String get searchFilterApply;

  /// No description provided for @searchFilterShowResults.
  ///
  /// In en, this message translates to:
  /// **'Show Results'**
  String get searchFilterShowResults;

  /// No description provided for @searchFilterSectionBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get searchFilterSectionBasic;

  /// No description provided for @searchFilterSectionReligion.
  ///
  /// In en, this message translates to:
  /// **'Religion'**
  String get searchFilterSectionReligion;

  /// No description provided for @searchFilterSectionLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get searchFilterSectionLocation;

  /// No description provided for @searchFilterSectionEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get searchFilterSectionEducation;

  /// No description provided for @searchFilterSectionCareer.
  ///
  /// In en, this message translates to:
  /// **'Career'**
  String get searchFilterSectionCareer;

  /// No description provided for @searchFilterSectionLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle'**
  String get searchFilterSectionLifestyle;

  /// No description provided for @searchFilterSectionHoroscope.
  ///
  /// In en, this message translates to:
  /// **'Horoscope'**
  String get searchFilterSectionHoroscope;

  /// No description provided for @searchFilterSectionVerification.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get searchFilterSectionVerification;

  /// No description provided for @searchFilterSectionPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get searchFilterSectionPremium;

  /// No description provided for @searchFilterSectionProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get searchFilterSectionProfile;

  /// No description provided for @searchFilterAgeRange.
  ///
  /// In en, this message translates to:
  /// **'Age Range'**
  String get searchFilterAgeRange;

  /// No description provided for @searchFilterGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get searchFilterGender;

  /// No description provided for @searchFilterGenderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get searchFilterGenderMale;

  /// No description provided for @searchFilterGenderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get searchFilterGenderFemale;

  /// No description provided for @searchFilterHeightMin.
  ///
  /// In en, this message translates to:
  /// **'Min Height'**
  String get searchFilterHeightMin;

  /// No description provided for @searchFilterHeightMax.
  ///
  /// In en, this message translates to:
  /// **'Max Height'**
  String get searchFilterHeightMax;

  /// No description provided for @searchFilterCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get searchFilterCommunity;

  /// No description provided for @searchFilterState.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get searchFilterState;

  /// No description provided for @searchFilterDiet.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get searchFilterDiet;

  /// No description provided for @searchFilterSmoking.
  ///
  /// In en, this message translates to:
  /// **'Smoking'**
  String get searchFilterSmoking;

  /// No description provided for @searchFilterDrinking.
  ///
  /// In en, this message translates to:
  /// **'Drinking'**
  String get searchFilterDrinking;

  /// No description provided for @searchFilterRashi.
  ///
  /// In en, this message translates to:
  /// **'Rashi'**
  String get searchFilterRashi;

  /// No description provided for @searchFilterStar.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get searchFilterStar;

  /// No description provided for @searchFilterHoroscopeAvailable.
  ///
  /// In en, this message translates to:
  /// **'Horoscope Available'**
  String get searchFilterHoroscopeAvailable;

  /// No description provided for @searchFilterAadhaarVerified.
  ///
  /// In en, this message translates to:
  /// **'Aadhaar Verified'**
  String get searchFilterAadhaarVerified;

  /// No description provided for @searchFilterIncomeVerified.
  ///
  /// In en, this message translates to:
  /// **'Income Verified'**
  String get searchFilterIncomeVerified;

  /// No description provided for @searchFilterNriVerified.
  ///
  /// In en, this message translates to:
  /// **'NRI Verified'**
  String get searchFilterNriVerified;

  /// No description provided for @searchFilterPremiumOnly.
  ///
  /// In en, this message translates to:
  /// **'Premium Members Only'**
  String get searchFilterPremiumOnly;

  /// No description provided for @searchFilterWithPhoto.
  ///
  /// In en, this message translates to:
  /// **'With Photo'**
  String get searchFilterWithPhoto;

  /// No description provided for @searchFilterCompletedProfile.
  ///
  /// In en, this message translates to:
  /// **'Completed Profile'**
  String get searchFilterCompletedProfile;

  /// No description provided for @searchFilterOptionYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get searchFilterOptionYes;

  /// No description provided for @searchFilterOptionNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get searchFilterOptionNo;

  /// No description provided for @searchFilterOptionOccasionally.
  ///
  /// In en, this message translates to:
  /// **'Occasionally'**
  String get searchFilterOptionOccasionally;

  /// No description provided for @matchesTitle.
  ///
  /// In en, this message translates to:
  /// **'My Matches'**
  String get matchesTitle;

  /// No description provided for @matchesTabNew.
  ///
  /// In en, this message translates to:
  /// **'New ({count})'**
  String matchesTabNew(String count);

  /// No description provided for @matchesTabShortlisted.
  ///
  /// In en, this message translates to:
  /// **'Shortlisted'**
  String get matchesTabShortlisted;

  /// No description provided for @matchesTabMutual.
  ///
  /// In en, this message translates to:
  /// **'Mutual'**
  String get matchesTabMutual;

  /// No description provided for @matchesShortlistedEmpty.
  ///
  /// In en, this message translates to:
  /// **'Shortlisted Profiles'**
  String get matchesShortlistedEmpty;

  /// No description provided for @matchesMutualEmpty.
  ///
  /// In en, this message translates to:
  /// **'Mutual Likes'**
  String get matchesMutualEmpty;

  /// No description provided for @inboxTitle.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get inboxTitle;

  /// No description provided for @inboxNotificationsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get inboxNotificationsTooltip;

  /// No description provided for @inboxFilterTooltip.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get inboxFilterTooltip;

  /// No description provided for @inboxSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search conversations...'**
  String get inboxSearchHint;

  /// No description provided for @inboxTabInterestsReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get inboxTabInterestsReceived;

  /// No description provided for @inboxTabInterestsSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get inboxTabInterestsSent;

  /// No description provided for @inboxTabMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get inboxTabMessages;

  /// No description provided for @inboxEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get inboxEmptyTitle;

  /// No description provided for @inboxEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start discovering matches to begin a conversation.'**
  String get inboxEmptySubtitle;

  /// No description provided for @inboxEmptyCta.
  ///
  /// In en, this message translates to:
  /// **'Discover Matches'**
  String get inboxEmptyCta;

  /// No description provided for @inboxLoadError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Pull down to try again.'**
  String get inboxLoadError;

  /// No description provided for @inboxFilterSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get inboxFilterSheetTitle;

  /// No description provided for @inboxFilterUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get inboxFilterUnread;

  /// No description provided for @inboxFilterOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get inboxFilterOnline;

  /// No description provided for @inboxFilterVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get inboxFilterVerified;

  /// No description provided for @inboxFilterPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get inboxFilterPremium;

  /// No description provided for @inboxFilterRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get inboxFilterRecent;

  /// No description provided for @inboxFilterArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get inboxFilterArchived;

  /// No description provided for @inboxFilterBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get inboxFilterBlocked;

  /// No description provided for @inboxSmartNewMatch.
  ///
  /// In en, this message translates to:
  /// **'New Match'**
  String get inboxSmartNewMatch;

  /// No description provided for @inboxSmartInterestAccepted.
  ///
  /// In en, this message translates to:
  /// **'Interest Accepted'**
  String get inboxSmartInterestAccepted;

  /// No description provided for @inboxSmartInterestDeclined.
  ///
  /// In en, this message translates to:
  /// **'Interest Declined'**
  String get inboxSmartInterestDeclined;

  /// No description provided for @inboxSmartMessageRequest.
  ///
  /// In en, this message translates to:
  /// **'Message Request'**
  String get inboxSmartMessageRequest;

  /// No description provided for @inboxSmartAiSuggested.
  ///
  /// In en, this message translates to:
  /// **'AI Suggested'**
  String get inboxSmartAiSuggested;

  /// No description provided for @inboxCompatibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'{percent}% Match'**
  String inboxCompatibilityLabel(int percent);

  /// No description provided for @inboxActionViewProfile.
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get inboxActionViewProfile;

  /// No description provided for @inboxActionMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get inboxActionMute;

  /// No description provided for @inboxActionUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get inboxActionUnmute;

  /// No description provided for @inboxActionArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get inboxActionArchive;

  /// No description provided for @inboxActionUnarchive.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get inboxActionUnarchive;

  /// No description provided for @inboxActionBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get inboxActionBlock;

  /// No description provided for @inboxActionUnblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get inboxActionUnblock;

  /// No description provided for @inboxActionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get inboxActionDelete;

  /// No description provided for @inboxActionPin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get inboxActionPin;

  /// No description provided for @inboxActionMarkUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark Unread'**
  String get inboxActionMarkUnread;

  /// No description provided for @inboxPremiumLockedName.
  ///
  /// In en, this message translates to:
  /// **'Premium Member'**
  String get inboxPremiumLockedName;

  /// No description provided for @inboxPremiumLockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Unlock Premium to continue chatting.'**
  String get inboxPremiumLockedMessage;

  /// No description provided for @inboxUpgradeCta.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get inboxUpgradeCta;

  /// No description provided for @inboxAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get inboxAccept;

  /// No description provided for @inboxDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get inboxDecline;

  /// No description provided for @inboxYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get inboxYesterday;

  /// No description provided for @inboxToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get inboxToday;

  /// No description provided for @inboxOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get inboxOnline;

  /// No description provided for @inboxMoreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get inboxMoreOptions;

  /// No description provided for @inboxMessageFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send'**
  String get inboxMessageFailed;

  /// No description provided for @inboxBlockedBanner.
  ///
  /// In en, this message translates to:
  /// **'You have blocked this conversation.'**
  String get inboxBlockedBanner;

  /// No description provided for @inboxComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get inboxComposerHint;

  /// No description provided for @inboxComposerAttach.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get inboxComposerAttach;

  /// No description provided for @inboxComposerEmoji.
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get inboxComposerEmoji;

  /// No description provided for @inboxComposerSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get inboxComposerSend;

  /// No description provided for @inboxComposerVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get inboxComposerVoice;

  /// No description provided for @inboxBlockConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Block {name}?'**
  String inboxBlockConfirmTitle(String name);

  /// No description provided for @inboxBlockConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'They won\'t be able to message you, and you won\'t see each other in Discover anymore.'**
  String get inboxBlockConfirmMessage;

  /// No description provided for @inboxUnblockConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Unblock {name}?'**
  String inboxUnblockConfirmTitle(String name);

  /// No description provided for @inboxUnblockConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be able to message each other again.'**
  String get inboxUnblockConfirmMessage;

  /// No description provided for @inboxUnblockLoading.
  ///
  /// In en, this message translates to:
  /// **'Unblocking…'**
  String get inboxUnblockLoading;

  /// No description provided for @inboxUnblockSuccess.
  ///
  /// In en, this message translates to:
  /// **'{name} has been unblocked.'**
  String inboxUnblockSuccess(String name);

  /// No description provided for @inboxDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation?'**
  String get inboxDeleteConfirmTitle;

  /// No description provided for @inboxDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes the conversation from your inbox. This can\'t be undone.'**
  String get inboxDeleteConfirmMessage;

  /// No description provided for @inboxRetrySend.
  ///
  /// In en, this message translates to:
  /// **'Tap to retry'**
  String get inboxRetrySend;

  /// No description provided for @inboxNewMessages.
  ///
  /// In en, this message translates to:
  /// **'New messages'**
  String get inboxNewMessages;

  /// No description provided for @inboxChooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get inboxChooseFromGallery;

  /// No description provided for @inboxTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get inboxTakePhoto;

  /// No description provided for @inboxRemoveAttachment.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get inboxRemoveAttachment;

  /// No description provided for @messageGateNoInterest.
  ///
  /// In en, this message translates to:
  /// **'Send an interest first to start chatting.'**
  String get messageGateNoInterest;

  /// No description provided for @messageGatePending.
  ///
  /// In en, this message translates to:
  /// **'Your interest is pending. You can start chatting once they accept it.'**
  String get messageGatePending;

  /// No description provided for @messageGateRespondFirst.
  ///
  /// In en, this message translates to:
  /// **'Respond to their interest first to start chatting.'**
  String get messageGateRespondFirst;

  /// No description provided for @messageGateDeclined.
  ///
  /// In en, this message translates to:
  /// **'This interest was declined.'**
  String get messageGateDeclined;

  /// No description provided for @messageGateBlocked.
  ///
  /// In en, this message translates to:
  /// **'You can\'t message this conversation.'**
  String get messageGateBlocked;

  /// No description provided for @messageGateError.
  ///
  /// In en, this message translates to:
  /// **'Unable to open chat. Please try again.'**
  String get messageGateError;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get notificationsMarkAllRead;

  /// No description provided for @notificationsSectionToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get notificationsSectionToday;

  /// No description provided for @notificationsSectionYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get notificationsSectionYesterday;

  /// No description provided for @notificationsSectionEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get notificationsSectionEarlier;

  /// No description provided for @notificationsJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get notificationsJustNow;

  /// No description provided for @notificationsMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String notificationsMinutesAgo(int count);

  /// No description provided for @notificationsHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} hr ago'**
  String notificationsHoursAgo(int count);

  /// No description provided for @notificationsDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} d ago'**
  String notificationsDaysAgo(int count);

  /// No description provided for @notificationsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up!'**
  String get notificationsEmptyTitle;

  /// No description provided for @notificationsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'New interests, matches, messages and updates will appear here.'**
  String get notificationsEmptyMessage;

  /// No description provided for @notificationsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'This will be available soon.'**
  String get notificationsComingSoon;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get profileTitle;

  /// No description provided for @profileAboutMeTitle.
  ///
  /// In en, this message translates to:
  /// **'About Me'**
  String get profileAboutMeTitle;

  /// No description provided for @profileBasicDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Basic Details'**
  String get profileBasicDetailsTitle;

  /// No description provided for @profileCardShortlist.
  ///
  /// In en, this message translates to:
  /// **'Shortlist'**
  String get profileCardShortlist;

  /// No description provided for @profileCardLike.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get profileCardLike;

  /// No description provided for @premiumTitle.
  ///
  /// In en, this message translates to:
  /// **'Nenjam Premium'**
  String get premiumTitle;

  /// No description provided for @premiumHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock Unlimited Matches'**
  String get premiumHeroTitle;

  /// No description provided for @premiumHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get access to verified contacts, AI matchmaking & horoscope details.'**
  String get premiumHeroSubtitle;

  /// No description provided for @premiumComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get premiumComingSoon;

  /// No description provided for @premiumUnavailableNotice.
  ///
  /// In en, this message translates to:
  /// **'Premium membership is coming soon. Online purchase isn\'t available yet, so no payment can be made and no premium access is granted.'**
  String get premiumUnavailableNotice;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAccountSecuritySection.
  ///
  /// In en, this message translates to:
  /// **'Account & Security'**
  String get settingsAccountSecuritySection;

  /// No description provided for @settingsIdVerificationTitle.
  ///
  /// In en, this message translates to:
  /// **'ID Verification'**
  String get settingsIdVerificationTitle;

  /// No description provided for @settingsIdVerificationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Verify ID to get trust badge'**
  String get settingsIdVerificationSubtitle;

  /// No description provided for @settingsPushNotifications.
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get settingsPushNotifications;

  /// No description provided for @settingsAppPreferencesSection.
  ///
  /// In en, this message translates to:
  /// **'App Preferences'**
  String get settingsAppPreferencesSection;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsHelpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get settingsHelpSupport;

  /// No description provided for @settingsLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get settingsLogout;

  /// No description provided for @settingsDangerZoneSection.
  ///
  /// In en, this message translates to:
  /// **'Danger Zone'**
  String get settingsDangerZoneSection;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsDeleteAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your profile and all data'**
  String get settingsDeleteAccountSubtitle;

  /// No description provided for @settingsDeleteAccountConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your profile, photos, and all data. This action cannot be undone.'**
  String get settingsDeleteAccountConfirmMessage;

  /// No description provided for @settingsDeleteAccountProgressMessage.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account…'**
  String get settingsDeleteAccountProgressMessage;

  /// No description provided for @settingsDeleteAccountErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete your account. Please check your connection and try again.'**
  String get settingsDeleteAccountErrorMessage;

  /// No description provided for @registrationStepIndicator.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String registrationStepIndicator(int current, int total);

  /// No description provided for @registrationPercentCompleted.
  ///
  /// In en, this message translates to:
  /// **'{percent}% Completed'**
  String registrationPercentCompleted(int percent);

  /// No description provided for @registrationBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get registrationBack;

  /// No description provided for @registrationSkipStep.
  ///
  /// In en, this message translates to:
  /// **'Skip this step'**
  String get registrationSkipStep;

  /// No description provided for @registrationFinishLogin.
  ///
  /// In en, this message translates to:
  /// **'Finish & Login'**
  String get registrationFinishLogin;

  /// No description provided for @registrationRequiredFieldsHint.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all required fields to continue.'**
  String get registrationRequiredFieldsHint;

  /// No description provided for @registrationStepBasicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic Info'**
  String get registrationStepBasicInfo;

  /// No description provided for @registrationStepReligion.
  ///
  /// In en, this message translates to:
  /// **'Religion'**
  String get registrationStepReligion;

  /// No description provided for @registrationStepLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get registrationStepLanguage;

  /// No description provided for @registrationStepLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get registrationStepLocation;

  /// No description provided for @registrationStepEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get registrationStepEducation;

  /// No description provided for @registrationStepPhysical.
  ///
  /// In en, this message translates to:
  /// **'Physical'**
  String get registrationStepPhysical;

  /// No description provided for @registrationStepLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle'**
  String get registrationStepLifestyle;

  /// No description provided for @registrationStepFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get registrationStepFamily;

  /// No description provided for @registrationStepHoroscope.
  ///
  /// In en, this message translates to:
  /// **'Horoscope'**
  String get registrationStepHoroscope;

  /// No description provided for @registrationStepPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get registrationStepPreferences;

  /// No description provided for @registrationStepPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get registrationStepPhotos;

  /// No description provided for @registrationStepVerification.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get registrationStepVerification;

  /// No description provided for @registrationBasicInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Basic Information'**
  String get registrationBasicInfoTitle;

  /// No description provided for @registrationBasicInfoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us about yourself'**
  String get registrationBasicInfoSubtitle;

  /// No description provided for @registrationFirstNameLabel.
  ///
  /// In en, this message translates to:
  /// **'First Name'**
  String get registrationFirstNameLabel;

  /// No description provided for @registrationFirstNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter first name'**
  String get registrationFirstNameHint;

  /// No description provided for @registrationLastNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Last Name'**
  String get registrationLastNameLabel;

  /// No description provided for @registrationLastNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter last name'**
  String get registrationLastNameHint;

  /// No description provided for @registrationGenderLabel.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get registrationGenderLabel;

  /// No description provided for @registrationDobLabel.
  ///
  /// In en, this message translates to:
  /// **'Date of Birth'**
  String get registrationDobLabel;

  /// No description provided for @birthDateDayLabel.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get birthDateDayLabel;

  /// No description provided for @birthDateMonthLabel.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get birthDateMonthLabel;

  /// No description provided for @birthDateYearLabel.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get birthDateYearLabel;

  /// No description provided for @birthDateDayHint.
  ///
  /// In en, this message translates to:
  /// **'DD'**
  String get birthDateDayHint;

  /// No description provided for @birthDateMonthHint.
  ///
  /// In en, this message translates to:
  /// **'MM'**
  String get birthDateMonthHint;

  /// No description provided for @birthDateYearHint.
  ///
  /// In en, this message translates to:
  /// **'YYYY'**
  String get birthDateYearHint;

  /// No description provided for @birthDateErrorDay.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid date.'**
  String get birthDateErrorDay;

  /// No description provided for @birthDateErrorMonth.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid month.'**
  String get birthDateErrorMonth;

  /// No description provided for @birthDateErrorYear.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid year.'**
  String get birthDateErrorYear;

  /// No description provided for @birthDateErrorInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid date of birth.'**
  String get birthDateErrorInvalid;

  /// No description provided for @birthDateErrorFuture.
  ///
  /// In en, this message translates to:
  /// **'Date of birth cannot be in the future.'**
  String get birthDateErrorFuture;

  /// No description provided for @birthDateErrorTooYoung.
  ///
  /// In en, this message translates to:
  /// **'You must be at least {age} years old to register.'**
  String birthDateErrorTooYoung(int age);

  /// No description provided for @registrationDobError.
  ///
  /// In en, this message translates to:
  /// **'Please select date of birth'**
  String get registrationDobError;

  /// No description provided for @registrationAgeYears.
  ///
  /// In en, this message translates to:
  /// **'Age: {age} years'**
  String registrationAgeYears(int age);

  /// No description provided for @registrationMaritalStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Marital Status'**
  String get registrationMaritalStatusLabel;

  /// No description provided for @genderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get genderMale;

  /// No description provided for @genderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get genderFemale;

  /// No description provided for @maritalNeverMarried.
  ///
  /// In en, this message translates to:
  /// **'Never Married'**
  String get maritalNeverMarried;

  /// No description provided for @maritalDivorced.
  ///
  /// In en, this message translates to:
  /// **'Divorced'**
  String get maritalDivorced;

  /// No description provided for @maritalWidowed.
  ///
  /// In en, this message translates to:
  /// **'Widowed'**
  String get maritalWidowed;

  /// No description provided for @maritalAwaitingDivorce.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Divorce'**
  String get maritalAwaitingDivorce;

  /// No description provided for @registrationReligionTitle.
  ///
  /// In en, this message translates to:
  /// **'Religion & Community'**
  String get registrationReligionTitle;

  /// No description provided for @registrationReligionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your religious background'**
  String get registrationReligionSubtitle;

  /// No description provided for @registrationReligionLabel.
  ///
  /// In en, this message translates to:
  /// **'Religion'**
  String get registrationReligionLabel;

  /// No description provided for @registrationSpecifyReligionLabel.
  ///
  /// In en, this message translates to:
  /// **'Specify Religion'**
  String get registrationSpecifyReligionLabel;

  /// No description provided for @registrationSpecifyReligionHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your religion'**
  String get registrationSpecifyReligionHint;

  /// No description provided for @registrationCasteLabel.
  ///
  /// In en, this message translates to:
  /// **'Caste'**
  String get registrationCasteLabel;

  /// No description provided for @registrationCasteHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Iyer, Iyengar, Mudaliar'**
  String get registrationCasteHint;

  /// No description provided for @registrationSubCasteLabel.
  ///
  /// In en, this message translates to:
  /// **'Sub Caste'**
  String get registrationSubCasteLabel;

  /// No description provided for @registrationSubCasteHint.
  ///
  /// In en, this message translates to:
  /// **'Enter sub caste'**
  String get registrationSubCasteHint;

  /// No description provided for @registrationGothraLabel.
  ///
  /// In en, this message translates to:
  /// **'Gothra (Optional)'**
  String get registrationGothraLabel;

  /// No description provided for @registrationGothraHint.
  ///
  /// In en, this message translates to:
  /// **'Enter gothra'**
  String get registrationGothraHint;

  /// No description provided for @registrationDenominationLabel.
  ///
  /// In en, this message translates to:
  /// **'Denomination (Optional)'**
  String get registrationDenominationLabel;

  /// No description provided for @registrationDenominationHint.
  ///
  /// In en, this message translates to:
  /// **'Enter denomination'**
  String get registrationDenominationHint;

  /// No description provided for @registrationCommunityLabel.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get registrationCommunityLabel;

  /// No description provided for @registrationSpecifySubCommunityLabel.
  ///
  /// In en, this message translates to:
  /// **'Specify Sub-community'**
  String get registrationSpecifySubCommunityLabel;

  /// No description provided for @registrationSpecifyCommunityLabel.
  ///
  /// In en, this message translates to:
  /// **'Specify Community'**
  String get registrationSpecifyCommunityLabel;

  /// No description provided for @registrationCommunityHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Tamil, Telugu, Kannada'**
  String get registrationCommunityHint;

  /// No description provided for @religionHindu.
  ///
  /// In en, this message translates to:
  /// **'Hindu'**
  String get religionHindu;

  /// No description provided for @religionChristian.
  ///
  /// In en, this message translates to:
  /// **'Christian'**
  String get religionChristian;

  /// No description provided for @religionMuslim.
  ///
  /// In en, this message translates to:
  /// **'Muslim'**
  String get religionMuslim;

  /// No description provided for @religionJain.
  ///
  /// In en, this message translates to:
  /// **'Jain'**
  String get religionJain;

  /// No description provided for @religionSikh.
  ///
  /// In en, this message translates to:
  /// **'Sikh'**
  String get religionSikh;

  /// No description provided for @religionBuddhist.
  ///
  /// In en, this message translates to:
  /// **'Buddhist'**
  String get religionBuddhist;

  /// No description provided for @religionInterReligion.
  ///
  /// In en, this message translates to:
  /// **'Inter-Religion'**
  String get religionInterReligion;

  /// No description provided for @religionOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get religionOther;

  /// No description provided for @registrationLanguagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get registrationLanguagesTitle;

  /// No description provided for @registrationLanguagesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your language preferences'**
  String get registrationLanguagesSubtitle;

  /// No description provided for @registrationMotherTongueLabel.
  ///
  /// In en, this message translates to:
  /// **'Mother Tongue'**
  String get registrationMotherTongueLabel;

  /// No description provided for @registrationLanguagesKnownLabel.
  ///
  /// In en, this message translates to:
  /// **'Languages Known'**
  String get registrationLanguagesKnownLabel;

  /// No description provided for @langTamil.
  ///
  /// In en, this message translates to:
  /// **'Tamil'**
  String get langTamil;

  /// No description provided for @langTelugu.
  ///
  /// In en, this message translates to:
  /// **'Telugu'**
  String get langTelugu;

  /// No description provided for @langMalayalam.
  ///
  /// In en, this message translates to:
  /// **'Malayalam'**
  String get langMalayalam;

  /// No description provided for @langKannada.
  ///
  /// In en, this message translates to:
  /// **'Kannada'**
  String get langKannada;

  /// No description provided for @langHindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get langHindi;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langMarathi.
  ///
  /// In en, this message translates to:
  /// **'Marathi'**
  String get langMarathi;

  /// No description provided for @langBengali.
  ///
  /// In en, this message translates to:
  /// **'Bengali'**
  String get langBengali;

  /// No description provided for @langGujarati.
  ///
  /// In en, this message translates to:
  /// **'Gujarati'**
  String get langGujarati;

  /// No description provided for @langUrdu.
  ///
  /// In en, this message translates to:
  /// **'Urdu'**
  String get langUrdu;

  /// No description provided for @langFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get langFrench;

  /// No description provided for @langGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get langGerman;

  /// No description provided for @langArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get langArabic;

  /// No description provided for @registrationLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get registrationLocationTitle;

  /// No description provided for @registrationLocationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Where do you live?'**
  String get registrationLocationSubtitle;

  /// No description provided for @registrationCountryLabel.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get registrationCountryLabel;

  /// No description provided for @registrationStateLabel.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get registrationStateLabel;

  /// No description provided for @registrationCityLabel.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get registrationCityLabel;

  /// No description provided for @registrationCityHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Chennai'**
  String get registrationCityHint;

  /// No description provided for @registrationCountryHint.
  ///
  /// In en, this message translates to:
  /// **'Select your country'**
  String get registrationCountryHint;

  /// No description provided for @registrationStateHint.
  ///
  /// In en, this message translates to:
  /// **'Select your state'**
  String get registrationStateHint;

  /// No description provided for @registrationAreaLabel.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get registrationAreaLabel;

  /// No description provided for @registrationAreaHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., T. Nagar'**
  String get registrationAreaHint;

  /// No description provided for @registrationPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN Code'**
  String get registrationPinLabel;

  /// No description provided for @registrationPinHint.
  ///
  /// In en, this message translates to:
  /// **'600017'**
  String get registrationPinHint;

  /// No description provided for @registrationNativePlaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Native Place'**
  String get registrationNativePlaceLabel;

  /// No description provided for @registrationNativePlaceHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Thanjavur'**
  String get registrationNativePlaceHint;

  /// No description provided for @countryIndia.
  ///
  /// In en, this message translates to:
  /// **'India'**
  String get countryIndia;

  /// No description provided for @countryUsa.
  ///
  /// In en, this message translates to:
  /// **'United States'**
  String get countryUsa;

  /// No description provided for @countryUk.
  ///
  /// In en, this message translates to:
  /// **'United Kingdom'**
  String get countryUk;

  /// No description provided for @countrySingapore.
  ///
  /// In en, this message translates to:
  /// **'Singapore'**
  String get countrySingapore;

  /// No description provided for @countryUae.
  ///
  /// In en, this message translates to:
  /// **'UAE'**
  String get countryUae;

  /// No description provided for @countryMalaysia.
  ///
  /// In en, this message translates to:
  /// **'Malaysia'**
  String get countryMalaysia;

  /// No description provided for @countryAustralia.
  ///
  /// In en, this message translates to:
  /// **'Australia'**
  String get countryAustralia;

  /// No description provided for @countryCanada.
  ///
  /// In en, this message translates to:
  /// **'Canada'**
  String get countryCanada;

  /// No description provided for @countryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get countryOther;

  /// No description provided for @stateTamilNadu.
  ///
  /// In en, this message translates to:
  /// **'Tamil Nadu'**
  String get stateTamilNadu;

  /// No description provided for @stateKarnataka.
  ///
  /// In en, this message translates to:
  /// **'Karnataka'**
  String get stateKarnataka;

  /// No description provided for @stateKerala.
  ///
  /// In en, this message translates to:
  /// **'Kerala'**
  String get stateKerala;

  /// No description provided for @stateAndhraPradesh.
  ///
  /// In en, this message translates to:
  /// **'Andhra Pradesh'**
  String get stateAndhraPradesh;

  /// No description provided for @stateTelangana.
  ///
  /// In en, this message translates to:
  /// **'Telangana'**
  String get stateTelangana;

  /// No description provided for @stateMaharashtra.
  ///
  /// In en, this message translates to:
  /// **'Maharashtra'**
  String get stateMaharashtra;

  /// No description provided for @stateDelhi.
  ///
  /// In en, this message translates to:
  /// **'Delhi'**
  String get stateDelhi;

  /// No description provided for @stateGujarat.
  ///
  /// In en, this message translates to:
  /// **'Gujarat'**
  String get stateGujarat;

  /// No description provided for @stateWestBengal.
  ///
  /// In en, this message translates to:
  /// **'West Bengal'**
  String get stateWestBengal;

  /// No description provided for @stateRajasthan.
  ///
  /// In en, this message translates to:
  /// **'Rajasthan'**
  String get stateRajasthan;

  /// No description provided for @stateUp.
  ///
  /// In en, this message translates to:
  /// **'UP'**
  String get stateUp;

  /// No description provided for @stateOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get stateOther;

  /// No description provided for @registrationEducationTitle.
  ///
  /// In en, this message translates to:
  /// **'Education & Career'**
  String get registrationEducationTitle;

  /// No description provided for @registrationEducationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your professional background'**
  String get registrationEducationSubtitle;

  /// No description provided for @registrationQualificationLabel.
  ///
  /// In en, this message translates to:
  /// **'Highest Qualification'**
  String get registrationQualificationLabel;

  /// No description provided for @registrationSpecifyQualificationLabel.
  ///
  /// In en, this message translates to:
  /// **'Specify Qualification'**
  String get registrationSpecifyQualificationLabel;

  /// No description provided for @registrationSpecifyQualificationHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., B.A. History'**
  String get registrationSpecifyQualificationHint;

  /// No description provided for @registrationCollegeLabel.
  ///
  /// In en, this message translates to:
  /// **'College / University'**
  String get registrationCollegeLabel;

  /// No description provided for @registrationCollegeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., IIT Madras'**
  String get registrationCollegeHint;

  /// No description provided for @registrationOccupationLabel.
  ///
  /// In en, this message translates to:
  /// **'Occupation'**
  String get registrationOccupationLabel;

  /// No description provided for @registrationSpecifyOccupationLabel.
  ///
  /// In en, this message translates to:
  /// **'Specify Occupation'**
  String get registrationSpecifyOccupationLabel;

  /// No description provided for @registrationSpecifyOccupationHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Freelance Designer'**
  String get registrationSpecifyOccupationHint;

  /// No description provided for @registrationCompanyLabel.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get registrationCompanyLabel;

  /// No description provided for @registrationCompanyHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Google'**
  String get registrationCompanyHint;

  /// No description provided for @registrationEmploymentTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'You work with'**
  String get registrationEmploymentTypeLabel;

  /// No description provided for @registrationSpecifyEmploymentTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Specify what you work with'**
  String get registrationSpecifyEmploymentTypeLabel;

  /// No description provided for @registrationSpecifyEmploymentTypeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. NGO, Cooperative'**
  String get registrationSpecifyEmploymentTypeHint;

  /// No description provided for @registrationIndustryLabel.
  ///
  /// In en, this message translates to:
  /// **'Industry'**
  String get registrationIndustryLabel;

  /// No description provided for @registrationSpecifyIndustryLabel.
  ///
  /// In en, this message translates to:
  /// **'Specify Industry'**
  String get registrationSpecifyIndustryLabel;

  /// No description provided for @registrationSpecifyIndustryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Logistics, Agriculture'**
  String get registrationSpecifyIndustryHint;

  /// No description provided for @registrationAnnualIncomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Annual Income'**
  String get registrationAnnualIncomeLabel;

  /// No description provided for @registrationAnnualIncomeOtherLabel.
  ///
  /// In en, this message translates to:
  /// **'Specify Annual Income (in Lakhs)'**
  String get registrationAnnualIncomeOtherLabel;

  /// No description provided for @registrationAnnualIncomeOtherHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., 12'**
  String get registrationAnnualIncomeOtherHint;

  /// No description provided for @registrationWorkLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Work Location'**
  String get registrationWorkLocationLabel;

  /// No description provided for @registrationWorkLocationHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Bangalore'**
  String get registrationWorkLocationHint;

  /// No description provided for @occSoftwareEngineer.
  ///
  /// In en, this message translates to:
  /// **'Software Engineer'**
  String get occSoftwareEngineer;

  /// No description provided for @occDoctor.
  ///
  /// In en, this message translates to:
  /// **'Doctor'**
  String get occDoctor;

  /// No description provided for @occGovt.
  ///
  /// In en, this message translates to:
  /// **'IAS / IPS / Govt'**
  String get occGovt;

  /// No description provided for @occBusinessOwner.
  ///
  /// In en, this message translates to:
  /// **'Business Owner'**
  String get occBusinessOwner;

  /// No description provided for @occFinanceBanking.
  ///
  /// In en, this message translates to:
  /// **'Finance / Banking'**
  String get occFinanceBanking;

  /// No description provided for @occCivilMechEngg.
  ///
  /// In en, this message translates to:
  /// **'Civil / Mechanical Engg'**
  String get occCivilMechEngg;

  /// No description provided for @occTeacherProfessor.
  ///
  /// In en, this message translates to:
  /// **'Teacher / Professor'**
  String get occTeacherProfessor;

  /// No description provided for @occLawyer.
  ///
  /// In en, this message translates to:
  /// **'Lawyer'**
  String get occLawyer;

  /// No description provided for @occArchitect.
  ///
  /// In en, this message translates to:
  /// **'Architect'**
  String get occArchitect;

  /// No description provided for @occOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get occOther;

  /// No description provided for @empPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get empPrivate;

  /// No description provided for @empGovernment.
  ///
  /// In en, this message translates to:
  /// **'Government'**
  String get empGovernment;

  /// No description provided for @empBusiness.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get empBusiness;

  /// No description provided for @empSelfEmployed.
  ///
  /// In en, this message translates to:
  /// **'Self-Employed'**
  String get empSelfEmployed;

  /// No description provided for @empNotWorking.
  ///
  /// In en, this message translates to:
  /// **'Not Working'**
  String get empNotWorking;

  /// No description provided for @empStudent.
  ///
  /// In en, this message translates to:
  /// **'Student'**
  String get empStudent;

  /// No description provided for @income5Below.
  ///
  /// In en, this message translates to:
  /// **'Below 5 Lakhs'**
  String get income5Below;

  /// No description provided for @income5to10.
  ///
  /// In en, this message translates to:
  /// **'5 - 10 Lakhs'**
  String get income5to10;

  /// No description provided for @income10to20.
  ///
  /// In en, this message translates to:
  /// **'10 - 20 Lakhs'**
  String get income10to20;

  /// No description provided for @income20to50.
  ///
  /// In en, this message translates to:
  /// **'20 - 50 Lakhs'**
  String get income20to50;

  /// No description provided for @income50to100.
  ///
  /// In en, this message translates to:
  /// **'50 Lakhs - 1 Crore'**
  String get income50to100;

  /// No description provided for @income100Plus.
  ///
  /// In en, this message translates to:
  /// **'1 Crore+'**
  String get income100Plus;

  /// No description provided for @incomeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get incomeOther;

  /// No description provided for @registrationPhysicalTitle.
  ///
  /// In en, this message translates to:
  /// **'Physical Details'**
  String get registrationPhysicalTitle;

  /// No description provided for @registrationPhysicalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Describe your appearance'**
  String get registrationPhysicalSubtitle;

  /// No description provided for @registrationHeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get registrationHeightLabel;

  /// No description provided for @registrationTapToSetHeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Drag the slider to set your height'**
  String get registrationTapToSetHeightLabel;

  /// No description provided for @registrationWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get registrationWeightLabel;

  /// No description provided for @registrationTapToSetWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Drag the slider to set your weight'**
  String get registrationTapToSetWeightLabel;

  /// No description provided for @registrationBloodGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'Blood Group'**
  String get registrationBloodGroupLabel;

  /// No description provided for @registrationDisabilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Disability'**
  String get registrationDisabilityLabel;

  /// No description provided for @disabilityNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get disabilityNone;

  /// No description provided for @disabilityPhysical.
  ///
  /// In en, this message translates to:
  /// **'Physical'**
  String get disabilityPhysical;

  /// No description provided for @disabilityHearing.
  ///
  /// In en, this message translates to:
  /// **'Hearing'**
  String get disabilityHearing;

  /// No description provided for @disabilityVisual.
  ///
  /// In en, this message translates to:
  /// **'Visual'**
  String get disabilityVisual;

  /// No description provided for @disabilitySpeech.
  ///
  /// In en, this message translates to:
  /// **'Speech'**
  String get disabilitySpeech;

  /// No description provided for @disabilityOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get disabilityOther;

  /// No description provided for @registrationLifestyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle'**
  String get registrationLifestyleTitle;

  /// No description provided for @registrationLifestyleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your habits and interests'**
  String get registrationLifestyleSubtitle;

  /// No description provided for @registrationEatingHabitLabel.
  ///
  /// In en, this message translates to:
  /// **'Eating Habit'**
  String get registrationEatingHabitLabel;

  /// No description provided for @registrationSmokingLabel.
  ///
  /// In en, this message translates to:
  /// **'Smoking'**
  String get registrationSmokingLabel;

  /// No description provided for @registrationDrinkingLabel.
  ///
  /// In en, this message translates to:
  /// **'Drinking'**
  String get registrationDrinkingLabel;

  /// No description provided for @registrationFitnessLabel.
  ///
  /// In en, this message translates to:
  /// **'Fitness / Exercise'**
  String get registrationFitnessLabel;

  /// No description provided for @registrationHobbiesLabel.
  ///
  /// In en, this message translates to:
  /// **'Hobbies'**
  String get registrationHobbiesLabel;

  /// No description provided for @registrationAboutMeLabel.
  ///
  /// In en, this message translates to:
  /// **'About Me'**
  String get registrationAboutMeLabel;

  /// No description provided for @registrationAboutMeHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us about yourself, your interests, and what you are looking for...'**
  String get registrationAboutMeHint;

  /// No description provided for @eatVegetarian.
  ///
  /// In en, this message translates to:
  /// **'Vegetarian'**
  String get eatVegetarian;

  /// No description provided for @eatNonVegetarian.
  ///
  /// In en, this message translates to:
  /// **'Non-Vegetarian'**
  String get eatNonVegetarian;

  /// No description provided for @eatEggetarian.
  ///
  /// In en, this message translates to:
  /// **'Eggetarian'**
  String get eatEggetarian;

  /// No description provided for @eatVegan.
  ///
  /// In en, this message translates to:
  /// **'Vegan'**
  String get eatVegan;

  /// No description provided for @eatJain.
  ///
  /// In en, this message translates to:
  /// **'Jain'**
  String get eatJain;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @commonOccasionally.
  ///
  /// In en, this message translates to:
  /// **'Occasionally'**
  String get commonOccasionally;

  /// No description provided for @fitnessDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get fitnessDaily;

  /// No description provided for @fitnessRegularly.
  ///
  /// In en, this message translates to:
  /// **'Regularly'**
  String get fitnessRegularly;

  /// No description provided for @hobbyReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get hobbyReading;

  /// No description provided for @hobbyTravelling.
  ///
  /// In en, this message translates to:
  /// **'Travelling'**
  String get hobbyTravelling;

  /// No description provided for @hobbyCooking.
  ///
  /// In en, this message translates to:
  /// **'Cooking'**
  String get hobbyCooking;

  /// No description provided for @hobbyMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get hobbyMusic;

  /// No description provided for @hobbySports.
  ///
  /// In en, this message translates to:
  /// **'Sports'**
  String get hobbySports;

  /// No description provided for @hobbyGaming.
  ///
  /// In en, this message translates to:
  /// **'Gaming'**
  String get hobbyGaming;

  /// No description provided for @hobbyPhotography.
  ///
  /// In en, this message translates to:
  /// **'Photography'**
  String get hobbyPhotography;

  /// No description provided for @hobbyPainting.
  ///
  /// In en, this message translates to:
  /// **'Painting'**
  String get hobbyPainting;

  /// No description provided for @hobbyDancing.
  ///
  /// In en, this message translates to:
  /// **'Dancing'**
  String get hobbyDancing;

  /// No description provided for @hobbyYoga.
  ///
  /// In en, this message translates to:
  /// **'Yoga'**
  String get hobbyYoga;

  /// No description provided for @hobbyMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get hobbyMovies;

  /// No description provided for @hobbyGardening.
  ///
  /// In en, this message translates to:
  /// **'Gardening'**
  String get hobbyGardening;

  /// No description provided for @commonDontKnow.
  ///
  /// In en, this message translates to:
  /// **'Don\'t Know'**
  String get commonDontKnow;

  /// No description provided for @commonPleaseSpecifyLabel.
  ///
  /// In en, this message translates to:
  /// **'Please specify'**
  String get commonPleaseSpecifyLabel;

  /// No description provided for @commonPleaseSpecifyHint.
  ///
  /// In en, this message translates to:
  /// **'Type your answer'**
  String get commonPleaseSpecifyHint;

  /// No description provided for @commonRequiredFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Required field'**
  String get commonRequiredFieldLabel;

  /// No description provided for @registrationFamilyTitle.
  ///
  /// In en, this message translates to:
  /// **'Family Details'**
  String get registrationFamilyTitle;

  /// No description provided for @registrationFamilySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us about your family'**
  String get registrationFamilySubtitle;

  /// No description provided for @registrationFatherSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Father'**
  String get registrationFatherSectionLabel;

  /// No description provided for @registrationFatherNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Father\'s Name (Optional)'**
  String get registrationFatherNameLabel;

  /// No description provided for @registrationFatherNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter father\'s name'**
  String get registrationFatherNameHint;

  /// No description provided for @registrationFatherAgeLabel.
  ///
  /// In en, this message translates to:
  /// **'Father\'s Age (Optional)'**
  String get registrationFatherAgeLabel;

  /// No description provided for @registrationFatherAgeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter father\'s age'**
  String get registrationFatherAgeHint;

  /// No description provided for @registrationFatherOccLabel.
  ///
  /// In en, this message translates to:
  /// **'Father\'s Occupation (Optional)'**
  String get registrationFatherOccLabel;

  /// No description provided for @registrationFatherOccHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Retired Government Officer'**
  String get registrationFatherOccHint;

  /// No description provided for @registrationMotherSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Mother'**
  String get registrationMotherSectionLabel;

  /// No description provided for @registrationMotherNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Mother\'s Name (Optional)'**
  String get registrationMotherNameLabel;

  /// No description provided for @registrationMotherNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter mother\'s name'**
  String get registrationMotherNameHint;

  /// No description provided for @registrationMotherAgeLabel.
  ///
  /// In en, this message translates to:
  /// **'Mother\'s Age (Optional)'**
  String get registrationMotherAgeLabel;

  /// No description provided for @registrationMotherAgeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter mother\'s age'**
  String get registrationMotherAgeHint;

  /// No description provided for @registrationMotherOccLabel.
  ///
  /// In en, this message translates to:
  /// **'Mother\'s Occupation (Optional)'**
  String get registrationMotherOccLabel;

  /// No description provided for @registrationMotherOccHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Homemaker'**
  String get registrationMotherOccHint;

  /// No description provided for @registrationFamilyTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Family Type'**
  String get registrationFamilyTypeLabel;

  /// No description provided for @registrationFamilyValuesLabel.
  ///
  /// In en, this message translates to:
  /// **'Family Values'**
  String get registrationFamilyValuesLabel;

  /// No description provided for @registrationFamilyStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Family Status'**
  String get registrationFamilyStatusLabel;

  /// No description provided for @registrationSiblingsSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Siblings'**
  String get registrationSiblingsSectionLabel;

  /// No description provided for @registrationSiblingBrotherLabel.
  ///
  /// In en, this message translates to:
  /// **'Brother'**
  String get registrationSiblingBrotherLabel;

  /// No description provided for @registrationSiblingSisterLabel.
  ///
  /// In en, this message translates to:
  /// **'Sister'**
  String get registrationSiblingSisterLabel;

  /// No description provided for @registrationRemoveSiblingLabel.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get registrationRemoveSiblingLabel;

  /// No description provided for @registrationSiblingNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name (Optional)'**
  String get registrationSiblingNameLabel;

  /// No description provided for @registrationSiblingNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter sibling\'s name'**
  String get registrationSiblingNameHint;

  /// No description provided for @registrationSiblingAgeLabel.
  ///
  /// In en, this message translates to:
  /// **'Age (Optional)'**
  String get registrationSiblingAgeLabel;

  /// No description provided for @registrationSiblingAgeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter sibling\'s age'**
  String get registrationSiblingAgeHint;

  /// No description provided for @registrationSiblingOccupationLabel.
  ///
  /// In en, this message translates to:
  /// **'Occupation (Optional)'**
  String get registrationSiblingOccupationLabel;

  /// No description provided for @registrationSiblingOccupationHint.
  ///
  /// In en, this message translates to:
  /// **'Enter sibling\'s occupation'**
  String get registrationSiblingOccupationHint;

  /// No description provided for @registrationAddSiblingLabel.
  ///
  /// In en, this message translates to:
  /// **'Add Sibling'**
  String get registrationAddSiblingLabel;

  /// No description provided for @famJoint.
  ///
  /// In en, this message translates to:
  /// **'Joint Family'**
  String get famJoint;

  /// No description provided for @famNuclear.
  ///
  /// In en, this message translates to:
  /// **'Nuclear Family'**
  String get famNuclear;

  /// No description provided for @famTraditional.
  ///
  /// In en, this message translates to:
  /// **'Traditional'**
  String get famTraditional;

  /// No description provided for @famModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get famModerate;

  /// No description provided for @famLiberal.
  ///
  /// In en, this message translates to:
  /// **'Liberal'**
  String get famLiberal;

  /// No description provided for @famMiddleClass.
  ///
  /// In en, this message translates to:
  /// **'Middle Class'**
  String get famMiddleClass;

  /// No description provided for @famUpperMiddleClass.
  ///
  /// In en, this message translates to:
  /// **'Upper Middle Class'**
  String get famUpperMiddleClass;

  /// No description provided for @famRich.
  ///
  /// In en, this message translates to:
  /// **'Rich'**
  String get famRich;

  /// No description provided for @famAffluent.
  ///
  /// In en, this message translates to:
  /// **'Affluent'**
  String get famAffluent;

  /// No description provided for @registrationHoroscopeTitle.
  ///
  /// In en, this message translates to:
  /// **'Horoscope'**
  String get registrationHoroscopeTitle;

  /// No description provided for @registrationHoroscopeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Astrological information (optional)'**
  String get registrationHoroscopeSubtitle;

  /// No description provided for @registrationHoroscopeAvailable.
  ///
  /// In en, this message translates to:
  /// **'Horoscope Available?'**
  String get registrationHoroscopeAvailable;

  /// No description provided for @registrationBirthTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Birth Time'**
  String get registrationBirthTimeLabel;

  /// No description provided for @registrationBirthTimeHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to select'**
  String get registrationBirthTimeHint;

  /// No description provided for @registrationBirthPlaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Birth Place'**
  String get registrationBirthPlaceLabel;

  /// No description provided for @registrationBirthPlaceHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Chennai'**
  String get registrationBirthPlaceHint;

  /// No description provided for @registrationRashiLabel.
  ///
  /// In en, this message translates to:
  /// **'Rashi (Moon Sign)'**
  String get registrationRashiLabel;

  /// No description provided for @registrationNakshatraLabel.
  ///
  /// In en, this message translates to:
  /// **'Nakshatra'**
  String get registrationNakshatraLabel;

  /// No description provided for @registrationStarLabel.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get registrationStarLabel;

  /// No description provided for @registrationManglikLabel.
  ///
  /// In en, this message translates to:
  /// **'Manglik / Sevvai'**
  String get registrationManglikLabel;

  /// No description provided for @registrationDoshamLabel.
  ///
  /// In en, this message translates to:
  /// **'Dosham'**
  String get registrationDoshamLabel;

  /// No description provided for @rashiMesha.
  ///
  /// In en, this message translates to:
  /// **'Mesha'**
  String get rashiMesha;

  /// No description provided for @rashiVrishabha.
  ///
  /// In en, this message translates to:
  /// **'Vrishabha'**
  String get rashiVrishabha;

  /// No description provided for @rashiMithuna.
  ///
  /// In en, this message translates to:
  /// **'Mithuna'**
  String get rashiMithuna;

  /// No description provided for @rashiKataka.
  ///
  /// In en, this message translates to:
  /// **'Kataka'**
  String get rashiKataka;

  /// No description provided for @rashiSimha.
  ///
  /// In en, this message translates to:
  /// **'Simha'**
  String get rashiSimha;

  /// No description provided for @rashiKanya.
  ///
  /// In en, this message translates to:
  /// **'Kanya'**
  String get rashiKanya;

  /// No description provided for @rashiTula.
  ///
  /// In en, this message translates to:
  /// **'Tula'**
  String get rashiTula;

  /// No description provided for @rashiVrischika.
  ///
  /// In en, this message translates to:
  /// **'Vrischika'**
  String get rashiVrischika;

  /// No description provided for @rashiDhanu.
  ///
  /// In en, this message translates to:
  /// **'Dhanu'**
  String get rashiDhanu;

  /// No description provided for @rashiMakara.
  ///
  /// In en, this message translates to:
  /// **'Makara'**
  String get rashiMakara;

  /// No description provided for @rashiKumbha.
  ///
  /// In en, this message translates to:
  /// **'Kumbha'**
  String get rashiKumbha;

  /// No description provided for @rashiMeena.
  ///
  /// In en, this message translates to:
  /// **'Meena'**
  String get rashiMeena;

  /// No description provided for @commonAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get commonAny;

  /// No description provided for @registrationPartnerTitle.
  ///
  /// In en, this message translates to:
  /// **'Partner Preferences'**
  String get registrationPartnerTitle;

  /// No description provided for @registrationPartnerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What are you looking for in a partner?'**
  String get registrationPartnerSubtitle;

  /// No description provided for @registrationPrefAgeLabel.
  ///
  /// In en, this message translates to:
  /// **'Preferred Age Range'**
  String get registrationPrefAgeLabel;

  /// No description provided for @registrationPrefHeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Preferred Height'**
  String get registrationPrefHeightLabel;

  /// No description provided for @registrationPrefReligionLabel.
  ///
  /// In en, this message translates to:
  /// **'Religion'**
  String get registrationPrefReligionLabel;

  /// No description provided for @registrationPrefCasteLabel.
  ///
  /// In en, this message translates to:
  /// **'Caste'**
  String get registrationPrefCasteLabel;

  /// No description provided for @registrationPrefEducationLabel.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get registrationPrefEducationLabel;

  /// No description provided for @registrationPrefOccupationLabel.
  ///
  /// In en, this message translates to:
  /// **'Occupation'**
  String get registrationPrefOccupationLabel;

  /// No description provided for @registrationPrefIncomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Annual Income'**
  String get registrationPrefIncomeLabel;

  /// No description provided for @registrationPrefLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get registrationPrefLocationLabel;

  /// No description provided for @registrationPrefMotherTongueLabel.
  ///
  /// In en, this message translates to:
  /// **'Mother Tongue'**
  String get registrationPrefMotherTongueLabel;

  /// No description provided for @registrationPrefMaritalLabel.
  ///
  /// In en, this message translates to:
  /// **'Marital Status'**
  String get registrationPrefMaritalLabel;

  /// No description provided for @registrationPartnerPrefSetLabel.
  ///
  /// In en, this message translates to:
  /// **'Your partner preferences are set'**
  String get registrationPartnerPrefSetLabel;

  /// No description provided for @registrationPartnerPrefNotSetLabel.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t set your partner preferences yet'**
  String get registrationPartnerPrefNotSetLabel;

  /// No description provided for @registrationSetPartnerPrefButton.
  ///
  /// In en, this message translates to:
  /// **'Set Partner Preferences'**
  String get registrationSetPartnerPrefButton;

  /// No description provided for @registrationEditPartnerPrefButton.
  ///
  /// In en, this message translates to:
  /// **'Edit Partner Preferences'**
  String get registrationEditPartnerPrefButton;

  /// No description provided for @prefCasteSame.
  ///
  /// In en, this message translates to:
  /// **'Same Caste'**
  String get prefCasteSame;

  /// No description provided for @prefCasteAny.
  ///
  /// In en, this message translates to:
  /// **'Any Caste'**
  String get prefCasteAny;

  /// No description provided for @prefCasteInter.
  ///
  /// In en, this message translates to:
  /// **'Inter-Caste OK'**
  String get prefCasteInter;

  /// No description provided for @prefEduAnyDegree.
  ///
  /// In en, this message translates to:
  /// **'Any Degree'**
  String get prefEduAnyDegree;

  /// No description provided for @prefOccSoftwareIt.
  ///
  /// In en, this message translates to:
  /// **'Software / IT'**
  String get prefOccSoftwareIt;

  /// No description provided for @prefLocSameCity.
  ///
  /// In en, this message translates to:
  /// **'Same City'**
  String get prefLocSameCity;

  /// No description provided for @prefLocSameState.
  ///
  /// In en, this message translates to:
  /// **'Same State'**
  String get prefLocSameState;

  /// No description provided for @prefLocAnywhereIndia.
  ///
  /// In en, this message translates to:
  /// **'Anywhere in India'**
  String get prefLocAnywhereIndia;

  /// No description provided for @prefLocNri.
  ///
  /// In en, this message translates to:
  /// **'NRI OK'**
  String get prefLocNri;

  /// No description provided for @prefTongueSame.
  ///
  /// In en, this message translates to:
  /// **'Same Mother Tongue'**
  String get prefTongueSame;

  /// No description provided for @prefMaritalDoesntMatter.
  ///
  /// In en, this message translates to:
  /// **'Doesn\'t Matter'**
  String get prefMaritalDoesntMatter;

  /// No description provided for @partnerPrefPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Partner Preferences'**
  String get partnerPrefPageTitle;

  /// No description provided for @partnerPrefSaveButton.
  ///
  /// In en, this message translates to:
  /// **'Save Preferences'**
  String get partnerPrefSaveButton;

  /// No description provided for @partnerPrefSavedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Partner preferences saved'**
  String get partnerPrefSavedSnackbar;

  /// No description provided for @partnerPrefSaveErrorSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Could not save preferences. Check your connection.'**
  String get partnerPrefSaveErrorSnackbar;

  /// No description provided for @partnerPrefNotSetPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get partnerPrefNotSetPlaceholder;

  /// No description provided for @partnerPrefDoesntMatter.
  ///
  /// In en, this message translates to:
  /// **'Doesn\'t Matter'**
  String get partnerPrefDoesntMatter;

  /// No description provided for @partnerPrefSectionBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic Preferences'**
  String get partnerPrefSectionBasic;

  /// No description provided for @partnerPrefSectionReligionCommunity.
  ///
  /// In en, this message translates to:
  /// **'Religion & Community'**
  String get partnerPrefSectionReligionCommunity;

  /// No description provided for @partnerPrefSectionEducationCareer.
  ///
  /// In en, this message translates to:
  /// **'Education & Career'**
  String get partnerPrefSectionEducationCareer;

  /// No description provided for @partnerPrefSectionFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get partnerPrefSectionFamily;

  /// No description provided for @partnerPrefSectionProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile Preferences'**
  String get partnerPrefSectionProfile;

  /// No description provided for @partnerPrefSectionLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle'**
  String get partnerPrefSectionLifestyle;

  /// No description provided for @partnerPrefSectionLocation.
  ///
  /// In en, this message translates to:
  /// **'Location Preferences'**
  String get partnerPrefSectionLocation;

  /// No description provided for @partnerPrefSectionSpecialCases.
  ///
  /// In en, this message translates to:
  /// **'Special Cases'**
  String get partnerPrefSectionSpecialCases;

  /// No description provided for @partnerPrefSectionVerification.
  ///
  /// In en, this message translates to:
  /// **'Verification & Other'**
  String get partnerPrefSectionVerification;

  /// No description provided for @partnerPrefEthnicityLabel.
  ///
  /// In en, this message translates to:
  /// **'Ethnicity / Community'**
  String get partnerPrefEthnicityLabel;

  /// No description provided for @partnerPrefSubCasteLabel.
  ///
  /// In en, this message translates to:
  /// **'Sub-Caste'**
  String get partnerPrefSubCasteLabel;

  /// No description provided for @partnerPrefMangalikLabel.
  ///
  /// In en, this message translates to:
  /// **'Mangalik Status'**
  String get partnerPrefMangalikLabel;

  /// No description provided for @partnerPrefMinEducationLabel.
  ///
  /// In en, this message translates to:
  /// **'Minimum Education'**
  String get partnerPrefMinEducationLabel;

  /// No description provided for @partnerPrefEducationLevelsLabel.
  ///
  /// In en, this message translates to:
  /// **'Preferred Education Levels'**
  String get partnerPrefEducationLevelsLabel;

  /// No description provided for @partnerPrefCollegesLabel.
  ///
  /// In en, this message translates to:
  /// **'Preferred Colleges / Universities'**
  String get partnerPrefCollegesLabel;

  /// No description provided for @partnerPrefFieldOfStudyLabel.
  ///
  /// In en, this message translates to:
  /// **'Field of Study'**
  String get partnerPrefFieldOfStudyLabel;

  /// No description provided for @partnerPrefIndustryLabel.
  ///
  /// In en, this message translates to:
  /// **'Industry'**
  String get partnerPrefIndustryLabel;

  /// No description provided for @partnerPrefEmploymentTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Employment Type'**
  String get partnerPrefEmploymentTypeLabel;

  /// No description provided for @partnerPrefFamilyStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Family Status'**
  String get partnerPrefFamilyStatusLabel;

  /// No description provided for @partnerPrefFamilyTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Family Type'**
  String get partnerPrefFamilyTypeLabel;

  /// No description provided for @partnerPrefFamilyValuesLabel.
  ///
  /// In en, this message translates to:
  /// **'Family Values'**
  String get partnerPrefFamilyValuesLabel;

  /// No description provided for @partnerPrefProfileManagedByLabel.
  ///
  /// In en, this message translates to:
  /// **'Profile Managed By'**
  String get partnerPrefProfileManagedByLabel;

  /// No description provided for @partnerPrefDietLabel.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get partnerPrefDietLabel;

  /// No description provided for @partnerPrefDrinkingLabel.
  ///
  /// In en, this message translates to:
  /// **'Drinking'**
  String get partnerPrefDrinkingLabel;

  /// No description provided for @partnerPrefSmokingLabel.
  ///
  /// In en, this message translates to:
  /// **'Smoking'**
  String get partnerPrefSmokingLabel;

  /// No description provided for @partnerPrefCountryLabel.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get partnerPrefCountryLabel;

  /// No description provided for @partnerPrefStateLabel.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get partnerPrefStateLabel;

  /// No description provided for @partnerPrefCityLabel.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get partnerPrefCityLabel;

  /// No description provided for @partnerPrefWillingToRelocateLabel.
  ///
  /// In en, this message translates to:
  /// **'Willing to Relocate'**
  String get partnerPrefWillingToRelocateLabel;

  /// No description provided for @partnerPrefNriAcceptedLabel.
  ///
  /// In en, this message translates to:
  /// **'NRI Accepted'**
  String get partnerPrefNriAcceptedLabel;

  /// No description provided for @partnerPrefDivorcedAcceptedLabel.
  ///
  /// In en, this message translates to:
  /// **'Divorced Accepted'**
  String get partnerPrefDivorcedAcceptedLabel;

  /// No description provided for @partnerPrefWidowedAcceptedLabel.
  ///
  /// In en, this message translates to:
  /// **'Widowed Accepted'**
  String get partnerPrefWidowedAcceptedLabel;

  /// No description provided for @partnerPrefAwaitingDivorceAcceptedLabel.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Divorce Accepted'**
  String get partnerPrefAwaitingDivorceAcceptedLabel;

  /// No description provided for @partnerPrefPhysicallyChallengedAcceptedLabel.
  ///
  /// In en, this message translates to:
  /// **'Physically Challenged Accepted'**
  String get partnerPrefPhysicallyChallengedAcceptedLabel;

  /// No description provided for @partnerPrefAnySpecialCaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Any Special Case'**
  String get partnerPrefAnySpecialCaseLabel;

  /// No description provided for @partnerPrefHoroscopeMatchRequiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Horoscope Match Required'**
  String get partnerPrefHoroscopeMatchRequiredLabel;

  /// No description provided for @partnerPrefVerifiedProfilesOnlyLabel.
  ///
  /// In en, this message translates to:
  /// **'Verified Profiles Only'**
  String get partnerPrefVerifiedProfilesOnlyLabel;

  /// No description provided for @partnerPrefHasProfilePhotoLabel.
  ///
  /// In en, this message translates to:
  /// **'Has Profile Photo'**
  String get partnerPrefHasProfilePhotoLabel;

  /// No description provided for @partnerPrefHasHoroscopeLabel.
  ///
  /// In en, this message translates to:
  /// **'Has Horoscope'**
  String get partnerPrefHasHoroscopeLabel;

  /// No description provided for @partnerPrefAadhaarVerifiedLabel.
  ///
  /// In en, this message translates to:
  /// **'Aadhaar Verified'**
  String get partnerPrefAadhaarVerifiedLabel;

  /// No description provided for @partnerPrefPhoneVerifiedLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Verified'**
  String get partnerPrefPhoneVerifiedLabel;

  /// No description provided for @partnerPrefMangalikMustBe.
  ///
  /// In en, this message translates to:
  /// **'Must be Mangalik'**
  String get partnerPrefMangalikMustBe;

  /// No description provided for @partnerPrefMangalikNon.
  ///
  /// In en, this message translates to:
  /// **'Non-Mangalik'**
  String get partnerPrefMangalikNon;

  /// No description provided for @partnerPrefDietVegetarian.
  ///
  /// In en, this message translates to:
  /// **'Vegetarian'**
  String get partnerPrefDietVegetarian;

  /// No description provided for @partnerPrefDietEggetarian.
  ///
  /// In en, this message translates to:
  /// **'Eggetarian'**
  String get partnerPrefDietEggetarian;

  /// No description provided for @partnerPrefDietVegan.
  ///
  /// In en, this message translates to:
  /// **'Vegan'**
  String get partnerPrefDietVegan;

  /// No description provided for @partnerPrefDietNonVegetarian.
  ///
  /// In en, this message translates to:
  /// **'Non-Vegetarian'**
  String get partnerPrefDietNonVegetarian;

  /// No description provided for @partnerPrefDrinkingNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get partnerPrefDrinkingNever;

  /// No description provided for @partnerPrefDrinkingOccasionally.
  ///
  /// In en, this message translates to:
  /// **'Occasionally'**
  String get partnerPrefDrinkingOccasionally;

  /// No description provided for @partnerPrefDrinkingSocially.
  ///
  /// In en, this message translates to:
  /// **'Socially'**
  String get partnerPrefDrinkingSocially;

  /// No description provided for @partnerPrefDrinkingRegularly.
  ///
  /// In en, this message translates to:
  /// **'Regularly'**
  String get partnerPrefDrinkingRegularly;

  /// No description provided for @partnerPrefSmokingNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get partnerPrefSmokingNever;

  /// No description provided for @partnerPrefSmokingOccasionally.
  ///
  /// In en, this message translates to:
  /// **'Occasionally'**
  String get partnerPrefSmokingOccasionally;

  /// No description provided for @partnerPrefSmokingRegularly.
  ///
  /// In en, this message translates to:
  /// **'Regularly'**
  String get partnerPrefSmokingRegularly;

  /// No description provided for @partnerPrefFamilyStatusMiddleClass.
  ///
  /// In en, this message translates to:
  /// **'Middle Class'**
  String get partnerPrefFamilyStatusMiddleClass;

  /// No description provided for @partnerPrefFamilyStatusUpperMiddleClass.
  ///
  /// In en, this message translates to:
  /// **'Upper Middle Class'**
  String get partnerPrefFamilyStatusUpperMiddleClass;

  /// No description provided for @partnerPrefFamilyStatusRich.
  ///
  /// In en, this message translates to:
  /// **'Rich'**
  String get partnerPrefFamilyStatusRich;

  /// No description provided for @partnerPrefFamilyStatusAffluent.
  ///
  /// In en, this message translates to:
  /// **'Affluent'**
  String get partnerPrefFamilyStatusAffluent;

  /// No description provided for @partnerPrefFamilyTypeJoint.
  ///
  /// In en, this message translates to:
  /// **'Joint Family'**
  String get partnerPrefFamilyTypeJoint;

  /// No description provided for @partnerPrefFamilyTypeNuclear.
  ///
  /// In en, this message translates to:
  /// **'Nuclear Family'**
  String get partnerPrefFamilyTypeNuclear;

  /// No description provided for @partnerPrefFamilyValuesTraditional.
  ///
  /// In en, this message translates to:
  /// **'Traditional'**
  String get partnerPrefFamilyValuesTraditional;

  /// No description provided for @partnerPrefFamilyValuesModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get partnerPrefFamilyValuesModerate;

  /// No description provided for @partnerPrefFamilyValuesLiberal.
  ///
  /// In en, this message translates to:
  /// **'Liberal'**
  String get partnerPrefFamilyValuesLiberal;

  /// No description provided for @partnerPrefManagedBySelf.
  ///
  /// In en, this message translates to:
  /// **'Self'**
  String get partnerPrefManagedBySelf;

  /// No description provided for @partnerPrefManagedByParent.
  ///
  /// In en, this message translates to:
  /// **'Parent'**
  String get partnerPrefManagedByParent;

  /// No description provided for @partnerPrefManagedBySibling.
  ///
  /// In en, this message translates to:
  /// **'Sibling'**
  String get partnerPrefManagedBySibling;

  /// No description provided for @partnerPrefManagedByRelative.
  ///
  /// In en, this message translates to:
  /// **'Relative'**
  String get partnerPrefManagedByRelative;

  /// No description provided for @partnerPrefManagedByGuardian.
  ///
  /// In en, this message translates to:
  /// **'Guardian'**
  String get partnerPrefManagedByGuardian;

  /// No description provided for @partnerPrefAcceptanceAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get partnerPrefAcceptanceAccepted;

  /// No description provided for @partnerPrefAcceptanceNotAccepted.
  ///
  /// In en, this message translates to:
  /// **'Not Accepted'**
  String get partnerPrefAcceptanceNotAccepted;

  /// No description provided for @partnerPrefRequirementRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get partnerPrefRequirementRequired;

  /// No description provided for @partnerPrefRequirementOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get partnerPrefRequirementOptional;

  /// No description provided for @drawerPartnerPreferences.
  ///
  /// In en, this message translates to:
  /// **'Partner Preferences'**
  String get drawerPartnerPreferences;

  /// No description provided for @registrationPhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get registrationPhotosTitle;

  /// No description provided for @registrationPhotosSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add photos to get 10x more responses'**
  String get registrationPhotosSubtitle;

  /// No description provided for @registrationPrimaryPhoto.
  ///
  /// In en, this message translates to:
  /// **'Primary Photo'**
  String get registrationPrimaryPhoto;

  /// No description provided for @registrationGalleryPhotos.
  ///
  /// In en, this message translates to:
  /// **'Gallery Photos'**
  String get registrationGalleryPhotos;

  /// No description provided for @registrationPhotosLocalNote.
  ///
  /// In en, this message translates to:
  /// **'Photos will be uploaded when backend integration is complete. Currently stored locally.'**
  String get registrationPhotosLocalNote;

  /// No description provided for @registrationAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add Photo'**
  String get registrationAddPhoto;

  /// No description provided for @registrationCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get registrationCamera;

  /// No description provided for @registrationCameraSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Take a new photo'**
  String get registrationCameraSubtitle;

  /// No description provided for @registrationGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get registrationGallery;

  /// No description provided for @registrationGallerySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get registrationGallerySubtitle;

  /// No description provided for @registrationVerificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification & Trust'**
  String get registrationVerificationTitle;

  /// No description provided for @registrationVerificationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get verified badges to build trust with matches'**
  String get registrationVerificationSubtitle;

  /// No description provided for @registrationVerifyMobileTitle.
  ///
  /// In en, this message translates to:
  /// **'Mobile Number Verification'**
  String get registrationVerifyMobileTitle;

  /// No description provided for @registrationVerifyMobileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mandatory for contacting profiles'**
  String get registrationVerifyMobileSubtitle;

  /// No description provided for @registrationVerifyEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Email Verification'**
  String get registrationVerifyEmailTitle;

  /// No description provided for @registrationVerifyEmailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Receive match alerts and account updates'**
  String get registrationVerifyEmailSubtitle;

  /// No description provided for @registrationVerifyFaceTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Face Selfie Verification'**
  String get registrationVerifyFaceTitle;

  /// No description provided for @registrationVerifyFaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get a blue tick badge on your profile photo'**
  String get registrationVerifyFaceSubtitle;

  /// No description provided for @registrationVerifyIdTitle.
  ///
  /// In en, this message translates to:
  /// **'Government ID / Aadhaar'**
  String get registrationVerifyIdTitle;

  /// No description provided for @registrationVerifyIdSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your age and identity securely'**
  String get registrationVerifyIdSubtitle;

  /// No description provided for @registrationVerifyIncomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Income Verification'**
  String get registrationVerifyIncomeTitle;

  /// No description provided for @registrationVerifyIncomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upload a document to verify your income'**
  String get registrationVerifyIncomeSubtitle;

  /// No description provided for @registrationVerifyAssetTitle.
  ///
  /// In en, this message translates to:
  /// **'Asset Verification'**
  String get registrationVerifyAssetTitle;

  /// No description provided for @registrationVerifyAssetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upload proof of assets for verification'**
  String get registrationVerifyAssetSubtitle;

  /// No description provided for @registrationVerifyNriTitle.
  ///
  /// In en, this message translates to:
  /// **'NRI Verification'**
  String get registrationVerifyNriTitle;

  /// No description provided for @registrationVerifyNriSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upload proof of your overseas residency status'**
  String get registrationVerifyNriSubtitle;

  /// No description provided for @registrationPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'100% Privacy Guaranteed'**
  String get registrationPrivacyTitle;

  /// No description provided for @registrationPrivacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your identity documents are encrypted and never shown publicly to any user.'**
  String get registrationPrivacySubtitle;

  /// No description provided for @registrationVerifyButton.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get registrationVerifyButton;

  /// No description provided for @registrationVerificationRetryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get registrationVerificationRetryButton;

  /// No description provided for @registrationVerificationPendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Pending Review'**
  String get registrationVerificationPendingLabel;

  /// No description provided for @registrationVerificationRejectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Verification Rejected'**
  String get registrationVerificationRejectedLabel;

  /// No description provided for @registrationVerificationFailedLabel.
  ///
  /// In en, this message translates to:
  /// **'Upload Failed'**
  String get registrationVerificationFailedLabel;

  /// No description provided for @registrationVerifyMobileRequiredHint.
  ///
  /// In en, this message translates to:
  /// **'Verify your mobile number to finish registration.'**
  String get registrationVerifyMobileRequiredHint;

  /// No description provided for @registrationProfileForTitle.
  ///
  /// In en, this message translates to:
  /// **'This Profile is for'**
  String get registrationProfileForTitle;

  /// No description provided for @registrationProfileForSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select the relationship'**
  String get registrationProfileForSubtitle;

  /// No description provided for @registrationProfileForLabel.
  ///
  /// In en, this message translates to:
  /// **'Profile for'**
  String get registrationProfileForLabel;

  /// No description provided for @profileForRelative.
  ///
  /// In en, this message translates to:
  /// **'Relative'**
  String get profileForRelative;

  /// No description provided for @profileForMyselfSub.
  ///
  /// In en, this message translates to:
  /// **'I am looking for a match for myself'**
  String get profileForMyselfSub;

  /// No description provided for @profileForSonSub.
  ///
  /// In en, this message translates to:
  /// **'Finding a match for my son'**
  String get profileForSonSub;

  /// No description provided for @profileForDaughterSub.
  ///
  /// In en, this message translates to:
  /// **'Finding a match for my daughter'**
  String get profileForDaughterSub;

  /// No description provided for @profileForBrotherSub.
  ///
  /// In en, this message translates to:
  /// **'Finding a match for my brother'**
  String get profileForBrotherSub;

  /// No description provided for @profileForSisterSub.
  ///
  /// In en, this message translates to:
  /// **'Finding a match for my sister'**
  String get profileForSisterSub;

  /// No description provided for @profileForRelativeSub.
  ///
  /// In en, this message translates to:
  /// **'Finding a match for a relative'**
  String get profileForRelativeSub;

  /// No description provided for @profileForFriendSub.
  ///
  /// In en, this message translates to:
  /// **'Finding a match for a friend'**
  String get profileForFriendSub;

  /// No description provided for @profileForOptionMyself.
  ///
  /// In en, this message translates to:
  /// **'Myself'**
  String get profileForOptionMyself;

  /// No description provided for @profileForOptionSon.
  ///
  /// In en, this message translates to:
  /// **'My Son'**
  String get profileForOptionSon;

  /// No description provided for @profileForOptionDaughter.
  ///
  /// In en, this message translates to:
  /// **'My Daughter'**
  String get profileForOptionDaughter;

  /// No description provided for @profileForOptionBrother.
  ///
  /// In en, this message translates to:
  /// **'My Brother'**
  String get profileForOptionBrother;

  /// No description provided for @profileForOptionSister.
  ///
  /// In en, this message translates to:
  /// **'My Sister'**
  String get profileForOptionSister;

  /// No description provided for @profileForOptionFriend.
  ///
  /// In en, this message translates to:
  /// **'My Friend'**
  String get profileForOptionFriend;

  /// No description provided for @profileForOptionRelative.
  ///
  /// In en, this message translates to:
  /// **'My Relative'**
  String get profileForOptionRelative;

  /// No description provided for @profileForNotice.
  ///
  /// In en, this message translates to:
  /// **'Nenjam is a space for people genuinely looking to marry. Profiles created with false details, or on behalf of a marriage bureau or any business, are removed from the platform.'**
  String get profileForNotice;

  /// No description provided for @onboardingNameHeadline.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get onboardingNameHeadline;

  /// No description provided for @onboardingNameDobSection.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get onboardingNameDobSection;

  /// No description provided for @onboardingNameDobHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter it as DD / MM / YYYY.'**
  String get onboardingNameDobHelp;

  /// No description provided for @profileBasicsSubCommunityLabel.
  ///
  /// In en, this message translates to:
  /// **'Sub-community'**
  String get profileBasicsSubCommunityLabel;

  /// No description provided for @profileBasicsSubCommunityHint.
  ///
  /// In en, this message translates to:
  /// **'Enter sub-community (optional)'**
  String get profileBasicsSubCommunityHint;

  /// No description provided for @profileBasicsHeadline.
  ///
  /// In en, this message translates to:
  /// **'Now let\'s build your Profile'**
  String get profileBasicsHeadline;

  /// No description provided for @profileBasicsStateHint.
  ///
  /// In en, this message translates to:
  /// **'State you live in'**
  String get profileBasicsStateHint;

  /// No description provided for @profileBasicsCityHint.
  ///
  /// In en, this message translates to:
  /// **'City you live in'**
  String get profileBasicsCityHint;

  /// No description provided for @loadingStates.
  ///
  /// In en, this message translates to:
  /// **'Loading states...'**
  String get loadingStates;

  /// No description provided for @couldntLoadStates.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load states'**
  String get couldntLoadStates;

  /// No description provided for @noStatesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No states available'**
  String get noStatesAvailable;

  /// No description provided for @findingCitiesIn.
  ///
  /// In en, this message translates to:
  /// **'Finding cities in {stateName}...'**
  String findingCitiesIn(String stateName);

  /// No description provided for @couldntLoadCities.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load cities'**
  String get couldntLoadCities;

  /// No description provided for @noCitiesFoundForState.
  ///
  /// In en, this message translates to:
  /// **'No cities found for this state'**
  String get noCitiesFoundForState;

  /// No description provided for @profileBasicsCasteNoBar.
  ///
  /// In en, this message translates to:
  /// **'Not particular about my partner\'s community (caste no bar)'**
  String get profileBasicsCasteNoBar;

  /// No description provided for @onboardingReligionHeadline.
  ///
  /// In en, this message translates to:
  /// **'Your religion'**
  String get onboardingReligionHeadline;

  /// No description provided for @onboardingReligionLabel.
  ///
  /// In en, this message translates to:
  /// **'Religion'**
  String get onboardingReligionLabel;

  /// No description provided for @onboardingReligionHint.
  ///
  /// In en, this message translates to:
  /// **'Select your religion'**
  String get onboardingReligionHint;

  /// No description provided for @loadingReligions.
  ///
  /// In en, this message translates to:
  /// **'Loading religions...'**
  String get loadingReligions;

  /// No description provided for @couldntLoadReligions.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load religions'**
  String get couldntLoadReligions;

  /// No description provided for @noReligionsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No religions available'**
  String get noReligionsAvailable;

  /// No description provided for @onboardingCommunityLabel.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get onboardingCommunityLabel;

  /// No description provided for @onboardingCommunityHint.
  ///
  /// In en, this message translates to:
  /// **'Select your community'**
  String get onboardingCommunityHint;

  /// No description provided for @loadingCommunities.
  ///
  /// In en, this message translates to:
  /// **'Loading communities...'**
  String get loadingCommunities;

  /// No description provided for @couldntLoadCommunities.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load communities'**
  String get couldntLoadCommunities;

  /// No description provided for @noCommunitiesFound.
  ///
  /// In en, this message translates to:
  /// **'No communities found'**
  String get noCommunitiesFound;

  /// No description provided for @onboardingCommunityHelp.
  ///
  /// In en, this message translates to:
  /// **'Your community is the group you identify with — for some families that is a caste, for others a language or region.'**
  String get onboardingCommunityHelp;

  /// No description provided for @onboardingLivingInLabel.
  ///
  /// In en, this message translates to:
  /// **'Living in'**
  String get onboardingLivingInLabel;

  /// No description provided for @onboardingLivingInHint.
  ///
  /// In en, this message translates to:
  /// **'Country you live in'**
  String get onboardingLivingInHint;

  /// No description provided for @onboardingContactHeadline.
  ///
  /// In en, this message translates to:
  /// **'An active email ID & phone no. are required to secure your profile'**
  String get onboardingContactHeadline;

  /// No description provided for @onboardingContactEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email ID'**
  String get onboardingContactEmailLabel;

  /// No description provided for @onboardingContactEmailHint.
  ///
  /// In en, this message translates to:
  /// **'your.name@example.com'**
  String get onboardingContactEmailHint;

  /// No description provided for @onboardingContactMobileLabel.
  ///
  /// In en, this message translates to:
  /// **'Mobile no.'**
  String get onboardingContactMobileLabel;

  /// No description provided for @onboardingContactMobileHint.
  ///
  /// In en, this message translates to:
  /// **'Mobile no.'**
  String get onboardingContactMobileHint;

  /// No description provided for @onboardingContactSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get onboardingContactSubmit;

  /// No description provided for @onboardingContactLegal.
  ///
  /// In en, this message translates to:
  /// **'By creating an account, you agree to our Privacy Policy and T&C.'**
  String get onboardingContactLegal;

  /// No description provided for @onboardingContactEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get onboardingContactEmailInvalid;

  /// No description provided for @onboardingContactMobileInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 10-digit mobile number.'**
  String get onboardingContactMobileInvalid;

  /// No description provided for @onboardingContactEmailLocked.
  ///
  /// In en, this message translates to:
  /// **'Already linked to your account.'**
  String get onboardingContactEmailLocked;

  /// No description provided for @onboardingContactMobileLocked.
  ///
  /// In en, this message translates to:
  /// **'Already linked to your account.'**
  String get onboardingContactMobileLocked;

  /// No description provided for @onboardingContactEmailLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send a confirmation to that address. Try again, or use a different one.'**
  String get onboardingContactEmailLinkFailed;

  /// No description provided for @onboardingMaritalHeadline.
  ///
  /// In en, this message translates to:
  /// **'Marital status'**
  String get onboardingMaritalHeadline;

  /// No description provided for @onboardingMaritalLabel.
  ///
  /// In en, this message translates to:
  /// **'Your marital status'**
  String get onboardingMaritalLabel;

  /// No description provided for @onboardingMaritalHint.
  ///
  /// In en, this message translates to:
  /// **'Select your marital status'**
  String get onboardingMaritalHint;

  /// No description provided for @onboardingHeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get onboardingHeightLabel;

  /// No description provided for @onboardingHeightFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Your height'**
  String get onboardingHeightFieldLabel;

  /// No description provided for @onboardingHeightHint.
  ///
  /// In en, this message translates to:
  /// **'Select your height'**
  String get onboardingHeightHint;

  /// No description provided for @onboardingDietLabel.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get onboardingDietLabel;

  /// No description provided for @onboardingDietFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Your diet'**
  String get onboardingDietFieldLabel;

  /// No description provided for @onboardingDietHint.
  ///
  /// In en, this message translates to:
  /// **'Select your diet'**
  String get onboardingDietHint;

  /// No description provided for @onboardingEducationEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Great! Few more details'**
  String get onboardingEducationEyebrow;

  /// No description provided for @onboardingEducationHeadline.
  ///
  /// In en, this message translates to:
  /// **'Highest qualification'**
  String get onboardingEducationHeadline;

  /// No description provided for @onboardingQualificationLabel.
  ///
  /// In en, this message translates to:
  /// **'Your highest qualification'**
  String get onboardingQualificationLabel;

  /// No description provided for @onboardingQualificationHint.
  ///
  /// In en, this message translates to:
  /// **'Select your qualification'**
  String get onboardingQualificationHint;

  /// No description provided for @onboardingCollegeLabel.
  ///
  /// In en, this message translates to:
  /// **'College'**
  String get onboardingCollegeLabel;

  /// No description provided for @onboardingCollegeFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'College you attended'**
  String get onboardingCollegeFieldLabel;

  /// No description provided for @onboardingCollegeHint.
  ///
  /// In en, this message translates to:
  /// **'College you attended'**
  String get onboardingCollegeHint;

  /// No description provided for @onboardingIncomeEyebrow.
  ///
  /// In en, this message translates to:
  /// **'You are almost done!'**
  String get onboardingIncomeEyebrow;

  /// No description provided for @onboardingIncomeHeadline.
  ///
  /// In en, this message translates to:
  /// **'Annual income'**
  String get onboardingIncomeHeadline;

  /// No description provided for @onboardingIncomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Your annual income'**
  String get onboardingIncomeLabel;

  /// No description provided for @onboardingIncomeHint.
  ///
  /// In en, this message translates to:
  /// **'Select your annual income'**
  String get onboardingIncomeHint;

  /// No description provided for @onboardingIncomeWhy.
  ///
  /// In en, this message translates to:
  /// **'Why is income required?'**
  String get onboardingIncomeWhy;

  /// No description provided for @onboardingIncomeWhyAnswer.
  ///
  /// In en, this message translates to:
  /// **'Income is one of the details members filter on, so adding it means your profile reaches the people actually looking for a match like you. It is never shown as an exact figure.'**
  String get onboardingIncomeWhyAnswer;

  /// No description provided for @onboardingWorkHeadline.
  ///
  /// In en, this message translates to:
  /// **'Work details'**
  String get onboardingWorkHeadline;

  /// No description provided for @onboardingWorkWithLabel.
  ///
  /// In en, this message translates to:
  /// **'You work with'**
  String get onboardingWorkWithLabel;

  /// No description provided for @onboardingWorkWithHint.
  ///
  /// In en, this message translates to:
  /// **'Select where you work'**
  String get onboardingWorkWithHint;

  /// No description provided for @onboardingWorkAsLabel.
  ///
  /// In en, this message translates to:
  /// **'You work as'**
  String get onboardingWorkAsLabel;

  /// No description provided for @onboardingWorkAsHint.
  ///
  /// In en, this message translates to:
  /// **'Select what you do'**
  String get onboardingWorkAsHint;

  /// No description provided for @onboardingCompanyLabel.
  ///
  /// In en, this message translates to:
  /// **'Your current company name'**
  String get onboardingCompanyLabel;

  /// No description provided for @onboardingCompanyHint.
  ///
  /// In en, this message translates to:
  /// **'Specify current organization'**
  String get onboardingCompanyHint;

  /// No description provided for @onboardingIncomeCta.
  ///
  /// In en, this message translates to:
  /// **'Create Profile'**
  String get onboardingIncomeCta;

  /// No description provided for @onboardingPhotosHeadline.
  ///
  /// In en, this message translates to:
  /// **'Add Photos to complete your Profile'**
  String get onboardingPhotosHeadline;

  /// No description provided for @onboardingPhotosSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Photo privacy controls are available in Settings.'**
  String get onboardingPhotosSubtitle;

  /// No description provided for @onboardingPhotosGallery.
  ///
  /// In en, this message translates to:
  /// **'Add from Gallery'**
  String get onboardingPhotosGallery;

  /// No description provided for @onboardingPhotosCamera.
  ///
  /// In en, this message translates to:
  /// **'Use Camera'**
  String get onboardingPhotosCamera;

  /// No description provided for @onboardingPhotosLater.
  ///
  /// In en, this message translates to:
  /// **'Add Photos Later'**
  String get onboardingPhotosLater;

  /// No description provided for @onboardingPhotosFailed.
  ///
  /// In en, this message translates to:
  /// **'That photo couldn\'t be uploaded. Try again.'**
  String get onboardingPhotosFailed;

  /// No description provided for @onboardingPhotosPendingFailed.
  ///
  /// In en, this message translates to:
  /// **'Your photo couldn\'t be uploaded. It\'s been kept — you can add it from Edit Profile.'**
  String get onboardingPhotosPendingFailed;

  /// No description provided for @onboardingPhotosPendingMissing.
  ///
  /// In en, this message translates to:
  /// **'A photo you added is no longer available on this device. Please select it again in Edit Profile.'**
  String get onboardingPhotosPendingMissing;

  /// No description provided for @onboardingPhotosAddedOne.
  ///
  /// In en, this message translates to:
  /// **'1 photo added.'**
  String get onboardingPhotosAddedOne;

  /// Confirms how many photos the member has uploaded so far
  ///
  /// In en, this message translates to:
  /// **'{count} photos added.'**
  String onboardingPhotosAddedMany(String count);

  /// No description provided for @onboardingAboutEyebrow.
  ///
  /// In en, this message translates to:
  /// **'We\'ve added a short description about you'**
  String get onboardingAboutEyebrow;

  /// No description provided for @onboardingAboutHeadline.
  ///
  /// In en, this message translates to:
  /// **'About yourself'**
  String get onboardingAboutHeadline;

  /// No description provided for @onboardingAboutHelper.
  ///
  /// In en, this message translates to:
  /// **'Edit the text above to make it more personal.'**
  String get onboardingAboutHelper;

  /// No description provided for @onboardingAboutRequired.
  ///
  /// In en, this message translates to:
  /// **'Tell us a little about yourself to continue.'**
  String get onboardingAboutRequired;

  /// No description provided for @accountExistsTitle.
  ///
  /// In en, this message translates to:
  /// **'Account already exists'**
  String get accountExistsTitle;

  /// No description provided for @accountExistsBoth.
  ///
  /// In en, this message translates to:
  /// **'This email or mobile number is already registered. Please log in to continue.'**
  String get accountExistsBoth;

  /// No description provided for @accountExistsEmail.
  ///
  /// In en, this message translates to:
  /// **'An account with this email is already registered. Please log in to continue.'**
  String get accountExistsEmail;

  /// No description provided for @accountExistsMobile.
  ///
  /// In en, this message translates to:
  /// **'This mobile number is already registered. Please log in to continue.'**
  String get accountExistsMobile;

  /// No description provided for @accountExistsLogIn.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get accountExistsLogIn;

  /// No description provided for @accountExistsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit details'**
  String get accountExistsEdit;

  /// No description provided for @accountCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to check your account right now. Please try again.'**
  String get accountCheckFailed;

  /// No description provided for @accountCheckRetry.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get accountCheckRetry;

  /// No description provided for @onboardingVerifyMobileHeadline.
  ///
  /// In en, this message translates to:
  /// **'Verify Mobile Number'**
  String get onboardingVerifyMobileHeadline;

  /// No description provided for @onboardingVerifyMobileSentTo.
  ///
  /// In en, this message translates to:
  /// **'Confirm this is the number to reach you on'**
  String get onboardingVerifyMobileSentTo;

  /// No description provided for @onboardingVerifyMobileEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get onboardingVerifyMobileEdit;

  /// No description provided for @onboardingVerifyMobileVerified.
  ///
  /// In en, this message translates to:
  /// **'Number verified successfully'**
  String get onboardingVerifyMobileVerified;

  /// No description provided for @authInvalidOtp.
  ///
  /// In en, this message translates to:
  /// **'That code isn\'t right. Check it and try again.'**
  String get authInvalidOtp;

  /// No description provided for @onboardingVerifyMobileEnter.
  ///
  /// In en, this message translates to:
  /// **'Enter any 4-digit code to continue.'**
  String get onboardingVerifyMobileEnter;

  /// No description provided for @onboardingVerifyMobileSessionFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not finish signing you in. Please try again.'**
  String get onboardingVerifyMobileSessionFailed;

  /// No description provided for @onboardingVerifyMobileRegistrationFailed.
  ///
  /// In en, this message translates to:
  /// **'Your number is verified, but we could not save your profile. Check your connection and tap Retry.'**
  String get onboardingVerifyMobileRegistrationFailed;

  /// No description provided for @authEntrySignUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get authEntrySignUp;

  /// No description provided for @authEntryLogin.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get authEntryLogin;

  /// Says which required fields on the Location & Sub-community step are still unanswered; {fields} is an already-joined list such as "state and city"
  ///
  /// In en, this message translates to:
  /// **'Select your {fields} to continue.'**
  String profileBasicsMissing(String fields);

  /// Joins the last two entries of the missing-field list
  ///
  /// In en, this message translates to:
  /// **'{first} and {second}'**
  String profileBasicsFieldJoin(String first, String second);

  /// No description provided for @profileBasicsPartnerPrefSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Saved your details, but we couldn\'t record the community preference. You can set it later in Partner Preferences.'**
  String get profileBasicsPartnerPrefSaveFailed;

  /// No description provided for @registrationProfileCreatedForLabel.
  ///
  /// In en, this message translates to:
  /// **'Profile Created For'**
  String get registrationProfileCreatedForLabel;

  /// No description provided for @relationSelf.
  ///
  /// In en, this message translates to:
  /// **'Self'**
  String get relationSelf;

  /// No description provided for @registrationFullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get registrationFullNameLabel;

  /// No description provided for @registrationFullNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter full name'**
  String get registrationFullNameHint;

  /// No description provided for @registrationRegisterContinue.
  ///
  /// In en, this message translates to:
  /// **'Register & Continue'**
  String get registrationRegisterContinue;

  /// No description provided for @registrationReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review Your Profile'**
  String get registrationReviewTitle;

  /// No description provided for @registrationProfileSummary.
  ///
  /// In en, this message translates to:
  /// **'Profile Summary'**
  String get registrationProfileSummary;

  /// No description provided for @registrationEnterApp.
  ///
  /// In en, this message translates to:
  /// **'Enter Nenjam Matrimony'**
  String get registrationEnterApp;

  /// No description provided for @registrationEditButton.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get registrationEditButton;

  /// No description provided for @registrationNoInfoYet.
  ///
  /// In en, this message translates to:
  /// **'No information added yet.'**
  String get registrationNoInfoYet;

  /// No description provided for @registrationProfileCompletePct.
  ///
  /// In en, this message translates to:
  /// **'Profile {percent}% Complete'**
  String registrationProfileCompletePct(int percent);

  /// No description provided for @registrationCompleteExcellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent! Your profile is ready to find matches.'**
  String get registrationCompleteExcellent;

  /// No description provided for @registrationCompleteMore.
  ///
  /// In en, this message translates to:
  /// **'Complete more sections to attract better matches.'**
  String get registrationCompleteMore;

  /// No description provided for @registrationWelcomeHeadline.
  ///
  /// In en, this message translates to:
  /// **'Let\'s build your story ❤️'**
  String get registrationWelcomeHeadline;

  /// No description provided for @registrationWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll get to know you a little better so we can introduce you to someone truly compatible.'**
  String get registrationWelcomeSubtitle;

  /// No description provided for @registrationWelcomeCta.
  ///
  /// In en, this message translates to:
  /// **'Begin My Journey'**
  String get registrationWelcomeCta;

  /// No description provided for @registrationMilestoneGettingStarted.
  ///
  /// In en, this message translates to:
  /// **'Getting Started'**
  String get registrationMilestoneGettingStarted;

  /// No description provided for @registrationMilestoneAboutYou.
  ///
  /// In en, this message translates to:
  /// **'About You'**
  String get registrationMilestoneAboutYou;

  /// No description provided for @registrationMilestoneYourWorld.
  ///
  /// In en, this message translates to:
  /// **'Your World'**
  String get registrationMilestoneYourWorld;

  /// No description provided for @registrationMilestoneLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle'**
  String get registrationMilestoneLifestyle;

  /// No description provided for @registrationMilestoneCompatibility.
  ///
  /// In en, this message translates to:
  /// **'Compatibility'**
  String get registrationMilestoneCompatibility;

  /// No description provided for @registrationMilestoneReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get registrationMilestoneReady;

  /// No description provided for @registrationTimeRemainingMinutes.
  ///
  /// In en, this message translates to:
  /// **'About {minutes} min left'**
  String registrationTimeRemainingMinutes(int minutes);

  /// No description provided for @registrationTimeRemainingLessThanMinute.
  ///
  /// In en, this message translates to:
  /// **'Less than a minute remaining'**
  String get registrationTimeRemainingLessThanMinute;

  /// No description provided for @registrationContinueYourStory.
  ///
  /// In en, this message translates to:
  /// **'Continue Your Story'**
  String get registrationContinueYourStory;

  /// No description provided for @registrationMotivationStep1.
  ///
  /// In en, this message translates to:
  /// **'You\'re doing great.'**
  String get registrationMotivationStep1;

  /// No description provided for @registrationMotivationStep2.
  ///
  /// In en, this message translates to:
  /// **'We\'re getting to know you.'**
  String get registrationMotivationStep2;

  /// No description provided for @registrationMotivationStep3.
  ///
  /// In en, this message translates to:
  /// **'This helps us recommend better matches.'**
  String get registrationMotivationStep3;

  /// No description provided for @registrationMotivationStep4.
  ///
  /// In en, this message translates to:
  /// **'You\'re off to a wonderful start.'**
  String get registrationMotivationStep4;

  /// No description provided for @registrationMotivationStep5.
  ///
  /// In en, this message translates to:
  /// **'Every detail helps us find the right match.'**
  String get registrationMotivationStep5;

  /// No description provided for @registrationMotivationStep6.
  ///
  /// In en, this message translates to:
  /// **'Halfway there — you\'re doing wonderfully.'**
  String get registrationMotivationStep6;

  /// No description provided for @registrationMotivationStep7.
  ///
  /// In en, this message translates to:
  /// **'This helps us understand what matters to you.'**
  String get registrationMotivationStep7;

  /// No description provided for @registrationMotivationStep8.
  ///
  /// In en, this message translates to:
  /// **'Almost there.'**
  String get registrationMotivationStep8;

  /// No description provided for @registrationMotivationStep9.
  ///
  /// In en, this message translates to:
  /// **'Just a few more details.'**
  String get registrationMotivationStep9;

  /// No description provided for @registrationMotivationQuiz.
  ///
  /// In en, this message translates to:
  /// **'This helps us understand what makes you, you.'**
  String get registrationMotivationQuiz;

  /// No description provided for @registrationMotivationStep10.
  ///
  /// In en, this message translates to:
  /// **'You\'ve already completed most of your story.'**
  String get registrationMotivationStep10;

  /// No description provided for @registrationMotivationStep11.
  ///
  /// In en, this message translates to:
  /// **'So close to meeting your matches.'**
  String get registrationMotivationStep11;

  /// No description provided for @registrationMotivationStep12.
  ///
  /// In en, this message translates to:
  /// **'One last step to complete your story.'**
  String get registrationMotivationStep12;

  /// No description provided for @registrationTipBasicInfo.
  ///
  /// In en, this message translates to:
  /// **'Your age is only used to improve compatibility.'**
  String get registrationTipBasicInfo;

  /// No description provided for @registrationTipReligion.
  ///
  /// In en, this message translates to:
  /// **'This helps us match you within your community preferences.'**
  String get registrationTipReligion;

  /// No description provided for @registrationTipLanguage.
  ///
  /// In en, this message translates to:
  /// **'Shared languages make conversations easier from day one.'**
  String get registrationTipLanguage;

  /// No description provided for @registrationTipLocation.
  ///
  /// In en, this message translates to:
  /// **'We use this to suggest matches nearby or wherever you\'d like.'**
  String get registrationTipLocation;

  /// No description provided for @registrationTipEducation.
  ///
  /// In en, this message translates to:
  /// **'Your background helps us find someone who complements your journey.'**
  String get registrationTipEducation;

  /// No description provided for @registrationTipPhysical.
  ///
  /// In en, this message translates to:
  /// **'These details help us fine-tune your compatibility profile.'**
  String get registrationTipPhysical;

  /// No description provided for @registrationTipLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Shared lifestyles often lead to stronger relationships.'**
  String get registrationTipLifestyle;

  /// No description provided for @registrationTipFamily.
  ///
  /// In en, this message translates to:
  /// **'Family details help us recommend compatible families.'**
  String get registrationTipFamily;

  /// No description provided for @registrationTipHoroscope.
  ///
  /// In en, this message translates to:
  /// **'This step is optional but improves astrology compatibility.'**
  String get registrationTipHoroscope;

  /// No description provided for @registrationTipQuiz.
  ///
  /// In en, this message translates to:
  /// **'This step is optional but improves match quality.'**
  String get registrationTipQuiz;

  /// No description provided for @registrationTipPartnerPref.
  ///
  /// In en, this message translates to:
  /// **'You can always update these later.'**
  String get registrationTipPartnerPref;

  /// No description provided for @registrationTipPhotos.
  ///
  /// In en, this message translates to:
  /// **'Natural, smiling photos receive more interest.'**
  String get registrationTipPhotos;

  /// No description provided for @registrationTipVerification.
  ///
  /// In en, this message translates to:
  /// **'Verified profiles earn more trust and better responses.'**
  String get registrationTipVerification;

  /// No description provided for @registrationWizardBasicInfoHeadline.
  ///
  /// In en, this message translates to:
  /// **'Tell us about yourself ❤️'**
  String get registrationWizardBasicInfoHeadline;

  /// No description provided for @registrationWizardBasicInfoHook.
  ///
  /// In en, this message translates to:
  /// **'Every great relationship starts with a simple introduction.'**
  String get registrationWizardBasicInfoHook;

  /// No description provided for @registrationWizardReligionHeadline.
  ///
  /// In en, this message translates to:
  /// **'Your roots & beliefs'**
  String get registrationWizardReligionHeadline;

  /// No description provided for @registrationWizardReligionHook.
  ///
  /// In en, this message translates to:
  /// **'Help us understand where you come from.'**
  String get registrationWizardReligionHook;

  /// No description provided for @registrationWizardLanguageHeadline.
  ///
  /// In en, this message translates to:
  /// **'The languages of your heart'**
  String get registrationWizardLanguageHeadline;

  /// No description provided for @registrationWizardLanguageHook.
  ///
  /// In en, this message translates to:
  /// **'Tell us how you love to communicate.'**
  String get registrationWizardLanguageHook;

  /// No description provided for @registrationWizardLocationHeadline.
  ///
  /// In en, this message translates to:
  /// **'Where your story is unfolding'**
  String get registrationWizardLocationHeadline;

  /// No description provided for @registrationWizardLocationHook.
  ///
  /// In en, this message translates to:
  /// **'Let us know where to find you.'**
  String get registrationWizardLocationHook;

  /// No description provided for @registrationWizardEducationHeadline.
  ///
  /// In en, this message translates to:
  /// **'Your journey so far'**
  String get registrationWizardEducationHeadline;

  /// No description provided for @registrationWizardEducationHook.
  ///
  /// In en, this message translates to:
  /// **'Tell us about your studies and career.'**
  String get registrationWizardEducationHook;

  /// No description provided for @registrationWizardPhysicalHeadline.
  ///
  /// In en, this message translates to:
  /// **'A little about your appearance'**
  String get registrationWizardPhysicalHeadline;

  /// No description provided for @registrationWizardPhysicalHook.
  ///
  /// In en, this message translates to:
  /// **'Just a few details to complete the picture.'**
  String get registrationWizardPhysicalHook;

  /// No description provided for @registrationWizardLifestyleHeadline.
  ///
  /// In en, this message translates to:
  /// **'How do you spend your days?'**
  String get registrationWizardLifestyleHeadline;

  /// No description provided for @registrationWizardLifestyleHook.
  ///
  /// In en, this message translates to:
  /// **'Help us understand your lifestyle and what makes you, you.'**
  String get registrationWizardLifestyleHook;

  /// No description provided for @registrationWizardFamilyHeadline.
  ///
  /// In en, this message translates to:
  /// **'Tell us about your family'**
  String get registrationWizardFamilyHeadline;

  /// No description provided for @registrationWizardFamilyHook.
  ///
  /// In en, this message translates to:
  /// **'Family is an important part of every journey.'**
  String get registrationWizardFamilyHook;

  /// No description provided for @registrationWizardHoroscopeHeadline.
  ///
  /// In en, this message translates to:
  /// **'Your stars can tell part of the story'**
  String get registrationWizardHoroscopeHeadline;

  /// No description provided for @registrationWizardHoroscopeHook.
  ///
  /// In en, this message translates to:
  /// **'This step is optional but helps us improve compatibility.'**
  String get registrationWizardHoroscopeHook;

  /// No description provided for @registrationWizardQuizHeadline.
  ///
  /// In en, this message translates to:
  /// **'What makes you, you?'**
  String get registrationWizardQuizHeadline;

  /// No description provided for @registrationWizardQuizHook.
  ///
  /// In en, this message translates to:
  /// **'Short, scenario-based questions about what you expect from married life.'**
  String get registrationWizardQuizHook;

  /// No description provided for @registrationWizardPartnerHeadline.
  ///
  /// In en, this message translates to:
  /// **'Who are you hoping to meet?'**
  String get registrationWizardPartnerHeadline;

  /// No description provided for @registrationWizardPartnerHook.
  ///
  /// In en, this message translates to:
  /// **'Tell us about the kind of person you\'re looking for.'**
  String get registrationWizardPartnerHook;

  /// No description provided for @registrationWizardPhotosHeadline.
  ///
  /// In en, this message translates to:
  /// **'Let your smile tell your story'**
  String get registrationWizardPhotosHeadline;

  /// No description provided for @registrationWizardPhotosHook.
  ///
  /// In en, this message translates to:
  /// **'People connect with genuine photos.'**
  String get registrationWizardPhotosHook;

  /// No description provided for @registrationWizardVerificationHeadline.
  ///
  /// In en, this message translates to:
  /// **'Building trust, together'**
  String get registrationWizardVerificationHeadline;

  /// No description provided for @registrationWizardVerificationHook.
  ///
  /// In en, this message translates to:
  /// **'A few quick checks to keep everyone\'s story safe.'**
  String get registrationWizardVerificationHook;

  /// No description provided for @registrationCompletingHeadline.
  ///
  /// In en, this message translates to:
  /// **'Creating your compatibility profile...'**
  String get registrationCompletingHeadline;

  /// No description provided for @registrationCompletingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This will only take a moment.'**
  String get registrationCompletingSubtitle;

  /// No description provided for @registrationCompletingStage1.
  ///
  /// In en, this message translates to:
  /// **'Saving your profile'**
  String get registrationCompletingStage1;

  /// No description provided for @registrationCompletingStage2.
  ///
  /// In en, this message translates to:
  /// **'Preparing your compatibility profile'**
  String get registrationCompletingStage2;

  /// No description provided for @registrationCompletingStage3.
  ///
  /// In en, this message translates to:
  /// **'Finding meaningful matches'**
  String get registrationCompletingStage3;

  /// No description provided for @registrationCompletingStage4.
  ///
  /// In en, this message translates to:
  /// **'Personalizing your experience'**
  String get registrationCompletingStage4;

  /// No description provided for @registrationCompletingErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get registrationCompletingErrorTitle;

  /// No description provided for @registrationCompletingErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t save your profile. Please check your connection and try again.'**
  String get registrationCompletingErrorMessage;

  /// No description provided for @registrationCompletingRetryCta.
  ///
  /// In en, this message translates to:
  /// **'Back to Review'**
  String get registrationCompletingRetryCta;

  /// No description provided for @registrationSuccessHeadline.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Nenjam ❤️'**
  String get registrationSuccessHeadline;

  /// No description provided for @registrationSuccessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your story is ready. We\'ve already started finding meaningful connections for you.'**
  String get registrationSuccessSubtitle;

  /// No description provided for @registrationSuccessCompletionCard.
  ///
  /// In en, this message translates to:
  /// **'Profile {percent}% Complete'**
  String registrationSuccessCompletionCard(int percent);

  /// No description provided for @registrationSuccessPhotosAdded.
  ///
  /// In en, this message translates to:
  /// **'Photos Added'**
  String get registrationSuccessPhotosAdded;

  /// No description provided for @registrationSuccessPhotosSkipped.
  ///
  /// In en, this message translates to:
  /// **'Photos Skipped'**
  String get registrationSuccessPhotosSkipped;

  /// No description provided for @registrationSuccessHoroscopeDone.
  ///
  /// In en, this message translates to:
  /// **'Horoscope Ready'**
  String get registrationSuccessHoroscopeDone;

  /// No description provided for @registrationSuccessHoroscopeSkipped.
  ///
  /// In en, this message translates to:
  /// **'Horoscope Skipped'**
  String get registrationSuccessHoroscopeSkipped;

  /// No description provided for @registrationSuccessPartnerPrefSaved.
  ///
  /// In en, this message translates to:
  /// **'Partner Preferences Saved'**
  String get registrationSuccessPartnerPrefSaved;

  /// No description provided for @registrationSuccessCta.
  ///
  /// In en, this message translates to:
  /// **'Meet Your First Match'**
  String get registrationSuccessCta;

  /// No description provided for @profileCompletionScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile Strength'**
  String get profileCompletionScreenTitle;

  /// No description provided for @profileCompletionScreenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See how complete your story is — and what to do next.'**
  String get profileCompletionScreenSubtitle;

  /// No description provided for @profileCompletionTierBuilding.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get profileCompletionTierBuilding;

  /// No description provided for @profileCompletionTierGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get profileCompletionTierGood;

  /// No description provided for @profileCompletionTierStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get profileCompletionTierStrong;

  /// No description provided for @profileCompletionTierExceptional.
  ///
  /// In en, this message translates to:
  /// **'Exceptional'**
  String get profileCompletionTierExceptional;

  /// No description provided for @profileCompletionCompletedSectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Story So Far'**
  String get profileCompletionCompletedSectionsTitle;

  /// No description provided for @profileCompletionRegistrationGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Registration information'**
  String get profileCompletionRegistrationGroupTitle;

  /// No description provided for @profileCompletionMissingSectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Still Growing'**
  String get profileCompletionMissingSectionsTitle;

  /// No description provided for @profileCompletionFutureGrowthTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep Growing Your Profile'**
  String get profileCompletionFutureGrowthTitle;

  /// No description provided for @profileCompletionFutureGrowthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Even a complete profile can go further.'**
  String get profileCompletionFutureGrowthSubtitle;

  /// No description provided for @profileCompletionModuleRegistration.
  ///
  /// In en, this message translates to:
  /// **'Your Story'**
  String get profileCompletionModuleRegistration;

  /// No description provided for @profileCompletionTipRegistration.
  ///
  /// In en, this message translates to:
  /// **'Every detail helps us find your best match.'**
  String get profileCompletionTipRegistration;

  /// No description provided for @profileCompletionActionRegistration.
  ///
  /// In en, this message translates to:
  /// **'Complete Your Story'**
  String get profileCompletionActionRegistration;

  /// No description provided for @profileCompletionActionPhotos.
  ///
  /// In en, this message translates to:
  /// **'Boost Your Match Quality'**
  String get profileCompletionActionPhotos;

  /// No description provided for @profileCompletionActionPartnerPref.
  ///
  /// In en, this message translates to:
  /// **'Sharpen Your Matches'**
  String get profileCompletionActionPartnerPref;

  /// No description provided for @profileCompletionActionVerification.
  ///
  /// In en, this message translates to:
  /// **'Get Verified'**
  String get profileCompletionActionVerification;

  /// No description provided for @profileCompletionActionHoroscope.
  ///
  /// In en, this message translates to:
  /// **'Deepen Your Compatibility'**
  String get profileCompletionActionHoroscope;

  /// No description provided for @profileCompletionActionEducation.
  ///
  /// In en, this message translates to:
  /// **'Complete Your Education & Career'**
  String get profileCompletionActionEducation;

  /// No description provided for @profileCompletionActionPhysical.
  ///
  /// In en, this message translates to:
  /// **'Add Your Physical Details'**
  String get profileCompletionActionPhysical;

  /// No description provided for @profileCompletionActionLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Share Your Lifestyle'**
  String get profileCompletionActionLifestyle;

  /// No description provided for @profileCompletionActionFamily.
  ///
  /// In en, this message translates to:
  /// **'Complete Your Family Details'**
  String get profileCompletionActionFamily;

  /// No description provided for @profileCompletionActionPsychology.
  ///
  /// In en, this message translates to:
  /// **'Take the Psychology Assessment'**
  String get profileCompletionActionPsychology;

  /// No description provided for @profileCompletionGrowthPsychology.
  ///
  /// In en, this message translates to:
  /// **'Psychology Assessment'**
  String get profileCompletionGrowthPsychology;

  /// No description provided for @profileCompletionGrowthPsychologySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share your expectations for married life.'**
  String get profileCompletionGrowthPsychologySubtitle;

  /// No description provided for @profileCompletionGrowthHoroscope.
  ///
  /// In en, this message translates to:
  /// **'Horoscope Compatibility'**
  String get profileCompletionGrowthHoroscope;

  /// No description provided for @profileCompletionGrowthHoroscopeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See your astrological match insights.'**
  String get profileCompletionGrowthHoroscopeSubtitle;

  /// No description provided for @profileCompletionGrowthPremium.
  ///
  /// In en, this message translates to:
  /// **'Nenjam Premium'**
  String get profileCompletionGrowthPremium;

  /// No description provided for @profileCompletionGrowthPremiumSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get 5x more visibility.'**
  String get profileCompletionGrowthPremiumSubtitle;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingAiTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Matchmaking'**
  String get onboardingAiTitle;

  /// No description provided for @onboardingAiDescription.
  ///
  /// In en, this message translates to:
  /// **'Find your perfect partner with our advanced AI-driven compatibility engine.'**
  String get onboardingAiDescription;

  /// No description provided for @onboardingAiBadge.
  ///
  /// In en, this message translates to:
  /// **'AI Matching'**
  String get onboardingAiBadge;

  /// No description provided for @onboardingAiBadgeSub.
  ///
  /// In en, this message translates to:
  /// **'Optimal compatibility'**
  String get onboardingAiBadgeSub;

  /// No description provided for @onboardingVerifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Verified Profiles'**
  String get onboardingVerifiedTitle;

  /// No description provided for @onboardingVerifiedDescription.
  ///
  /// In en, this message translates to:
  /// **'Every profile is manually verified to ensure a safe and trustworthy experience.'**
  String get onboardingVerifiedDescription;

  /// No description provided for @onboardingVerifiedBadge.
  ///
  /// In en, this message translates to:
  /// **'Secure'**
  String get onboardingVerifiedBadge;

  /// No description provided for @onboardingAstroTitle.
  ///
  /// In en, this message translates to:
  /// **'Astro Compatibility'**
  String get onboardingAstroTitle;

  /// No description provided for @onboardingAstroDescription.
  ///
  /// In en, this message translates to:
  /// **'Discover celestial alignment with detailed Kundli and Guna matching.'**
  String get onboardingAstroDescription;

  /// No description provided for @onboardingAstroBadgeGuna.
  ///
  /// In en, this message translates to:
  /// **'36/36 Guna'**
  String get onboardingAstroBadgeGuna;

  /// No description provided for @onboardingAstroBadgeKundli.
  ///
  /// In en, this message translates to:
  /// **'Kundli Match'**
  String get onboardingAstroBadgeKundli;

  /// No description provided for @onboardingAstroSync.
  ///
  /// In en, this message translates to:
  /// **'Astro Sync'**
  String get onboardingAstroSync;

  /// No description provided for @drawerProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get drawerProfile;

  /// No description provided for @drawerEditProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get drawerEditProfile;

  /// No description provided for @drawerHoroscope.
  ///
  /// In en, this message translates to:
  /// **'Horoscope'**
  String get drawerHoroscope;

  /// No description provided for @drawerFamilyDetails.
  ///
  /// In en, this message translates to:
  /// **'Family Details'**
  String get drawerFamilyDetails;

  /// No description provided for @drawerPsychology.
  ///
  /// In en, this message translates to:
  /// **'Psychology'**
  String get drawerPsychology;

  /// No description provided for @drawerVerificationCenter.
  ///
  /// In en, this message translates to:
  /// **'Verification Center'**
  String get drawerVerificationCenter;

  /// No description provided for @drawerInterestSent.
  ///
  /// In en, this message translates to:
  /// **'Interests Sent'**
  String get drawerInterestSent;

  /// No description provided for @drawerInterestReceived.
  ///
  /// In en, this message translates to:
  /// **'Interests Received'**
  String get drawerInterestReceived;

  /// No description provided for @drawerShortlist.
  ///
  /// In en, this message translates to:
  /// **'Shortlisted Profiles'**
  String get drawerShortlist;

  /// No description provided for @shortlistRemoveButton.
  ///
  /// In en, this message translates to:
  /// **'Remove from Shortlist'**
  String get shortlistRemoveButton;

  /// No description provided for @shortlistEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No shortlisted profiles yet'**
  String get shortlistEmptyTitle;

  /// No description provided for @shortlistEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Save profiles you\'re interested in and find them here.'**
  String get shortlistEmptyMessage;

  /// No description provided for @shortlistExploreProfiles.
  ///
  /// In en, this message translates to:
  /// **'Explore Profiles'**
  String get shortlistExploreProfiles;

  /// No description provided for @shortlistActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update shortlist. Please try again.'**
  String get shortlistActionFailed;

  /// No description provided for @profileViewersTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile Viewers'**
  String get profileViewersTitle;

  /// No description provided for @profileViewersEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No one has viewed your profile yet'**
  String get profileViewersEmptyTitle;

  /// No description provided for @profileViewersEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile and send interests to get noticed.'**
  String get profileViewersEmptyMessage;

  /// No description provided for @profileViewersViewedJustNow.
  ///
  /// In en, this message translates to:
  /// **'Viewed just now'**
  String get profileViewersViewedJustNow;

  /// No description provided for @profileViewersViewedMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'Viewed {count,plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String profileViewersViewedMinutesAgo(int count);

  /// No description provided for @profileViewersViewedHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'Viewed {count,plural, =1{1 hour ago} other{{count} hours ago}}'**
  String profileViewersViewedHoursAgo(int count);

  /// No description provided for @profileViewersViewedDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'Viewed {count,plural, =1{1 day ago} other{{count} days ago}}'**
  String profileViewersViewedDaysAgo(int count);

  /// No description provided for @privacyVisibilitySection.
  ///
  /// In en, this message translates to:
  /// **'Profile Visibility'**
  String get privacyVisibilitySection;

  /// No description provided for @privacyHideProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide My Profile'**
  String get privacyHideProfileTitle;

  /// No description provided for @privacyHideProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Don\'t show my profile in Discover, Search or Near Me'**
  String get privacyHideProfileSubtitle;

  /// No description provided for @privacyHidePhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide Photos from Non-Connections'**
  String get privacyHidePhotosTitle;

  /// No description provided for @privacyHidePhotosSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only accepted connections can see your photos'**
  String get privacyHidePhotosSubtitle;

  /// No description provided for @privacyLoadErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Privacy settings aren\'t available from the backend yet.'**
  String get privacyLoadErrorMessage;

  /// No description provided for @privacySaveErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your changes. Please try again.'**
  String get privacySaveErrorMessage;

  /// No description provided for @privacyBlockedSection.
  ///
  /// In en, this message translates to:
  /// **'Blocked Profiles'**
  String get privacyBlockedSection;

  /// No description provided for @privacyBlockedEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No Blocked Profiles'**
  String get privacyBlockedEmptyTitle;

  /// No description provided for @privacyBlockedEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Profiles you block will appear here.'**
  String get privacyBlockedEmptyMessage;

  /// No description provided for @privacyUnblockLabel.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get privacyUnblockLabel;

  /// No description provided for @privacyBlockedStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get privacyBlockedStatusLabel;

  /// No description provided for @privacyBlockedOnLabel.
  ///
  /// In en, this message translates to:
  /// **'Blocked on {date}'**
  String privacyBlockedOnLabel(String date);

  /// No description provided for @drawerLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get drawerLanguage;

  /// No description provided for @drawerSettings.
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get drawerSettings;

  /// No description provided for @drawerPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Safety'**
  String get drawerPrivacy;

  /// No description provided for @drawerHelp.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get drawerHelp;

  /// No description provided for @drawerLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get drawerLogout;

  /// No description provided for @supportContactTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get supportContactTitle;

  /// No description provided for @supportBugReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report a Bug'**
  String get supportBugReportTitle;

  /// No description provided for @supportFeatureRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Feature Request'**
  String get supportFeatureRequestTitle;

  /// No description provided for @supportAppFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'App Feedback'**
  String get supportAppFeedbackTitle;

  /// No description provided for @supportEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Email Support'**
  String get supportEmailTitle;

  /// No description provided for @supportEmailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'support@nenjammatrimony.com'**
  String get supportEmailSubtitle;

  /// No description provided for @supportTicketHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Ticket History'**
  String get supportTicketHistoryTitle;

  /// No description provided for @supportTicketFormSubjectLabel.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get supportTicketFormSubjectLabel;

  /// No description provided for @supportTicketFormSubjectHint.
  ///
  /// In en, this message translates to:
  /// **'Briefly describe your request'**
  String get supportTicketFormSubjectHint;

  /// No description provided for @supportTicketFormMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get supportTicketFormMessageLabel;

  /// No description provided for @supportTicketFormMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Share as much detail as you can'**
  String get supportTicketFormMessageHint;

  /// No description provided for @supportTicketFormSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get supportTicketFormSubmit;

  /// No description provided for @supportTicketFormValidationError.
  ///
  /// In en, this message translates to:
  /// **'Please fill in both fields'**
  String get supportTicketFormValidationError;

  /// No description provided for @supportTicketFormSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get supportTicketFormSuccessTitle;

  /// No description provided for @supportTicketFormSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Thanks — we\'ve received your request.'**
  String get supportTicketFormSuccessMessage;

  /// No description provided for @supportTicketFormErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t submit your request — this feature isn\'t live on the backend yet.'**
  String get supportTicketFormErrorMessage;

  /// No description provided for @supportTicketHistoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No Tickets Yet'**
  String get supportTicketHistoryEmptyTitle;

  /// No description provided for @supportTicketHistoryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Requests you submit will show up here.'**
  String get supportTicketHistoryEmptyMessage;

  /// No description provided for @supportTicketHistoryErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Ticket history isn\'t available from the backend yet.'**
  String get supportTicketHistoryErrorMessage;

  /// No description provided for @drawerProfileStrength.
  ///
  /// In en, this message translates to:
  /// **'Profile Strength'**
  String get drawerProfileStrength;

  /// No description provided for @drawerCompleteProfile.
  ///
  /// In en, this message translates to:
  /// **'Complete Profile'**
  String get drawerCompleteProfile;

  /// No description provided for @drawerPremiumTitle.
  ///
  /// In en, this message translates to:
  /// **'Nenjam Premium'**
  String get drawerPremiumTitle;

  /// No description provided for @drawerPremiumSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get 5x more visibility'**
  String get drawerPremiumSubtitle;

  /// No description provided for @drawerUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade Now'**
  String get drawerUpgrade;

  /// No description provided for @drawerVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Nenjam Matrimony'**
  String get drawerVersionLabel;

  /// No description provided for @drawerManagePhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Photos'**
  String get drawerManagePhotosTitle;

  /// No description provided for @drawerChangePhotoSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Change profile photo'**
  String get drawerChangePhotoSemanticLabel;

  /// No description provided for @profileDetailSendInterest.
  ///
  /// In en, this message translates to:
  /// **'Send Interest'**
  String get profileDetailSendInterest;

  /// No description provided for @profileDetailInterestSent.
  ///
  /// In en, this message translates to:
  /// **'Interest Sent'**
  String get profileDetailInterestSent;

  /// No description provided for @profileDetailStartConversation.
  ///
  /// In en, this message translates to:
  /// **'Start Conversation'**
  String get profileDetailStartConversation;

  /// No description provided for @profileDetailVideoCall.
  ///
  /// In en, this message translates to:
  /// **'Video Call'**
  String get profileDetailVideoCall;

  /// No description provided for @profileDetailVideoComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Video calling is coming soon'**
  String get profileDetailVideoComingSoon;

  /// No description provided for @profileDetailShareComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Share coming soon'**
  String get profileDetailShareComingSoon;

  /// No description provided for @interestStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get interestStatusPending;

  /// No description provided for @interestStatusAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get interestStatusAccepted;

  /// No description provided for @interestStatusDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get interestStatusDeclined;

  /// No description provided for @interestsWithdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get interestsWithdraw;

  /// No description provided for @interestsActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get interestsActionFailed;

  /// No description provided for @interestsReceivedEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No new interests yet'**
  String get interestsReceivedEmptyTitle;

  /// No description provided for @interestsReceivedEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'When someone sends you an interest, it will show up here.'**
  String get interestsReceivedEmptyMessage;

  /// No description provided for @interestsSentEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No interests sent yet'**
  String get interestsSentEmptyTitle;

  /// No description provided for @interestsSentEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Interests you send will show up here so you can track their status.'**
  String get interestsSentEmptyMessage;

  /// No description provided for @profileDetailTabAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get profileDetailTabAbout;

  /// No description provided for @profileDetailTabPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get profileDetailTabPhotos;

  /// No description provided for @profileDetailTabFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get profileDetailTabFamily;

  /// No description provided for @profileDetailTabLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle'**
  String get profileDetailTabLifestyle;

  /// No description provided for @profileDetailTabHoroscope.
  ///
  /// In en, this message translates to:
  /// **'Horoscope'**
  String get profileDetailTabHoroscope;

  /// No description provided for @profileDetailTabPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get profileDetailTabPreferences;

  /// No description provided for @profileDetailTabVerification.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get profileDetailTabVerification;

  /// No description provided for @profileDetailTabCompatibility.
  ///
  /// In en, this message translates to:
  /// **'Compatibility'**
  String get profileDetailTabCompatibility;

  /// No description provided for @profileDetailAgeYears.
  ///
  /// In en, this message translates to:
  /// **'{age} yrs'**
  String profileDetailAgeYears(int age);

  /// No description provided for @profileDetailNoMorePhotos.
  ///
  /// In en, this message translates to:
  /// **'No other photos shared yet'**
  String get profileDetailNoMorePhotos;

  /// No description provided for @profileDetailTabTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get profileDetailTabTimeline;

  /// No description provided for @profileDetailProfileNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Profile not available'**
  String get profileDetailProfileNotAvailable;

  /// No description provided for @profileDetailActionBlock.
  ///
  /// In en, this message translates to:
  /// **'Block User'**
  String get profileDetailActionBlock;

  /// No description provided for @profileDetailActionUnblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock User'**
  String get profileDetailActionUnblock;

  /// No description provided for @profileDetailActionReport.
  ///
  /// In en, this message translates to:
  /// **'Report User'**
  String get profileDetailActionReport;

  /// No description provided for @profileDetailUnblockConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Unblock this member?'**
  String get profileDetailUnblockConfirmTitle;

  /// No description provided for @profileDetailUnblockConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be able to see each other again in Discover, Matches, and Search, and can send interests and messages.'**
  String get profileDetailUnblockConfirmMessage;

  /// No description provided for @profileDetailUnblockConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get profileDetailUnblockConfirmButton;

  /// No description provided for @profileDetailUnblockLoading.
  ///
  /// In en, this message translates to:
  /// **'Unblocking member…'**
  String get profileDetailUnblockLoading;

  /// No description provided for @profileDetailUnblockSuccess.
  ///
  /// In en, this message translates to:
  /// **'{name} has been unblocked.'**
  String profileDetailUnblockSuccess(String name);

  /// No description provided for @profileDetailBlockConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Block this member?'**
  String get profileDetailBlockConfirmTitle;

  /// No description provided for @profileDetailBlockConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'They will disappear from Discover, Matches and Search. Existing chat remains available with a blocked banner. You can unblock later from Chat.'**
  String get profileDetailBlockConfirmMessage;

  /// No description provided for @profileDetailBlockConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get profileDetailBlockConfirmButton;

  /// No description provided for @profileDetailBlockLoading.
  ///
  /// In en, this message translates to:
  /// **'Blocking member…'**
  String get profileDetailBlockLoading;

  /// No description provided for @profileDetailBlockSuccess.
  ///
  /// In en, this message translates to:
  /// **'{name} has been blocked.'**
  String profileDetailBlockSuccess(String name);

  /// No description provided for @profileDetailReportReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Why are you reporting {name}?'**
  String profileDetailReportReasonTitle(String name);

  /// No description provided for @profileDetailReportReasonFakeProfile.
  ///
  /// In en, this message translates to:
  /// **'Fake Profile'**
  String get profileDetailReportReasonFakeProfile;

  /// No description provided for @profileDetailReportReasonSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get profileDetailReportReasonSpam;

  /// No description provided for @profileDetailReportReasonHarassment.
  ///
  /// In en, this message translates to:
  /// **'Harassment'**
  String get profileDetailReportReasonHarassment;

  /// No description provided for @profileDetailReportReasonInappropriateContent.
  ///
  /// In en, this message translates to:
  /// **'Inappropriate Photos'**
  String get profileDetailReportReasonInappropriateContent;

  /// No description provided for @profileDetailReportReasonUnderage.
  ///
  /// In en, this message translates to:
  /// **'Underage'**
  String get profileDetailReportReasonUnderage;

  /// No description provided for @profileDetailReportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get profileDetailReportReasonOther;

  /// No description provided for @profileDetailReportDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Additional details (optional)'**
  String get profileDetailReportDescriptionLabel;

  /// No description provided for @profileDetailReportDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Add any extra context that could help our review team'**
  String get profileDetailReportDescriptionHint;

  /// No description provided for @profileDetailReportSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get profileDetailReportSubmit;

  /// No description provided for @profileDetailReportLoading.
  ///
  /// In en, this message translates to:
  /// **'Submitting your report…'**
  String get profileDetailReportLoading;

  /// No description provided for @profileDetailReportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Thanks — your report has been submitted.'**
  String get profileDetailReportSuccess;

  /// No description provided for @profileDetailMoreLabel.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get profileDetailMoreLabel;

  /// No description provided for @safetyErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Please check your network and try again.'**
  String get safetyErrorNetwork;

  /// No description provided for @safetyErrorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get safetyErrorUnauthorized;

  /// No description provided for @safetyErrorValidation.
  ///
  /// In en, this message translates to:
  /// **'Something about this request wasn\'t valid. Please try again.'**
  String get safetyErrorValidation;

  /// No description provided for @safetyErrorNotFound.
  ///
  /// In en, this message translates to:
  /// **'This member is no longer available.'**
  String get safetyErrorNotFound;

  /// No description provided for @safetyErrorConflict.
  ///
  /// In en, this message translates to:
  /// **'This was already done for this member.'**
  String get safetyErrorConflict;

  /// No description provided for @safetyErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get safetyErrorGeneric;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get commonTryAgain;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get commonAll;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @commonDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commonDismiss;

  /// No description provided for @commonGreat.
  ///
  /// In en, this message translates to:
  /// **'Great'**
  String get commonGreat;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get commonError;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get commonLoading;

  /// No description provided for @commonProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing…'**
  String get commonProcessing;

  /// No description provided for @commonOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get commonOpenSettings;

  /// No description provided for @commonReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get commonReset;

  /// No description provided for @commonRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get commonRotate;

  /// No description provided for @commonSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get commonSearchHint;

  /// No description provided for @commonNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get commonNoMatches;

  /// No description provided for @commonReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get commonReply;

  /// No description provided for @commonEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get commonEnable;

  /// No description provided for @commonNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get commonNotNow;

  /// No description provided for @commonPopular.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get commonPopular;

  /// No description provided for @commonHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get commonHelp;

  /// No description provided for @commonPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get commonPrivacy;

  /// No description provided for @commonSubscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get commonSubscription;

  /// No description provided for @commonLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get commonLogOut;

  /// No description provided for @commonCouldNotLoadProfile.
  ///
  /// In en, this message translates to:
  /// **'Could not load profile'**
  String get commonCouldNotLoadProfile;

  /// No description provided for @commonProfileLoadConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your profile. Check your connection.'**
  String get commonProfileLoadConnectionError;

  /// No description provided for @fieldAge.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get fieldAge;

  /// No description provided for @fieldAgeRange.
  ///
  /// In en, this message translates to:
  /// **'Age Range'**
  String get fieldAgeRange;

  /// No description provided for @fieldReligion.
  ///
  /// In en, this message translates to:
  /// **'Religion'**
  String get fieldReligion;

  /// No description provided for @fieldReligionHint.
  ///
  /// In en, this message translates to:
  /// **'Select Religion'**
  String get fieldReligionHint;

  /// No description provided for @fieldCaste.
  ///
  /// In en, this message translates to:
  /// **'Caste'**
  String get fieldCaste;

  /// No description provided for @fieldCasteDivision.
  ///
  /// In en, this message translates to:
  /// **'Caste / Division'**
  String get fieldCasteDivision;

  /// No description provided for @fieldCasteHint.
  ///
  /// In en, this message translates to:
  /// **'Select Caste'**
  String get fieldCasteHint;

  /// No description provided for @fieldMotherTongue.
  ///
  /// In en, this message translates to:
  /// **'Mother Tongue'**
  String get fieldMotherTongue;

  /// No description provided for @fieldMotherTongueHint.
  ///
  /// In en, this message translates to:
  /// **'Select Tongue'**
  String get fieldMotherTongueHint;

  /// No description provided for @fieldProfession.
  ///
  /// In en, this message translates to:
  /// **'Profession'**
  String get fieldProfession;

  /// No description provided for @fieldProfessionHint.
  ///
  /// In en, this message translates to:
  /// **'Select Profession'**
  String get fieldProfessionHint;

  /// No description provided for @fieldAnnualIncome.
  ///
  /// In en, this message translates to:
  /// **'Annual Income'**
  String get fieldAnnualIncome;

  /// No description provided for @fieldIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get fieldIncome;

  /// No description provided for @fieldIncomeHint.
  ///
  /// In en, this message translates to:
  /// **'Select Range'**
  String get fieldIncomeHint;

  /// No description provided for @fieldHeight.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get fieldHeight;

  /// No description provided for @fieldHeightHint.
  ///
  /// In en, this message translates to:
  /// **'Select Height'**
  String get fieldHeightHint;

  /// No description provided for @fieldWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get fieldWeight;

  /// No description provided for @fieldWeightHint.
  ///
  /// In en, this message translates to:
  /// **'Select Weight'**
  String get fieldWeightHint;

  /// No description provided for @fieldQualification.
  ///
  /// In en, this message translates to:
  /// **'Highest Qualification'**
  String get fieldQualification;

  /// No description provided for @fieldQualificationHint.
  ///
  /// In en, this message translates to:
  /// **'Select Degree'**
  String get fieldQualificationHint;

  /// No description provided for @fieldCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'Current Location'**
  String get fieldCurrentLocation;

  /// No description provided for @fieldLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get fieldLocation;

  /// No description provided for @fieldLocationHint.
  ///
  /// In en, this message translates to:
  /// **'Select City / Country'**
  String get fieldLocationHint;

  /// No description provided for @fieldCountry.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get fieldCountry;

  /// No description provided for @fieldCountryHint.
  ///
  /// In en, this message translates to:
  /// **'Select Country'**
  String get fieldCountryHint;

  /// No description provided for @fieldCountryCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Select Country Code'**
  String get fieldCountryCodeHint;

  /// No description provided for @fieldGenderHint.
  ///
  /// In en, this message translates to:
  /// **'Select Gender'**
  String get fieldGenderHint;

  /// No description provided for @fieldEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get fieldEducation;

  /// No description provided for @fieldOccupation.
  ///
  /// In en, this message translates to:
  /// **'Occupation'**
  String get fieldOccupation;

  /// No description provided for @fieldMaritalStatus.
  ///
  /// In en, this message translates to:
  /// **'Marital Status'**
  String get fieldMaritalStatus;

  /// No description provided for @fieldMatrimonyId.
  ///
  /// In en, this message translates to:
  /// **'Matrimony ID'**
  String get fieldMatrimonyId;

  /// No description provided for @fieldDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get fieldDistance;

  /// No description provided for @fieldPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get fieldPhone;

  /// No description provided for @fieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get fieldEmail;

  /// No description provided for @fieldGovId.
  ///
  /// In en, this message translates to:
  /// **'Gov ID'**
  String get fieldGovId;

  /// No description provided for @fieldGovernmentId.
  ///
  /// In en, this message translates to:
  /// **'Government ID'**
  String get fieldGovernmentId;

  /// No description provided for @fieldFaceMatch.
  ///
  /// In en, this message translates to:
  /// **'Face Match'**
  String get fieldFaceMatch;

  /// No description provided for @fieldInterests.
  ///
  /// In en, this message translates to:
  /// **'Interests'**
  String get fieldInterests;

  /// No description provided for @fieldCoreValues.
  ///
  /// In en, this message translates to:
  /// **'Core Values'**
  String get fieldCoreValues;

  /// No description provided for @permissionPhotoDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo Access Disabled'**
  String get permissionPhotoDisabledTitle;

  /// No description provided for @permissionPhotoDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Photo access is disabled. Enable it from Settings.'**
  String get permissionPhotoDisabledMessage;

  /// No description provided for @permissionCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera Access'**
  String get permissionCameraTitle;

  /// No description provided for @permissionCameraMessage.
  ///
  /// In en, this message translates to:
  /// **'Nenjam needs camera access to take your photo.'**
  String get permissionCameraMessage;

  /// No description provided for @permissionCameraDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera Access Disabled'**
  String get permissionCameraDisabledTitle;

  /// No description provided for @permissionCameraDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Camera access is disabled. Enable it from Settings to take a photo.'**
  String get permissionCameraDisabledMessage;

  /// No description provided for @permissionMicTitle.
  ///
  /// In en, this message translates to:
  /// **'Microphone Access'**
  String get permissionMicTitle;

  /// No description provided for @permissionMicMessage.
  ///
  /// In en, this message translates to:
  /// **'Nenjam needs microphone access to record a voice message.'**
  String get permissionMicMessage;

  /// No description provided for @permissionMicDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Microphone Access Disabled'**
  String get permissionMicDisabledTitle;

  /// No description provided for @permissionMicDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is disabled. Enable it from Settings to record a voice message.'**
  String get permissionMicDisabledMessage;

  /// No description provided for @permissionNotificationsEnableTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable Notifications'**
  String get permissionNotificationsEnableTitle;

  /// No description provided for @permissionNotificationsEnableMessage.
  ///
  /// In en, this message translates to:
  /// **'Get notified when someone sends you an interest, accepts your request, or messages you.'**
  String get permissionNotificationsEnableMessage;

  /// No description provided for @permissionNotificationsDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications Disabled'**
  String get permissionNotificationsDisabledTitle;

  /// No description provided for @permissionNotificationsDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Enable notifications from Settings to stay updated.'**
  String get permissionNotificationsDisabledMessage;

  /// No description provided for @settingsNotificationsOffMessage.
  ///
  /// In en, this message translates to:
  /// **'To turn off notifications, disable them for Nenjam Matrimony in Settings.'**
  String get settingsNotificationsOffMessage;

  /// No description provided for @photoCropProcessError.
  ///
  /// In en, this message translates to:
  /// **'Could not process this photo. Please try again.'**
  String get photoCropProcessError;

  /// No description provided for @photoCropLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load this photo.'**
  String get photoCropLoadError;

  /// No description provided for @photoCropUsePhoto.
  ///
  /// In en, this message translates to:
  /// **'Use Photo'**
  String get photoCropUsePhoto;

  /// No description provided for @photosYourPhotos.
  ///
  /// In en, this message translates to:
  /// **'Your Photos'**
  String get photosYourPhotos;

  /// No description provided for @photosAddFirst.
  ///
  /// In en, this message translates to:
  /// **'Add your first photo'**
  String get photosAddFirst;

  /// No description provided for @photosReorderHint.
  ///
  /// In en, this message translates to:
  /// **'Long-press and drag to reorder. Tap a photo to set as display, replace, or delete it.'**
  String get photosReorderHint;

  /// No description provided for @photosSetAsDisplay.
  ///
  /// In en, this message translates to:
  /// **'Set as display photo'**
  String get photosSetAsDisplay;

  /// No description provided for @photosReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace photo'**
  String get photosReplace;

  /// No description provided for @photosDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete photo'**
  String get photosDelete;

  /// No description provided for @photosLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your photos. Check your connection.'**
  String get photosLoadError;

  /// No description provided for @photosGalleryTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo Gallery'**
  String get photosGalleryTitle;

  /// No description provided for @dialogUpgradeTitle.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Royal Premium'**
  String get dialogUpgradeTitle;

  /// No description provided for @dialogUpgradeMessage.
  ///
  /// In en, this message translates to:
  /// **'Get unlimited contact views, AI compatibility breakdowns, and horoscope matches.'**
  String get dialogUpgradeMessage;

  /// No description provided for @dialogVerificationTitle.
  ///
  /// In en, this message translates to:
  /// **'ID Verification Required'**
  String get dialogVerificationTitle;

  /// No description provided for @dialogVerificationMessage.
  ///
  /// In en, this message translates to:
  /// **'Please verify your Aadhaar or Passport to send direct chat invitations.'**
  String get dialogVerificationMessage;

  /// No description provided for @dialogVerifyNow.
  ///
  /// In en, this message translates to:
  /// **'Verify Now'**
  String get dialogVerifyNow;

  /// No description provided for @networkNoInternetTitle.
  ///
  /// In en, this message translates to:
  /// **'No Internet Connection'**
  String get networkNoInternetTitle;

  /// No description provided for @networkNoInternetMessage.
  ///
  /// In en, this message translates to:
  /// **'Please check your network settings and try reconnecting.'**
  String get networkNoInternetMessage;

  /// No description provided for @networkReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get networkReconnect;

  /// No description provided for @networkConnectionTimeout.
  ///
  /// In en, this message translates to:
  /// **'The connection timed out. Please try again.'**
  String get networkConnectionTimeout;

  /// No description provided for @networkReceiveTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to respond. Please try again.'**
  String get networkReceiveTimeout;

  /// No description provided for @networkRequestCancelled.
  ///
  /// In en, this message translates to:
  /// **'The request was cancelled.'**
  String get networkRequestCancelled;

  /// No description provided for @startupUnreachableTitle.
  ///
  /// In en, this message translates to:
  /// **'We can\'t reach Nenjam'**
  String get startupUnreachableTitle;

  /// No description provided for @startupUnreachableMessage.
  ///
  /// In en, this message translates to:
  /// **'Check your internet connection and try again.'**
  String get startupUnreachableMessage;

  /// No description provided for @startupUnhealthyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nenjam is temporarily unavailable'**
  String get startupUnhealthyTitle;

  /// No description provided for @startupUnhealthyMessage.
  ///
  /// In en, this message translates to:
  /// **'Our servers are having trouble right now. Please try again in a moment.'**
  String get startupUnhealthyMessage;

  /// No description provided for @networkServerErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Server Error (500)'**
  String get networkServerErrorTitle;

  /// No description provided for @networkServerErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Our matrimonial servers are currently undergoing maintenance or experiencing issues.'**
  String get networkServerErrorMessage;

  /// No description provided for @cardCompatibilityFootnote.
  ///
  /// In en, this message translates to:
  /// **'Based on 40+ AI lifestyle parameters'**
  String get cardCompatibilityFootnote;

  /// No description provided for @cardGetVerifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Get Verified Badge'**
  String get cardGetVerifiedTitle;

  /// No description provided for @cardGetVerifiedMessage.
  ///
  /// In en, this message translates to:
  /// **'Profiles with verified ID get 3x more match responses.'**
  String get cardGetVerifiedMessage;

  /// No description provided for @cardHoroscopeMatch.
  ///
  /// In en, this message translates to:
  /// **'Horoscope Match'**
  String get cardHoroscopeMatch;

  /// No description provided for @cardGunaMilanWith.
  ///
  /// In en, this message translates to:
  /// **'Guna Milan with {partnerName}'**
  String cardGunaMilanWith(String partnerName);

  /// No description provided for @otpPasteCode.
  ///
  /// In en, this message translates to:
  /// **'Paste Code'**
  String get otpPasteCode;

  /// No description provided for @riYourHoroscope.
  ///
  /// In en, this message translates to:
  /// **'Your Horoscope'**
  String get riYourHoroscope;

  /// No description provided for @riHoroscopeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add your horoscope details to enable compatibility matching.'**
  String get riHoroscopeEmpty;

  /// No description provided for @riHoroscopeAvailable.
  ///
  /// In en, this message translates to:
  /// **'Horoscope available'**
  String get riHoroscopeAvailable;

  /// No description provided for @riHoroscopeNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Horoscope not available'**
  String get riHoroscopeNotAvailable;

  /// No description provided for @riDiscoverPersonality.
  ///
  /// In en, this message translates to:
  /// **'Share your marriage expectations'**
  String get riDiscoverPersonality;

  /// No description provided for @riQuizTeaser.
  ///
  /// In en, this message translates to:
  /// **'3-minute quiz · improves match quality'**
  String get riQuizTeaser;

  /// No description provided for @riPersonalityProfile.
  ///
  /// In en, this message translates to:
  /// **'Marriage Compatibility Quiz'**
  String get riPersonalityProfile;

  /// No description provided for @riRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get riRetake;

  /// No description provided for @astroMatchingTitle.
  ///
  /// In en, this message translates to:
  /// **'Horoscope Matching'**
  String get astroMatchingTitle;

  /// No description provided for @astroLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your horoscope.'**
  String get astroLoadError;

  /// No description provided for @astroUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Horoscope matching isn\'t available yet'**
  String get astroUnavailableTitle;

  /// No description provided for @astroUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'We\'re still building this feature. Your horoscope details are saved with your profile, and no compatibility results are shown until real matching is ready.'**
  String get astroUnavailableMessage;

  /// No description provided for @astroYourDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Horoscope Details'**
  String get astroYourDetailsTitle;

  /// No description provided for @astroRasiLabel.
  ///
  /// In en, this message translates to:
  /// **'Rasi: {value}'**
  String astroRasiLabel(String value);

  /// No description provided for @astroNakshatraLabel.
  ///
  /// In en, this message translates to:
  /// **'Nakshatra: {value}'**
  String astroNakshatraLabel(String value);

  /// No description provided for @astroDoshamLabel.
  ///
  /// In en, this message translates to:
  /// **'Dosham: {value}'**
  String astroDoshamLabel(String value);

  /// No description provided for @astroAllowCompareTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow matches to compare horoscope'**
  String get astroAllowCompareTitle;

  /// No description provided for @astroAllowCompareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show a compatibility score on your profile.'**
  String get astroAllowCompareSubtitle;

  /// No description provided for @astroPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Compatibility Preview'**
  String get astroPreviewTitle;

  /// No description provided for @astroPreviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A sample of how your compatibility score will appear to potential matches.'**
  String get astroPreviewSubtitle;

  /// No description provided for @astroNakshatraMatch.
  ///
  /// In en, this message translates to:
  /// **'Nakshatra Match'**
  String get astroNakshatraMatch;

  /// No description provided for @astroRasiMatch.
  ///
  /// In en, this message translates to:
  /// **'Rasi Match'**
  String get astroRasiMatch;

  /// No description provided for @astroDoshamMatch.
  ///
  /// In en, this message translates to:
  /// **'Dosham Match'**
  String get astroDoshamMatch;

  /// No description provided for @astroPersonalityMatch.
  ///
  /// In en, this message translates to:
  /// **'Personality Match'**
  String get astroPersonalityMatch;

  /// No description provided for @helpNoEmailApp.
  ///
  /// In en, this message translates to:
  /// **'No email app found on this device.'**
  String get helpNoEmailApp;

  /// No description provided for @helpFaqTitle.
  ///
  /// In en, this message translates to:
  /// **'Frequently Asked Questions'**
  String get helpFaqTitle;

  /// No description provided for @helpStillNeedHelp.
  ///
  /// In en, this message translates to:
  /// **'Still Need Help?'**
  String get helpStillNeedHelp;

  /// No description provided for @inboxDeleteMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete message?'**
  String get inboxDeleteMessageTitle;

  /// No description provided for @inboxDeleteMessageBody.
  ///
  /// In en, this message translates to:
  /// **'This message will be deleted for everyone.'**
  String get inboxDeleteMessageBody;

  /// No description provided for @inboxEditMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get inboxEditMessageTitle;

  /// No description provided for @inboxEditMessageError.
  ///
  /// In en, this message translates to:
  /// **'Could not edit message. Please try again.'**
  String get inboxEditMessageError;

  /// No description provided for @inboxMessageDeleted.
  ///
  /// In en, this message translates to:
  /// **'This message was deleted'**
  String get inboxMessageDeleted;

  /// No description provided for @inboxMessageEdited.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get inboxMessageEdited;

  /// No description provided for @inboxTyping.
  ///
  /// In en, this message translates to:
  /// **'Typing'**
  String get inboxTyping;

  /// No description provided for @inboxCancelReply.
  ///
  /// In en, this message translates to:
  /// **'Cancel reply'**
  String get inboxCancelReply;

  /// No description provided for @inboxCancelRecording.
  ///
  /// In en, this message translates to:
  /// **'Cancel recording'**
  String get inboxCancelRecording;

  /// No description provided for @inboxStopAndPreview.
  ///
  /// In en, this message translates to:
  /// **'Stop and preview'**
  String get inboxStopAndPreview;

  /// No description provided for @inboxDiscardRecording.
  ///
  /// In en, this message translates to:
  /// **'Discard recording'**
  String get inboxDiscardRecording;

  /// No description provided for @inboxSendVoiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Send voice message'**
  String get inboxSendVoiceMessage;

  /// No description provided for @notificationChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Interests, matches, messages, and account updates.'**
  String get notificationChannelDescription;

  /// No description provided for @partnerPrefAgeSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get partnerPrefAgeSheetTitle;

  /// No description provided for @profileTodaysActivity.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Activity'**
  String get profileTodaysActivity;

  /// No description provided for @profileTodaysPriorities.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Priorities'**
  String get profileTodaysPriorities;

  /// No description provided for @profileAddFamilyDetails.
  ///
  /// In en, this message translates to:
  /// **'Add Family Details'**
  String get profileAddFamilyDetails;

  /// No description provided for @profileAddMorePhotos.
  ///
  /// In en, this message translates to:
  /// **'Add 2 More Photos'**
  String get profileAddMorePhotos;

  /// No description provided for @profileQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get profileQuickActions;

  /// No description provided for @profileManageSections.
  ///
  /// In en, this message translates to:
  /// **'Manage Your Profile'**
  String get profileManageSections;

  /// No description provided for @profileAiMatchCoach.
  ///
  /// In en, this message translates to:
  /// **'AI MATCH COACH'**
  String get profileAiMatchCoach;

  /// No description provided for @profileDiscoverOpportunities.
  ///
  /// In en, this message translates to:
  /// **'Discover Opportunities'**
  String get profileDiscoverOpportunities;

  /// No description provided for @profileNoRecommendations.
  ///
  /// In en, this message translates to:
  /// **'No matches yet. Complete your profile to see recommendations.'**
  String get profileNoRecommendations;

  /// No description provided for @profileCompatiblePercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% Compatible'**
  String profileCompatiblePercent(int percent);

  /// No description provided for @profileCompletionLabel.
  ///
  /// In en, this message translates to:
  /// **'Profile Completion'**
  String get profileCompletionLabel;

  /// No description provided for @profileMatchJourney.
  ///
  /// In en, this message translates to:
  /// **'Match Journey'**
  String get profileMatchJourney;

  /// No description provided for @profileJourneyAccountCreated.
  ///
  /// In en, this message translates to:
  /// **'Account\nCreated'**
  String get profileJourneyAccountCreated;

  /// No description provided for @profileJourneyProfileCompleted.
  ///
  /// In en, this message translates to:
  /// **'Profile\nCompleted'**
  String get profileJourneyProfileCompleted;

  /// No description provided for @profileJourneyVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get profileJourneyVerified;

  /// No description provided for @profileJourneyInterests.
  ///
  /// In en, this message translates to:
  /// **'Interests'**
  String get profileJourneyInterests;

  /// No description provided for @profileJourneyConversations.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get profileJourneyConversations;

  /// No description provided for @profileJourneyPerfectMatch.
  ///
  /// In en, this message translates to:
  /// **'Perfect\nMatch'**
  String get profileJourneyPerfectMatch;

  /// No description provided for @profilePerformanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile Performance'**
  String get profilePerformanceTitle;

  /// No description provided for @profilePerformanceStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get profilePerformanceStrength;

  /// No description provided for @profilePerformanceVisibility.
  ///
  /// In en, this message translates to:
  /// **'Visibility'**
  String get profilePerformanceVisibility;

  /// No description provided for @profilePerformanceResponse.
  ///
  /// In en, this message translates to:
  /// **'Response'**
  String get profilePerformanceResponse;

  /// No description provided for @profileDeactivateAccount.
  ///
  /// In en, this message translates to:
  /// **'Deactivate Account'**
  String get profileDeactivateAccount;

  /// No description provided for @profileMatchesLabel.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get profileMatchesLabel;

  /// No description provided for @profileDetailFamilyInfo.
  ///
  /// In en, this message translates to:
  /// **'Family Information'**
  String get profileDetailFamilyInfo;

  /// No description provided for @profileDetailAiCompatibility.
  ///
  /// In en, this message translates to:
  /// **'AI Match Compatibility'**
  String get profileDetailAiCompatibility;

  /// No description provided for @profileDetailSimilarProfiles.
  ///
  /// In en, this message translates to:
  /// **'Similar Profiles'**
  String get profileDetailSimilarProfiles;

  /// No description provided for @profileDetailVerifiedBanner.
  ///
  /// In en, this message translates to:
  /// **'VERIFIED PROFILE'**
  String get profileDetailVerifiedBanner;

  /// No description provided for @profileDetailJoinedNenjam.
  ///
  /// In en, this message translates to:
  /// **'Joined Nenjam'**
  String get profileDetailJoinedNenjam;

  /// No description provided for @profileDetailProfileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileDetailProfileUpdated;

  /// No description provided for @profileDetailIdentityVerified.
  ///
  /// In en, this message translates to:
  /// **'Identity verified'**
  String get profileDetailIdentityVerified;

  /// No description provided for @profileDetailActiveNow.
  ///
  /// In en, this message translates to:
  /// **'Active now'**
  String get profileDetailActiveNow;

  /// No description provided for @psychologyQuizTitle.
  ///
  /// In en, this message translates to:
  /// **'Marriage Compatibility Quiz'**
  String get psychologyQuizTitle;

  /// No description provided for @psychologyIntroBody.
  ///
  /// In en, this message translates to:
  /// **'Short, scenario-based questions about everyday married life — money, family, conflict, careers and more. Your answers help us suggest matches whose expectations align with yours.\n\nThis quiz is optional. Your answers are private and are never shown to other members. Once saved, you can change them again only after a waiting period.'**
  String get psychologyIntroBody;

  /// No description provided for @psychologyTakesMinutes.
  ///
  /// In en, this message translates to:
  /// **'Takes about 3 minutes'**
  String get psychologyTakesMinutes;

  /// No description provided for @psychologyStartQuiz.
  ///
  /// In en, this message translates to:
  /// **'Start Quiz'**
  String get psychologyStartQuiz;

  /// No description provided for @psychologyNoQuiz.
  ///
  /// In en, this message translates to:
  /// **'No quiz is available right now.'**
  String get psychologyNoQuiz;

  /// No description provided for @psychologyQuestionProgress.
  ///
  /// In en, this message translates to:
  /// **'Question {current} of {total}'**
  String psychologyQuestionProgress(int current, int total);

  /// No description provided for @psychologyYourProfile.
  ///
  /// In en, this message translates to:
  /// **'Quiz completed'**
  String get psychologyYourProfile;

  /// No description provided for @psychologyCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get psychologyCompleted;

  /// No description provided for @psychologyUpdatedOn.
  ///
  /// In en, this message translates to:
  /// **'Updated {date}'**
  String psychologyUpdatedOn(String date);

  /// No description provided for @psychologyYourAnswers.
  ///
  /// In en, this message translates to:
  /// **'Your answers'**
  String get psychologyYourAnswers;

  /// No description provided for @psychologyRetakeQuiz.
  ///
  /// In en, this message translates to:
  /// **'Retake Quiz'**
  String get psychologyRetakeQuiz;

  /// No description provided for @psychologyNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get psychologyNext;

  /// No description provided for @psychologySubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get psychologySubmit;

  /// No description provided for @psychologyLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load the quiz. Check your connection and try again.'**
  String get psychologyLoadError;

  /// No description provided for @psychologyIncompleteError.
  ///
  /// In en, this message translates to:
  /// **'Please answer every question before submitting.'**
  String get psychologyIncompleteError;

  /// No description provided for @psychologyRejectedError.
  ///
  /// In en, this message translates to:
  /// **'The quiz has been updated. Please review your answers and submit again.'**
  String get psychologyRejectedError;

  /// No description provided for @psychologySubmitError.
  ///
  /// In en, this message translates to:
  /// **'Could not submit your answers. Check your connection and try again.'**
  String get psychologySubmitError;

  /// No description provided for @psychologyCheckError.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t check your saved answers. Check your connection and try again.'**
  String get psychologyCheckError;

  /// No description provided for @psychologyRetakeCooldownDays.
  ///
  /// In en, this message translates to:
  /// **'You can change your answers again in {days,plural, =1{1 day} other{{days} days}}.'**
  String psychologyRetakeCooldownDays(int days);

  /// No description provided for @psychologyRetakeCooldownHours.
  ///
  /// In en, this message translates to:
  /// **'You can change your answers again in {hours,plural, =1{1 hour} other{{hours} hours}}.'**
  String psychologyRetakeCooldownHours(int hours);

  /// No description provided for @psychologyRetakeAvailableOn.
  ///
  /// In en, this message translates to:
  /// **'You can retake the quiz from {date}.'**
  String psychologyRetakeAvailableOn(String date);

  /// No description provided for @psychologyRetakeTryAnyway.
  ///
  /// In en, this message translates to:
  /// **'Try anyway'**
  String get psychologyRetakeTryAnyway;

  /// No description provided for @psychologyStatusCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t check your quiz status.'**
  String get psychologyStatusCheckFailed;

  /// No description provided for @registrationSaveStepError.
  ///
  /// In en, this message translates to:
  /// **'Could not save this step. Check your connection.'**
  String get registrationSaveStepError;

  /// No description provided for @registrationSaveStepErrorDetail.
  ///
  /// In en, this message translates to:
  /// **'Could not save this step: {message}'**
  String registrationSaveStepErrorDetail(String message);

  /// No description provided for @registrationSaveChangesError.
  ///
  /// In en, this message translates to:
  /// **'Could not save your changes. Check your connection.'**
  String get registrationSaveChangesError;

  /// No description provided for @registrationSaveChangesErrorDetail.
  ///
  /// In en, this message translates to:
  /// **'Could not save your changes: {message}'**
  String registrationSaveChangesErrorDetail(String message);

  /// No description provided for @registrationSaveProfileError.
  ///
  /// In en, this message translates to:
  /// **'Could not save your profile. Check your connection.'**
  String get registrationSaveProfileError;

  /// No description provided for @registrationSaveProfileErrorDetail.
  ///
  /// In en, this message translates to:
  /// **'Could not save your profile: {message}'**
  String registrationSaveProfileErrorDetail(String message);

  /// No description provided for @registrationProfileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get registrationProfileUpdated;

  /// No description provided for @registrationPreviewDocument.
  ///
  /// In en, this message translates to:
  /// **'Preview document'**
  String get registrationPreviewDocument;

  /// No description provided for @registrationChooseAgain.
  ///
  /// In en, this message translates to:
  /// **'Choose again'**
  String get registrationChooseAgain;

  /// No description provided for @registrationConfirmUpload.
  ///
  /// In en, this message translates to:
  /// **'Confirm upload'**
  String get registrationConfirmUpload;

  /// No description provided for @registrationWeightKg.
  ///
  /// In en, this message translates to:
  /// **'{weight} kg'**
  String registrationWeightKg(String weight);

  /// No description provided for @drawerRateUs.
  ///
  /// In en, this message translates to:
  /// **'Rate Us ⭐'**
  String get drawerRateUs;

  /// No description provided for @drawerProfileIdLabel.
  ///
  /// In en, this message translates to:
  /// **'ID: {id}'**
  String drawerProfileIdLabel(String id);

  /// No description provided for @authNoSignedInUserToLink.
  ///
  /// In en, this message translates to:
  /// **'No signed-in user to link the phone number to.'**
  String get authNoSignedInUserToLink;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonPleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Please wait...'**
  String get commonPleaseWait;

  /// No description provided for @permissionImagePickerError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the image picker.'**
  String get permissionImagePickerError;

  /// No description provided for @voiceRecordingUnsupportedOnWeb.
  ///
  /// In en, this message translates to:
  /// **'Voice messages aren\'t supported in the browser yet. Please use the Nenjam mobile app.'**
  String get voiceRecordingUnsupportedOnWeb;

  /// No description provided for @permissionCameraNeeded.
  ///
  /// In en, this message translates to:
  /// **'Camera access is needed to take a photo.'**
  String get permissionCameraNeeded;

  /// No description provided for @photoCropAdjustProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust Profile Photo'**
  String get photoCropAdjustProfileTitle;

  /// No description provided for @photoCropAdjustTitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust Photo'**
  String get photoCropAdjustTitle;

  /// No description provided for @inboxLastSeenTodayAt.
  ///
  /// In en, this message translates to:
  /// **'Last seen today at {time}'**
  String inboxLastSeenTodayAt(String time);

  /// No description provided for @inboxLastSeenYesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Last seen yesterday at {time}'**
  String inboxLastSeenYesterdayAt(String time);

  /// No description provided for @inboxLastSeenDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'Last seen {count,plural, =1{1 day ago} other{{count} days ago}}'**
  String inboxLastSeenDaysAgo(int count);

  /// No description provided for @inboxLastSeenOn.
  ///
  /// In en, this message translates to:
  /// **'Last seen {date}'**
  String inboxLastSeenOn(String date);

  /// No description provided for @inboxLastSeenJustNow.
  ///
  /// In en, this message translates to:
  /// **'Last seen just now'**
  String get inboxLastSeenJustNow;

  /// No description provided for @inboxLastSeenMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'Last seen {count}m ago'**
  String inboxLastSeenMinutesAgo(int count);

  /// No description provided for @inboxLastSeenHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'Last seen {count}h ago'**
  String inboxLastSeenHoursAgo(int count);

  /// No description provided for @inboxDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{1 day ago} other{{count} days ago}}'**
  String inboxDaysAgo(int count);

  /// No description provided for @validatorNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name'**
  String get validatorNameRequired;

  /// No description provided for @validatorNameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Name must be at least 2 characters'**
  String get validatorNameTooShort;

  /// No description provided for @validatorNameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Name must be less than 50 characters'**
  String get validatorNameTooLong;

  /// No description provided for @validatorNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Name can only contain letters, spaces, hyphens, and apostrophes'**
  String get validatorNameInvalid;

  /// No description provided for @validatorUsernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a username'**
  String get validatorUsernameRequired;

  /// No description provided for @validatorUsernameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Username must be at least 3 characters'**
  String get validatorUsernameTooShort;

  /// No description provided for @validatorUsernameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Username must be less than 20 characters'**
  String get validatorUsernameTooLong;

  /// No description provided for @validatorUsernameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use letters, numbers, or underscore (start with a letter)'**
  String get validatorUsernameInvalid;

  /// No description provided for @validatorEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email'**
  String get validatorEmailRequired;

  /// No description provided for @validatorEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get validatorEmailInvalid;

  /// No description provided for @validatorPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your phone number'**
  String get validatorPhoneRequired;

  /// No description provided for @validatorPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid 10-digit mobile number'**
  String get validatorPhoneInvalid;

  /// No description provided for @validatorOtpRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter the OTP'**
  String get validatorOtpRequired;

  /// No description provided for @validatorOtpLength.
  ///
  /// In en, this message translates to:
  /// **'OTP must be {length} digits'**
  String validatorOtpLength(int length);

  /// No description provided for @validatorOtpDigitsOnly.
  ///
  /// In en, this message translates to:
  /// **'OTP must contain only digits'**
  String get validatorOtpDigitsOnly;

  /// No description provided for @validatorPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a password'**
  String get validatorPasswordRequired;

  /// No description provided for @validatorPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get validatorPasswordTooShort;

  /// No description provided for @validatorPasswordUppercase.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one uppercase letter'**
  String get validatorPasswordUppercase;

  /// No description provided for @validatorPasswordLowercase.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one lowercase letter'**
  String get validatorPasswordLowercase;

  /// No description provided for @validatorPasswordNumber.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one number'**
  String get validatorPasswordNumber;

  /// No description provided for @validatorConfirmPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password'**
  String get validatorConfirmPasswordRequired;

  /// No description provided for @validatorPasswordsMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get validatorPasswordsMismatch;

  /// No description provided for @validatorAgeRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your age'**
  String get validatorAgeRequired;

  /// No description provided for @validatorNumberInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid number'**
  String get validatorNumberInvalid;

  /// No description provided for @validatorAgeMinimum.
  ///
  /// In en, this message translates to:
  /// **'You must be at least 18 years old'**
  String get validatorAgeMinimum;

  /// No description provided for @validatorAgeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid age'**
  String get validatorAgeInvalid;

  /// No description provided for @validatorHeightRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your height'**
  String get validatorHeightRequired;

  /// No description provided for @validatorHeightInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid height'**
  String get validatorHeightInvalid;

  /// No description provided for @validatorHeightRange.
  ///
  /// In en, this message translates to:
  /// **'Please enter height between 100 and 250 cm'**
  String get validatorHeightRange;

  /// No description provided for @validatorFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'{fieldName} is required'**
  String validatorFieldRequired(String fieldName);

  /// No description provided for @validatorBioTooLong.
  ///
  /// In en, this message translates to:
  /// **'Bio must be less than {maxLength} characters'**
  String validatorBioTooLong(int maxLength);

  /// No description provided for @authErrorUsernameTaken.
  ///
  /// In en, this message translates to:
  /// **'That username is already taken. Please choose another.'**
  String get authErrorUsernameTaken;

  /// No description provided for @authErrorEmailInUse.
  ///
  /// In en, this message translates to:
  /// **'An account already exists for this email. Try logging in.'**
  String get authErrorEmailInUse;

  /// No description provided for @authErrorEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'That email address looks invalid. Please check it.'**
  String get authErrorEmailInvalid;

  /// No description provided for @authErrorMethodDisabled.
  ///
  /// In en, this message translates to:
  /// **'This sign-in method is not enabled. Please contact support.'**
  String get authErrorMethodDisabled;

  /// No description provided for @authErrorAccountDisabled.
  ///
  /// In en, this message translates to:
  /// **'This account has been disabled. Please contact support.'**
  String get authErrorAccountDisabled;

  /// No description provided for @authErrorWrongCredentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password. Please try again.'**
  String get authErrorWrongCredentials;

  /// No description provided for @authErrorOtpIncorrect.
  ///
  /// In en, this message translates to:
  /// **'The OTP you entered is incorrect. Please try again.'**
  String get authErrorOtpIncorrect;

  /// No description provided for @authErrorOtpExpired.
  ///
  /// In en, this message translates to:
  /// **'This code has expired. Please request a new OTP.'**
  String get authErrorOtpExpired;

  /// No description provided for @authErrorPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'That phone number looks invalid. Please check it.'**
  String get authErrorPhoneInvalid;

  /// No description provided for @authErrorPhoneMissing.
  ///
  /// In en, this message translates to:
  /// **'Please enter a phone number.'**
  String get authErrorPhoneMissing;

  /// No description provided for @authErrorPhoneLinked.
  ///
  /// In en, this message translates to:
  /// **'This phone number is already linked to another account.'**
  String get authErrorPhoneLinked;

  /// No description provided for @authErrorTooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a while and try again.'**
  String get authErrorTooManyAttempts;

  /// No description provided for @authErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error. Please check your connection and try again.'**
  String get authErrorNetwork;

  /// No description provided for @authErrorPopupBlocked.
  ///
  /// In en, this message translates to:
  /// **'Your browser blocked the sign-in window. Allow pop-ups for this site and try again.'**
  String get authErrorPopupBlocked;

  /// No description provided for @authErrorCaptchaFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify that you\'re not a robot. Please try again.'**
  String get authErrorCaptchaFailed;

  /// No description provided for @authErrorUnauthorizedDomain.
  ///
  /// In en, this message translates to:
  /// **'Sign-in isn\'t enabled for this website address yet. Please contact support.'**
  String get authErrorUnauthorizedDomain;

  /// No description provided for @authErrorSmsQuota.
  ///
  /// In en, this message translates to:
  /// **'We can\'t send more verification codes right now. Please try again later.'**
  String get authErrorSmsQuota;

  /// No description provided for @authErrorBrowserStorage.
  ///
  /// In en, this message translates to:
  /// **'Your browser is blocking the storage sign-in needs. Allow cookies and site data, then try again.'**
  String get authErrorBrowserStorage;

  /// No description provided for @authErrorReauthRequired.
  ///
  /// In en, this message translates to:
  /// **'Please log in again to complete this action.'**
  String get authErrorReauthRequired;

  /// No description provided for @apiError400.
  ///
  /// In en, this message translates to:
  /// **'Invalid request. Please check your input.'**
  String get apiError400;

  /// No description provided for @apiError401.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please login again.'**
  String get apiError401;

  /// No description provided for @apiError403.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission for this action.'**
  String get apiError403;

  /// No description provided for @apiError404.
  ///
  /// In en, this message translates to:
  /// **'Resource not found.'**
  String get apiError404;

  /// No description provided for @apiError422.
  ///
  /// In en, this message translates to:
  /// **'Validation failed. Please check your input.'**
  String get apiError422;

  /// No description provided for @apiError429.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please wait and try again.'**
  String get apiError429;

  /// No description provided for @apiError500.
  ///
  /// In en, this message translates to:
  /// **'Server error. Please try again later.'**
  String get apiError500;

  /// No description provided for @apiError503.
  ///
  /// In en, this message translates to:
  /// **'Service temporarily unavailable.'**
  String get apiError503;

  /// No description provided for @verificationStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get verificationStatusPending;

  /// No description provided for @verificationStatusIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Incomplete'**
  String get verificationStatusIncomplete;

  /// No description provided for @profileNewMember.
  ///
  /// In en, this message translates to:
  /// **'New Member'**
  String get profileNewMember;

  /// No description provided for @profileLocationNotSet.
  ///
  /// In en, this message translates to:
  /// **'Location not set'**
  String get profileLocationNotSet;

  /// No description provided for @profilePreferencesNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set yet'**
  String get profilePreferencesNotSet;

  /// No description provided for @profilePreferencesLabel.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get profilePreferencesLabel;

  /// No description provided for @commonThisField.
  ///
  /// In en, this message translates to:
  /// **'This field'**
  String get commonThisField;

  /// No description provided for @authErrorWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'Your password is too weak. Use at least 8 characters with upper, lower, a number and a symbol.'**
  String get authErrorWeakPassword;

  /// No description provided for @profilePriorityCompletionImpact.
  ///
  /// In en, this message translates to:
  /// **'+12% Profile Complete Score'**
  String get profilePriorityCompletionImpact;

  /// No description provided for @profilePriorityVisibilityImpact.
  ///
  /// In en, this message translates to:
  /// **'Boost Visibility by 40%'**
  String get profilePriorityVisibilityImpact;

  /// No description provided for @profileDetailSiblingsBrothers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Brother} other{{count} Brothers}}'**
  String profileDetailSiblingsBrothers(int count);

  /// No description provided for @profileDetailSiblingsSisters.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Sister} other{{count} Sisters}}'**
  String profileDetailSiblingsSisters(int count);

  /// No description provided for @profileDetailSiblingsLine.
  ///
  /// In en, this message translates to:
  /// **'Siblings: {brothers}, {sisters}'**
  String profileDetailSiblingsLine(String brothers, String sisters);

  /// No description provided for @profileDetailTimeAgoMonths8.
  ///
  /// In en, this message translates to:
  /// **'8 months ago'**
  String get profileDetailTimeAgoMonths8;

  /// No description provided for @profileDetailTimeAgoWeeks2.
  ///
  /// In en, this message translates to:
  /// **'2 weeks ago'**
  String get profileDetailTimeAgoWeeks2;

  /// No description provided for @profileDetailTimeAgoMonth1.
  ///
  /// In en, this message translates to:
  /// **'1 month ago'**
  String get profileDetailTimeAgoMonth1;

  /// No description provided for @profileDetailTimeAgoJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get profileDetailTimeAgoJustNow;

  /// No description provided for @inboxPreviewPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get inboxPreviewPhoto;

  /// No description provided for @inboxPreviewDocument.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get inboxPreviewDocument;

  /// No description provided for @inboxEditedSuffix.
  ///
  /// In en, this message translates to:
  /// **' (edited)'**
  String get inboxEditedSuffix;

  /// No description provided for @astroExcellentMatch.
  ///
  /// In en, this message translates to:
  /// **'Excellent Match'**
  String get astroExcellentMatch;

  /// No description provided for @profileIdLabel.
  ///
  /// In en, this message translates to:
  /// **'ID: {id}'**
  String profileIdLabel(String id);

  /// No description provided for @authIdentifierLabel.
  ///
  /// In en, this message translates to:
  /// **'Email or Mobile Number'**
  String get authIdentifierLabel;

  /// No description provided for @authIdentifierHint.
  ///
  /// In en, this message translates to:
  /// **'name@example.com or 9876543210'**
  String get authIdentifierHint;

  /// No description provided for @authIdentifierRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your email or mobile number'**
  String get authIdentifierRequired;

  /// No description provided for @authIdentifierInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address or 10-digit mobile number'**
  String get authIdentifierInvalid;

  /// No description provided for @authNoAccountForMobile.
  ///
  /// In en, this message translates to:
  /// **'No account found for this mobile number.'**
  String get authNoAccountForMobile;

  /// No description provided for @authAccountCheckUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server. Please try again.'**
  String get authAccountCheckUnavailable;

  /// No description provided for @authOtpRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the code we sent you'**
  String get authOtpRequired;

  /// No description provided for @drawerSectionMatchActivity.
  ///
  /// In en, this message translates to:
  /// **'Your Match Activity'**
  String get drawerSectionMatchActivity;

  /// No description provided for @drawerSectionSettings.
  ///
  /// In en, this message translates to:
  /// **'Options & Settings'**
  String get drawerSectionSettings;

  /// No description provided for @drawerCopyIdSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Copy profile ID'**
  String get drawerCopyIdSemanticLabel;

  /// No description provided for @drawerIdCopied.
  ///
  /// In en, this message translates to:
  /// **'Profile ID copied'**
  String get drawerIdCopied;

  /// No description provided for @drawerTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get drawerTerms;

  /// No description provided for @drawerCopyright.
  ///
  /// In en, this message translates to:
  /// **'© {year} Nenjam Matrimony'**
  String drawerCopyright(String year);

  /// No description provided for @drawerVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String drawerVersion(String version);

  /// No description provided for @partnerPrefIntro.
  ///
  /// In en, this message translates to:
  /// **'You will see Matches based on the Preferences you have set'**
  String get partnerPrefIntro;

  /// No description provided for @welcomeBackHeadline.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBackHeadline;

  /// No description provided for @welcomeBackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your details to continue'**
  String get welcomeBackSubtitle;

  /// No description provided for @welcomeBackGetOtp.
  ///
  /// In en, this message translates to:
  /// **'Get OTP'**
  String get welcomeBackGetOtp;

  /// No description provided for @welcomeBackPassword.
  ///
  /// In en, this message translates to:
  /// **'Login with Password'**
  String get welcomeBackPassword;

  /// No description provided for @welcomeBackGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get welcomeBackGoogle;

  /// No description provided for @welcomeBackEmail.
  ///
  /// In en, this message translates to:
  /// **'Continue with Email'**
  String get welcomeBackEmail;

  /// No description provided for @welcomeBackNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get welcomeBackNoAccount;

  /// No description provided for @welcomeBackSignUpFree.
  ///
  /// In en, this message translates to:
  /// **'Sign Up Free'**
  String get welcomeBackSignUpFree;

  /// No description provided for @nearbyTitle.
  ///
  /// In en, this message translates to:
  /// **'Near Me'**
  String get nearbyTitle;

  /// No description provided for @drawerNearMe.
  ///
  /// In en, this message translates to:
  /// **'Near Me'**
  String get drawerNearMe;

  /// No description provided for @nearbyLoading.
  ///
  /// In en, this message translates to:
  /// **'Finding people near you...'**
  String get nearbyLoading;

  /// No description provided for @nearbyDistanceAway.
  ///
  /// In en, this message translates to:
  /// **'{distance} km away'**
  String nearbyDistanceAway(String distance);

  /// No description provided for @nearbyDistanceUnderOneKm.
  ///
  /// In en, this message translates to:
  /// **'Less than 1 km away'**
  String get nearbyDistanceUnderOneKm;

  /// No description provided for @nearbyApproximateNotice.
  ///
  /// In en, this message translates to:
  /// **'You shared an approximate location, so distances are rough.'**
  String get nearbyApproximateNotice;

  /// No description provided for @nearbyEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No one nearby yet'**
  String get nearbyEmptyTitle;

  /// No description provided for @nearbyEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No profiles found within {radius} km of your location.'**
  String nearbyEmptyMessage(String radius);

  /// No description provided for @nearbyRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get nearbyRefresh;

  /// No description provided for @nearbyPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Location access needed'**
  String get nearbyPermissionTitle;

  /// No description provided for @nearbyPermissionMessage.
  ///
  /// In en, this message translates to:
  /// **'Location access is required to discover people near you.'**
  String get nearbyPermissionMessage;

  /// No description provided for @nearbyPermissionBlockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Location access is blocked. Turn it on in Settings to discover people near you.'**
  String get nearbyPermissionBlockedMessage;

  /// No description provided for @nearbyEnableLocation.
  ///
  /// In en, this message translates to:
  /// **'Enable Location'**
  String get nearbyEnableLocation;

  /// No description provided for @nearbyOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get nearbyOpenSettings;

  /// No description provided for @nearbyServicesOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Location is turned off'**
  String get nearbyServicesOffTitle;

  /// No description provided for @nearbyServicesOffMessage.
  ///
  /// In en, this message translates to:
  /// **'Turn on location services to discover people near you.'**
  String get nearbyServicesOffMessage;

  /// No description provided for @nearbyTurnOnLocation.
  ///
  /// In en, this message translates to:
  /// **'Turn On Location'**
  String get nearbyTurnOnLocation;

  /// No description provided for @nearbyErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get nearbyErrorTitle;

  /// No description provided for @nearbyLocationErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Unable to get your location. Please try again.'**
  String get nearbyLocationErrorMessage;

  /// No description provided for @nearbyFetchErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Unable to load profiles near you. Please try again.'**
  String get nearbyFetchErrorMessage;

  /// No description provided for @nearbyRetry.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get nearbyRetry;

  /// No description provided for @nearbyDiscoverPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Find people near you'**
  String get nearbyDiscoverPromptTitle;

  /// No description provided for @nearbyDiscoverPromptMessage.
  ///
  /// In en, this message translates to:
  /// **'Enable location to discover compatible profiles within {radius} km of you.'**
  String nearbyDiscoverPromptMessage(String radius);

  /// No description provided for @completionCardTitleRegistration.
  ///
  /// In en, this message translates to:
  /// **'Finish Registration'**
  String get completionCardTitleRegistration;

  /// No description provided for @completionCardBodyRegistration.
  ///
  /// In en, this message translates to:
  /// **'A few answers are still missing.'**
  String get completionCardBodyRegistration;

  /// No description provided for @completionCardTitlePhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo(s)'**
  String get completionCardTitlePhoto;

  /// No description provided for @completionCardBodyPhoto.
  ///
  /// In en, this message translates to:
  /// **'Profiles with photos get far more interest.'**
  String get completionCardBodyPhoto;

  /// No description provided for @completionCardTitleFamily.
  ///
  /// In en, this message translates to:
  /// **'Family Details'**
  String get completionCardTitleFamily;

  /// No description provided for @completionCardBodyFamily.
  ///
  /// In en, this message translates to:
  /// **'Share your family background.'**
  String get completionCardBodyFamily;

  /// No description provided for @completionCardTitleHoroscope.
  ///
  /// In en, this message translates to:
  /// **'Horoscope'**
  String get completionCardTitleHoroscope;

  /// No description provided for @completionCardBodyHoroscope.
  ///
  /// In en, this message translates to:
  /// **'Add birth details for astrology matching.'**
  String get completionCardBodyHoroscope;

  /// No description provided for @completionCardTitleVerification.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get completionCardTitleVerification;

  /// No description provided for @completionCardBodyVerification.
  ///
  /// In en, this message translates to:
  /// **'Get verified to earn more trust.'**
  String get completionCardBodyVerification;

  /// No description provided for @completionCardTitlePsychology.
  ///
  /// In en, this message translates to:
  /// **'Psychology Test'**
  String get completionCardTitlePsychology;

  /// No description provided for @completionCardBodyPsychology.
  ///
  /// In en, this message translates to:
  /// **'Share your expectations for married life.'**
  String get completionCardBodyPsychology;

  /// No description provided for @completionCardShortTitlePhoto.
  ///
  /// In en, this message translates to:
  /// **'Add Photos'**
  String get completionCardShortTitlePhoto;

  /// No description provided for @completionCardShortTitlePsychology.
  ///
  /// In en, this message translates to:
  /// **'Psychology'**
  String get completionCardShortTitlePsychology;

  /// No description provided for @completionCardTitlePartnerPreference.
  ///
  /// In en, this message translates to:
  /// **'Partner Preferences'**
  String get completionCardTitlePartnerPreference;

  /// No description provided for @completionCardBodyPartnerPreference.
  ///
  /// In en, this message translates to:
  /// **'Tell us who you\'re looking for.'**
  String get completionCardBodyPartnerPreference;

  /// No description provided for @completionCardStatusOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get completionCardStatusOptional;

  /// No description provided for @completionCardDismissTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide this suggestion'**
  String get completionCardDismissTooltip;

  /// No description provided for @completionCardDismissed.
  ///
  /// In en, this message translates to:
  /// **'Hidden. Your saved details are untouched.'**
  String get completionCardDismissed;

  /// No description provided for @completionCardDismissFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not hide that just now. Please try again.'**
  String get completionCardDismissFailed;

  /// No description provided for @completionCardsScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Profile completeness score {percent}%'**
  String completionCardsScoreLabel(int percent);

  /// No description provided for @faceVerificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Account on hold'**
  String get faceVerificationTitle;

  /// No description provided for @faceVerificationExplanation.
  ///
  /// In en, this message translates to:
  /// **'As part of our routine safety checks, please complete a quick selfie verification to continue using your account.'**
  String get faceVerificationExplanation;

  /// No description provided for @faceVerificationConsent.
  ///
  /// In en, this message translates to:
  /// **'Your video selfie is sent to Amazon Web Services only to check that you are a real person and that you match your main profile photo. Nenjam does not store your selfie video or selfie image — we keep only the result (verified or not).'**
  String get faceVerificationConsent;

  /// No description provided for @faceVerificationCta.
  ///
  /// In en, this message translates to:
  /// **'Verify with Selfie'**
  String get faceVerificationCta;

  /// No description provided for @faceVerificationConsentShort.
  ///
  /// In en, this message translates to:
  /// **'Your selfie is checked by Amazon Web Services to confirm you are real and match your photo. Nenjam stores no selfie — only the result.'**
  String get faceVerificationConsentShort;

  /// No description provided for @faceVerificationConsentLearnMore.
  ///
  /// In en, this message translates to:
  /// **'Learn more'**
  String get faceVerificationConsentLearnMore;

  /// No description provided for @faceVerificationVerifying.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get faceVerificationVerifying;

  /// No description provided for @faceVerificationPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Verification selfies are NOT shown to others.'**
  String get faceVerificationPrivacyNote;

  /// No description provided for @faceVerificationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Verification is unavailable right now.'**
  String get faceVerificationUnavailable;

  /// No description provided for @faceVerificationAlreadyVerified.
  ///
  /// In en, this message translates to:
  /// **'You\'re already verified.'**
  String get faceVerificationAlreadyVerified;

  /// No description provided for @faceVerificationNoPrimaryPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a clear photo of your face first.'**
  String get faceVerificationNoPrimaryPhoto;

  /// No description provided for @faceVerificationUnsupportedPhoto.
  ///
  /// In en, this message translates to:
  /// **'Update your main photo to continue.'**
  String get faceVerificationUnsupportedPhoto;

  /// No description provided for @faceVerificationAttemptLimit.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached today\'s limit. Please try again later.'**
  String get faceVerificationAttemptLimit;

  /// No description provided for @faceVerificationFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t complete verification.'**
  String get faceVerificationFailedGeneric;

  /// No description provided for @faceVerificationFailedLiveness.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm you\'re a live person. Please try again in good lighting.'**
  String get faceVerificationFailedLiveness;

  /// No description provided for @faceVerificationFailedMatch.
  ///
  /// In en, this message translates to:
  /// **'This selfie doesn\'t match your main profile photo.'**
  String get faceVerificationFailedMatch;

  /// No description provided for @faceVerificationNoFaceInPhoto.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find a face in your main profile photo.'**
  String get faceVerificationNoFaceInPhoto;

  /// No description provided for @faceVerificationMultipleFaces.
  ///
  /// In en, this message translates to:
  /// **'Your main profile photo shows more than one face.'**
  String get faceVerificationMultipleFaces;

  /// No description provided for @faceVerificationPhotoChanged.
  ///
  /// In en, this message translates to:
  /// **'Your main profile photo changed since you were verified. Please verify again.'**
  String get faceVerificationPhotoChanged;

  /// No description provided for @faceVerificationExpired.
  ///
  /// In en, this message translates to:
  /// **'That attempt expired. Please try again.'**
  String get faceVerificationExpired;

  /// No description provided for @faceVerificationCancelled.
  ///
  /// In en, this message translates to:
  /// **'Verification was cancelled.'**
  String get faceVerificationCancelled;

  /// No description provided for @faceVerificationNetworkError.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm your result. Please check your connection and try again.'**
  String get faceVerificationNetworkError;

  /// No description provided for @faceVerificationUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Face verification isn\'t available in a web browser. Please use the Nenjam Matrimony Android app to verify your face.'**
  String get faceVerificationUnsupported;

  /// No description provided for @faceVerificationCameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera access is required for selfie verification.'**
  String get faceVerificationCameraPermissionDenied;

  /// No description provided for @faceVerificationOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get faceVerificationOpenSettings;

  /// No description provided for @faceVerificationUpdatePhoto.
  ///
  /// In en, this message translates to:
  /// **'Update main photo'**
  String get faceVerificationUpdatePhoto;

  /// No description provided for @faceVerificationCenterVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get faceVerificationCenterVerified;

  /// No description provided for @faceVerificationCenterReverify.
  ///
  /// In en, this message translates to:
  /// **'Your main photo changed — re-verify'**
  String get faceVerificationCenterReverify;

  /// No description provided for @faceVerificationCenterIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Not verified yet'**
  String get faceVerificationCenterIncomplete;

  /// No description provided for @photoViewerPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous photo'**
  String get photoViewerPrevious;

  /// No description provided for @photoViewerNext.
  ///
  /// In en, this message translates to:
  /// **'Next photo'**
  String get photoViewerNext;

  /// No description provided for @nearbyPermissionBlockedMessageWeb.
  ///
  /// In en, this message translates to:
  /// **'Location is blocked for this site. Allow it in your browser\'s site settings (next to the address bar), then try again.'**
  String get nearbyPermissionBlockedMessageWeb;

  /// No description provided for @profileLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Profile link copied'**
  String get profileLinkCopied;

  /// No description provided for @discoverLoadMoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load more profiles.'**
  String get discoverLoadMoreFailed;

  /// No description provided for @membershipLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load membership details.'**
  String get membershipLoadError;

  /// No description provided for @membershipCardFreeTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the Free plan'**
  String get membershipCardFreeTitle;

  /// No description provided for @membershipCardFreeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See what each membership plan includes.'**
  String get membershipCardFreeSubtitle;

  /// No description provided for @membershipCardFreeSubtitleSoon.
  ///
  /// In en, this message translates to:
  /// **'Paid plans are coming soon.'**
  String get membershipCardFreeSubtitleSoon;

  /// No description provided for @membershipCardPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'{plan} member'**
  String membershipCardPlanTitle(String plan);

  /// No description provided for @membershipCardActiveUntil.
  ///
  /// In en, this message translates to:
  /// **'Active until {date}'**
  String membershipCardActiveUntil(String date);

  /// No description provided for @membershipCardQueued.
  ///
  /// In en, this message translates to:
  /// **'{plan} starts on {date}'**
  String membershipCardQueued(String plan, String date);

  /// No description provided for @membershipCardViewMembership.
  ///
  /// In en, this message translates to:
  /// **'View membership'**
  String get membershipCardViewMembership;

  /// No description provided for @membershipHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Membership history'**
  String get membershipHistoryTitle;

  /// No description provided for @membershipHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No purchases or plan changes yet.'**
  String get membershipHistoryEmpty;

  /// No description provided for @membershipStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get membershipStatusPending;

  /// No description provided for @membershipStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get membershipStatusActive;

  /// No description provided for @membershipStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get membershipStatusExpired;

  /// No description provided for @membershipStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get membershipStatusCancelled;

  /// No description provided for @membershipStatusRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get membershipStatusRefunded;

  /// No description provided for @membershipStatusRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get membershipStatusRevoked;

  /// No description provided for @membershipSourceGrant.
  ///
  /// In en, this message translates to:
  /// **'Granted by Nenjam'**
  String get membershipSourceGrant;

  /// No description provided for @membershipMonths.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 month} other{{count} months}}'**
  String membershipMonths(int count);

  /// No description provided for @membershipCurrentPlan.
  ///
  /// In en, this message translates to:
  /// **'Current plan'**
  String get membershipCurrentPlan;

  /// No description provided for @membershipFeatureIncluded.
  ///
  /// In en, this message translates to:
  /// **'Included'**
  String get membershipFeatureIncluded;

  /// No description provided for @membershipFeatureNotIncluded.
  ///
  /// In en, this message translates to:
  /// **'Not included'**
  String get membershipFeatureNotIncluded;

  /// No description provided for @membershipFeatureUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get membershipFeatureUnlimited;

  /// No description provided for @membershipFeaturePerMonth.
  ///
  /// In en, this message translates to:
  /// **'{count} per month'**
  String membershipFeaturePerMonth(int count);

  /// No description provided for @membershipFeaturePerDay.
  ///
  /// In en, this message translates to:
  /// **'{count} per day'**
  String membershipFeaturePerDay(int count);

  /// No description provided for @membershipFeatureEveryMonths.
  ///
  /// In en, this message translates to:
  /// **'{count} every {months} months'**
  String membershipFeatureEveryMonths(int count, int months);

  /// No description provided for @membershipStartsOn.
  ///
  /// In en, this message translates to:
  /// **'Starts on {date}'**
  String membershipStartsOn(String date);

  /// No description provided for @membershipBuy.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get membershipBuy;

  /// No description provided for @membershipPurchaseUnavailableHere.
  ///
  /// In en, this message translates to:
  /// **'Buying isn\'t available in this version of the app yet.'**
  String get membershipPurchaseUnavailableHere;

  /// No description provided for @membershipPurchaseWebNote.
  ///
  /// In en, this message translates to:
  /// **'Buy membership in the Nenjam app.'**
  String get membershipPurchaseWebNote;

  /// No description provided for @membershipPurchaseActivated.
  ///
  /// In en, this message translates to:
  /// **'Your membership is active.'**
  String get membershipPurchaseActivated;

  /// No description provided for @membershipPurchaseActivationPending.
  ///
  /// In en, this message translates to:
  /// **'Payment received. Your membership will be activated shortly.'**
  String get membershipPurchaseActivationPending;

  /// No description provided for @membershipPurchaseCancelled.
  ///
  /// In en, this message translates to:
  /// **'Payment cancelled.'**
  String get membershipPurchaseCancelled;

  /// No description provided for @membershipPurchaseFailed.
  ///
  /// In en, this message translates to:
  /// **'The payment didn\'t go through.'**
  String get membershipPurchaseFailed;

  /// No description provided for @membershipPurchaseContactSupport.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm this payment. Please contact support.'**
  String get membershipPurchaseContactSupport;

  /// No description provided for @membershipPurchaseStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the payment, try again.'**
  String get membershipPurchaseStartFailed;

  /// No description provided for @membershipCheckoutPlanPrice.
  ///
  /// In en, this message translates to:
  /// **'Plan price'**
  String get membershipCheckoutPlanPrice;

  /// No description provided for @membershipCheckoutReferralDiscount.
  ///
  /// In en, this message translates to:
  /// **'Referral discount'**
  String get membershipCheckoutReferralDiscount;

  /// No description provided for @membershipCheckoutGst.
  ///
  /// In en, this message translates to:
  /// **'GST ({rate}%)'**
  String membershipCheckoutGst(String rate);

  /// No description provided for @membershipCheckoutTotal.
  ///
  /// In en, this message translates to:
  /// **'Total payable'**
  String get membershipCheckoutTotal;

  /// No description provided for @membershipCheckoutPay.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount}'**
  String membershipCheckoutPay(String amount);

  /// No description provided for @membershipCheckoutVerifying.
  ///
  /// In en, this message translates to:
  /// **'Confirming your payment…'**
  String get membershipCheckoutVerifying;

  /// No description provided for @membershipCheckoutUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Checkout isn\'t available right now. Try again shortly.'**
  String get membershipCheckoutUnavailable;

  /// No description provided for @membershipPromoCodesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Referral codes can\'t be used yet.'**
  String get membershipPromoCodesUnavailable;

  /// No description provided for @membershipPromoCodeApplied.
  ///
  /// In en, this message translates to:
  /// **'Code {code} applied'**
  String membershipPromoCodeApplied(String code);

  /// No description provided for @membershipVerificationUncertain.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm your payment yet. Please don\'t pay again: if money was taken, your plan will be activated.'**
  String get membershipVerificationUncertain;

  /// No description provided for @membershipCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get membershipCheckAgain;

  /// No description provided for @membershipCheckoutContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get membershipCheckoutContinue;

  /// No description provided for @membershipCheckoutActivating.
  ///
  /// In en, this message translates to:
  /// **'Payment received, activating your plan…'**
  String get membershipCheckoutActivating;

  /// No description provided for @membershipPurchaseAlreadyApplied.
  ///
  /// In en, this message translates to:
  /// **'This payment has already been applied to your membership.'**
  String get membershipPurchaseAlreadyApplied;

  /// No description provided for @membershipPurchaseRefunded.
  ///
  /// In en, this message translates to:
  /// **'This payment was refunded, so no plan was added. Please contact support if you need help.'**
  String get membershipPurchaseRefunded;

  /// No description provided for @membershipPromoInvalid.
  ///
  /// In en, this message translates to:
  /// **'Code not found.'**
  String get membershipPromoInvalid;

  /// No description provided for @membershipPromoNotFirstPlan.
  ///
  /// In en, this message translates to:
  /// **'Codes apply to your first plan only.'**
  String get membershipPromoNotFirstPlan;

  /// No description provided for @membershipPromoAlreadyAttributed.
  ///
  /// In en, this message translates to:
  /// **'You\'re already linked to an agent; their discount applies automatically.'**
  String get membershipPromoAlreadyAttributed;

  /// No description provided for @membershipPromoSelfReferral.
  ///
  /// In en, this message translates to:
  /// **'You can\'t use your own referral code.'**
  String get membershipPromoSelfReferral;

  /// No description provided for @membershipPromoAgentPaused.
  ///
  /// In en, this message translates to:
  /// **'This referral code can\'t be used right now.'**
  String get membershipPromoAgentPaused;

  /// No description provided for @membershipPromoPhoneNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Verify your mobile number to use a referral code.'**
  String get membershipPromoPhoneNotVerified;

  /// No description provided for @membershipDenialTitle.
  ///
  /// In en, this message translates to:
  /// **'Your membership plan'**
  String get membershipDenialTitle;

  /// No description provided for @membershipDenialSeePlans.
  ///
  /// In en, this message translates to:
  /// **'See membership plans'**
  String get membershipDenialSeePlans;

  /// No description provided for @membershipDenialResetsOn.
  ///
  /// In en, this message translates to:
  /// **'Your allowance resets on {date}.'**
  String membershipDenialResetsOn(String date);

  /// No description provided for @referralCodePrompt.
  ///
  /// In en, this message translates to:
  /// **'Have a referral code?'**
  String get referralCodePrompt;

  /// No description provided for @referralCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Enter the code someone shared with you.'**
  String get referralCodeHelp;

  /// No description provided for @referralCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Referral code'**
  String get referralCodeLabel;

  /// No description provided for @referralCodeApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get referralCodeApply;

  /// No description provided for @referralCodeRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get referralCodeRemove;

  /// No description provided for @referralCodeReferredBy.
  ///
  /// In en, this message translates to:
  /// **'Referred by {name}'**
  String referralCodeReferredBy(String name);

  /// No description provided for @referralCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'This code isn\'t valid'**
  String get referralCodeInvalid;

  /// No description provided for @referralCodeTooManyTries.
  ///
  /// In en, this message translates to:
  /// **'Too many tries, please wait'**
  String get referralCodeTooManyTries;

  /// No description provided for @referralCodeTooManyTriesSeconds.
  ///
  /// In en, this message translates to:
  /// **'Too many tries, please wait {seconds} seconds'**
  String referralCodeTooManyTriesSeconds(int seconds);

  /// No description provided for @referralCodeCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t check this code right now. You can carry on and try again later.'**
  String get referralCodeCheckFailed;

  /// No description provided for @referralCodeAttached.
  ///
  /// In en, this message translates to:
  /// **'Referral code applied.'**
  String get referralCodeAttached;

  /// No description provided for @referralCodeAlreadyLinked.
  ///
  /// In en, this message translates to:
  /// **'Your account is already linked to a referral code.'**
  String get referralCodeAlreadyLinked;

  /// No description provided for @referralCodeNotApplied.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t apply your referral code. Your signup is not affected.'**
  String get referralCodeNotApplied;

  /// No description provided for @referralCodeNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This referral code can\'t be used with your account.'**
  String get referralCodeNotAllowed;

  /// No description provided for @referralCodeRetryLater.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t apply your referral code yet. We\'ll try again later.'**
  String get referralCodeRetryLater;

  /// No description provided for @partnerHelpEntry.
  ///
  /// In en, this message translates to:
  /// **'Nenjam Partner Program help'**
  String get partnerHelpEntry;

  /// No description provided for @partnerHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get partnerHelpTitle;

  /// No description provided for @partnerHelpWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to the Nenjam Partner Program.'**
  String get partnerHelpWelcome;

  /// No description provided for @partnerHelpGettingStartedTitle.
  ///
  /// In en, this message translates to:
  /// **'Getting started'**
  String get partnerHelpGettingStartedTitle;

  /// No description provided for @partnerHelpGettingStartedBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your mobile number and the one-time code (OTP) we send you. Then fill in your application. Our team reviews it and either approves it or tells you why it was not approved. Once you are approved, you get your personal referral code.'**
  String get partnerHelpGettingStartedBody;

  /// No description provided for @partnerHelpReferringTitle.
  ///
  /// In en, this message translates to:
  /// **'Referring members'**
  String get partnerHelpReferringTitle;

  /// No description provided for @partnerHelpReferringBody.
  ///
  /// In en, this message translates to:
  /// **'Share your referral code, or the ready-made English or Tamil message in the portal. People can enter your code when they sign up, or at payment when they buy their first paid plan. A person stays linked to the first agent whose code they used.'**
  String get partnerHelpReferringBody;

  /// No description provided for @partnerHelpTrackingTitle.
  ///
  /// In en, this message translates to:
  /// **'Tracking referrals and earnings'**
  String get partnerHelpTrackingTitle;

  /// No description provided for @partnerHelpTrackingBody.
  ///
  /// In en, this message translates to:
  /// **'For privacy, you only see limited details about the people you referred: first name and last initial, age, city, their stage and a partly hidden phone number. You earn a commission only when someone you referred buys their first paid plan, and only once. Renewals and later plans do not earn commission. The commission is held for a short period, then approved, and paid by our team in the monthly payout.'**
  String get partnerHelpTrackingBody;

  /// No description provided for @partnerHelpBankTitle.
  ///
  /// In en, this message translates to:
  /// **'Bank details'**
  String get partnerHelpBankTitle;

  /// No description provided for @partnerHelpBankBody.
  ///
  /// In en, this message translates to:
  /// **'Add your UPI ID or bank account details carefully and check them before saving. Your PAN is needed before your first payout. If you change your payment details, they are checked again and your next payout may wait a short while.'**
  String get partnerHelpBankBody;

  /// No description provided for @partnerHelpTermsTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent terms (main points)'**
  String get partnerHelpTermsTitle;

  /// No description provided for @partnerHelpTermNoFees.
  ///
  /// In en, this message translates to:
  /// **'Never charge families any fee for joining.'**
  String get partnerHelpTermNoFees;

  /// No description provided for @partnerHelpTermNoFalsePromises.
  ///
  /// In en, this message translates to:
  /// **'Never make false promises about matches.'**
  String get partnerHelpTermNoFalsePromises;

  /// No description provided for @partnerHelpTermNoSharing.
  ///
  /// In en, this message translates to:
  /// **'Never share information about the people you refer or your clients.'**
  String get partnerHelpTermNoSharing;

  /// No description provided for @partnerHelpTermConsent.
  ///
  /// In en, this message translates to:
  /// **'Never create a profile for someone without their agreement.'**
  String get partnerHelpTermConsent;

  /// No description provided for @partnerHelpTermsConsequence.
  ///
  /// In en, this message translates to:
  /// **'Breaking these rules can lead to your account being paused.'**
  String get partnerHelpTermsConsequence;

  /// No description provided for @partnerHelpNeedHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Need help?'**
  String get partnerHelpNeedHelpTitle;

  /// No description provided for @partnerHelpContact.
  ///
  /// In en, this message translates to:
  /// **'Contact the Nenjam team at {contact}.'**
  String partnerHelpContact(String contact);

  /// No description provided for @partnerHelpOtpWarning.
  ///
  /// In en, this message translates to:
  /// **'Never share your OTP or any login details with anyone.'**
  String get partnerHelpOtpWarning;

  /// No description provided for @agentShareCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get agentShareCopyCode;

  /// No description provided for @agentShareCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get agentShareCodeCopied;

  /// No description provided for @agentShareWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Share on WhatsApp'**
  String get agentShareWhatsApp;

  /// No description provided for @agentShareLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get agentShareLanguageEnglish;

  /// No description provided for @agentShareLanguageTamil.
  ///
  /// In en, this message translates to:
  /// **'தமிழ்'**
  String get agentShareLanguageTamil;

  /// No description provided for @agentShareNotShareable.
  ///
  /// In en, this message translates to:
  /// **'Sharing is turned off for this code right now.'**
  String get agentShareNotShareable;

  /// No description provided for @agentShareNoMessage.
  ///
  /// In en, this message translates to:
  /// **'No ready-made message is available for this language.'**
  String get agentShareNoMessage;

  /// No description provided for @agentShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open WhatsApp. You can copy the code instead.'**
  String get agentShareFailed;

  /// No description provided for @agentShareLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your referral codes.'**
  String get agentShareLoadFailed;

  /// No description provided for @agentShareNoCodes.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have a referral code yet.'**
  String get agentShareNoCodes;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ta':
      return AppLocalizationsTa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
