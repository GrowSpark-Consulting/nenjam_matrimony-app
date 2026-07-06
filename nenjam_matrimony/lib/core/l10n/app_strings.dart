/// Nenjam Matrimony — Centralized Localization Strings
///
/// Stores strings for multi-language support. No hardcoded
/// user-facing text should exist outside localization delegates.
abstract final class AppStrings {
  // ─── Common ──────────────────────────────────────────────────────
  static const String appName = 'Nenjam Matrimony';
  static const String appTagline = 'Where Hearts Meet';
  static const String continueBtn = 'Continue';
  static const String skip = 'Skip';
  static const String retry = 'Retry';
  static const String cancel = 'Cancel';
  static const String save = 'Save';
  static const String logout = 'Logout';

  // ─── Auth ────────────────────────────────────────────────────────
  static const String loginTitle = 'Welcome to Nenjam Matrimony';
  static const String loginSubtitle = 'Enter your mobile number to continue.';
  static const String mobileNumber = 'Mobile Number';
  static const String sendOtp = 'Send OTP';
  static const String verifyOtpTitle = 'Enter Verification Code';
  static const String verifyOtpSubtitle = 'We have sent a 6-digit code.';
  static const String resendOtp = 'Resend OTP Code';

  // ─── Navigation ──────────────────────────────────────────────────
  static const String navHome = 'Home';
  static const String navSearch = 'Search';
  static const String navMatches = 'Matches';
  static const String navChat = 'Chat';
  static const String navProfile = 'Profile';

  // ─── Home ────────────────────────────────────────────────────────
  static const String aiRecommendations = 'AI Match Recommendations';
  static const String recentlyJoined = 'Recently Joined';
  static const String completeProfile = 'Complete Your Profile';

  // ─── Premium ─────────────────────────────────────────────────────
  static const String premiumTitle = 'Upgrade to Luxury Premium';
  static const String unlockMatches = 'Unlock Unlimited Matches';
}
