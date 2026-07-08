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

  /// No description provided for @authRegisteringForLabel.
  ///
  /// In en, this message translates to:
  /// **'Registering for'**
  String get authRegisteringForLabel;

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

  /// No description provided for @homeSeeAllButton.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get homeSeeAllButton;

  /// No description provided for @homeAiRecommendationsTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Match Recommendations'**
  String get homeAiRecommendationsTitle;

  /// No description provided for @homeRecentlyJoinedTitle.
  ///
  /// In en, this message translates to:
  /// **'Recently Joined'**
  String get homeRecentlyJoinedTitle;

  /// No description provided for @homeCompleteProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete Your Profile'**
  String get homeCompleteProfileTitle;

  /// No description provided for @homeProfileNextStep.
  ///
  /// In en, this message translates to:
  /// **'Next: {step}'**
  String homeProfileNextStep(String step);

  /// No description provided for @homeStepUploadHoroscope.
  ///
  /// In en, this message translates to:
  /// **'Upload Horoscope'**
  String get homeStepUploadHoroscope;

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

  /// No description provided for @homeAiMatchLabel.
  ///
  /// In en, this message translates to:
  /// **'match'**
  String get homeAiMatchLabel;

  /// No description provided for @homeNewTodayLabel.
  ///
  /// In en, this message translates to:
  /// **'New Today'**
  String get homeNewTodayLabel;

  /// No description provided for @homeVerifiedProfilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Verified Profiles'**
  String get homeVerifiedProfilesTitle;

  /// No description provided for @homeNearYouTitle.
  ///
  /// In en, this message translates to:
  /// **'Near You'**
  String get homeNearYouTitle;

  /// No description provided for @homePremiumMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Premium Members'**
  String get homePremiumMembersTitle;

  /// No description provided for @homeSearchingMoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Searching for more souls…'**
  String get homeSearchingMoreLabel;

  /// No description provided for @homeVerifiedLabel.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get homeVerifiedLabel;

  /// No description provided for @homePremiumLabel.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get homePremiumLabel;

  /// No description provided for @homePsychologyCompletedLabel.
  ///
  /// In en, this message translates to:
  /// **'Psychology Completed'**
  String get homePsychologyCompletedLabel;

  /// No description provided for @homeChipVerifiedIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verified Identity'**
  String get homeChipVerifiedIdentity;

  /// No description provided for @homeChipPremiumPlus.
  ///
  /// In en, this message translates to:
  /// **'Premium Plus'**
  String get homeChipPremiumPlus;

  /// No description provided for @homeChipNri.
  ///
  /// In en, this message translates to:
  /// **'NRI'**
  String get homeChipNri;

  /// No description provided for @homePhotoProtectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Photo Protected'**
  String get homePhotoProtectedLabel;

  /// No description provided for @homeInterestSentLabel.
  ///
  /// In en, this message translates to:
  /// **'Interest Sent'**
  String get homeInterestSentLabel;

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

  /// No description provided for @homePsychologyMatchScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Psychology Match'**
  String get homePsychologyMatchScoreLabel;

  /// No description provided for @homeCompatibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Compatibility'**
  String get homeCompatibilityLabel;

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

  /// No description provided for @homeFilterLabel.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get homeFilterLabel;

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

  /// No description provided for @navAstro.
  ///
  /// In en, this message translates to:
  /// **'Astro'**
  String get navAstro;

  /// No description provided for @navPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get navPremium;

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

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get chatTitle;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

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
  /// **'Upgrade to Luxury Premium'**
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

  /// No description provided for @premiumProceedToPayment.
  ///
  /// In en, this message translates to:
  /// **'Proceed to Payment'**
  String get premiumProceedToPayment;

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

  /// No description provided for @settingsDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get settingsDarkMode;

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

  /// No description provided for @registrationStepIndicator.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String registrationStepIndicator(int current, int total);

  /// No description provided for @registrationSaveExit.
  ///
  /// In en, this message translates to:
  /// **'Save & Exit'**
  String get registrationSaveExit;

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

  /// No description provided for @registrationFinishLogin.
  ///
  /// In en, this message translates to:
  /// **'Finish & Login'**
  String get registrationFinishLogin;

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

  /// No description provided for @registrationDobHint.
  ///
  /// In en, this message translates to:
  /// **'DD / MM / YYYY'**
  String get registrationDobHint;

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
  /// **'Sub Caste (Optional)'**
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

  /// No description provided for @registrationAreaLabel.
  ///
  /// In en, this message translates to:
  /// **'Area (Optional)'**
  String get registrationAreaLabel;

  /// No description provided for @registrationAreaHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., T. Nagar'**
  String get registrationAreaHint;

  /// No description provided for @registrationPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN Code (Optional)'**
  String get registrationPinLabel;

  /// No description provided for @registrationPinHint.
  ///
  /// In en, this message translates to:
  /// **'600017'**
  String get registrationPinHint;

  /// No description provided for @registrationNativePlaceLabel.
  ///
  /// In en, this message translates to:
  /// **'Native Place (Optional)'**
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

  /// No description provided for @registrationCollegeLabel.
  ///
  /// In en, this message translates to:
  /// **'College / University (Optional)'**
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

  /// No description provided for @registrationCompanyLabel.
  ///
  /// In en, this message translates to:
  /// **'Company (Optional)'**
  String get registrationCompanyLabel;

  /// No description provided for @registrationCompanyHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Google'**
  String get registrationCompanyHint;

  /// No description provided for @registrationEmploymentTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Employment Type'**
  String get registrationEmploymentTypeLabel;

  /// No description provided for @registrationAnnualIncomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Annual Income'**
  String get registrationAnnualIncomeLabel;

  /// No description provided for @registrationWorkLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Work Location (Optional)'**
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

  /// No description provided for @incomePreferNotSay.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get incomePreferNotSay;

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

  /// No description provided for @registrationWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get registrationWeightLabel;

  /// No description provided for @registrationBodyTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Body Type'**
  String get registrationBodyTypeLabel;

  /// No description provided for @registrationComplexionLabel.
  ///
  /// In en, this message translates to:
  /// **'Complexion'**
  String get registrationComplexionLabel;

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

  /// No description provided for @bodySlim.
  ///
  /// In en, this message translates to:
  /// **'Slim'**
  String get bodySlim;

  /// No description provided for @bodyAverage.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get bodyAverage;

  /// No description provided for @bodyAthletic.
  ///
  /// In en, this message translates to:
  /// **'Athletic'**
  String get bodyAthletic;

  /// No description provided for @bodyHeavy.
  ///
  /// In en, this message translates to:
  /// **'Heavy'**
  String get bodyHeavy;

  /// No description provided for @complexionVeryFair.
  ///
  /// In en, this message translates to:
  /// **'Very Fair'**
  String get complexionVeryFair;

  /// No description provided for @complexionFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get complexionFair;

  /// No description provided for @complexionWheatish.
  ///
  /// In en, this message translates to:
  /// **'Wheatish'**
  String get complexionWheatish;

  /// No description provided for @complexionDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get complexionDark;

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

  /// No description provided for @registrationBrothersLabel.
  ///
  /// In en, this message translates to:
  /// **'No. of Brothers'**
  String get registrationBrothersLabel;

  /// No description provided for @registrationSistersLabel.
  ///
  /// In en, this message translates to:
  /// **'No. of Sisters'**
  String get registrationSistersLabel;

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

  /// No description provided for @registrationProfileForTitle.
  ///
  /// In en, this message translates to:
  /// **'Who are you creating this profile for?'**
  String get registrationProfileForTitle;

  /// No description provided for @registrationProfileForSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select the relationship'**
  String get registrationProfileForSubtitle;

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
