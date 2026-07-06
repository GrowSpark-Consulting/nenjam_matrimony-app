/// Nenjam Matrimony — Asset Path Constants
///
/// Centralized paths for all app assets. Every asset reference
/// in the app must use these constants.
abstract final class AssetPaths {
  // ─── Base Paths ──────────────────────────────────────────────────
  static const String _icons = 'assets/icons';
  static const String _images = 'assets/images';
  static const String _svg = 'assets/svg';
  static const String _animations = 'assets/animations';
  static const String _lottie = 'assets/lottie';
  static const String _illustrations = 'assets/illustrations';

  // ─── Icons ───────────────────────────────────────────────────────
  static const String iconLogo = '$_icons/logo.png';
  static const String iconLogoSmall = '$_icons/logo_small.png';
  static const String iconGoogle = '$_icons/google.png';
  static const String iconApple = '$_icons/apple.png';
  static const String iconFacebook = '$_icons/facebook.png';

  // ─── SVG Icons ───────────────────────────────────────────────────
  static const String svgLogo = '$_svg/logo.svg';
  static const String svgHeart = '$_svg/heart.svg';
  static const String svgMatch = '$_svg/match.svg';
  static const String svgPremium = '$_svg/premium.svg';
  static const String svgVerified = '$_svg/verified.svg';
  static const String svgChat = '$_svg/chat.svg';
  static const String svgSearch = '$_svg/search.svg';
  static const String svgFilter = '$_svg/filter.svg';
  static const String svgNotification = '$_svg/notification.svg';
  static const String svgSettings = '$_svg/settings.svg';
  static const String svgProfile = '$_svg/profile.svg';
  static const String svgCamera = '$_svg/camera.svg';
  static const String svgGallery = '$_svg/gallery.svg';
  static const String svgHoroscope = '$_svg/horoscope.svg';

  // ─── Images ──────────────────────────────────────────────────────
  static const String imgPlaceholder = '$_images/placeholder.png';
  static const String imgAvatar = '$_images/avatar.png';
  static const String imgOnboarding1 = '$_images/onboarding_1.png';
  static const String imgOnboarding2 = '$_images/onboarding_2.png';
  static const String imgOnboarding3 = '$_images/onboarding_3.png';
  static const String imgSplashBg = '$_images/splash_bg.png';
  static const String imgPremiumBg = '$_images/premium_bg.png';

  // ─── Illustrations ───────────────────────────────────────────────
  static const String illEmpty = '$_illustrations/empty.png';
  static const String illError = '$_illustrations/error.png';
  static const String illNoConnection = '$_illustrations/no_connection.png';
  static const String illSuccess = '$_illustrations/success.png';
  static const String illWelcome = '$_illustrations/welcome.png';
  static const String illMatch = '$_illustrations/match.png';

  // ─── Lottie Animations ───────────────────────────────────────────
  static const String lottieLoading = '$_lottie/loading.json';
  static const String lottieSuccess = '$_lottie/success.json';
  static const String lottieHeart = '$_lottie/heart.json';
  static const String lottieMatch = '$_lottie/match.json';
  static const String lottiePremium = '$_lottie/premium.json';
  static const String lottieConfetti = '$_lottie/confetti.json';

  // ─── Animations ──────────────────────────────────────────────────
  static const String animSplash = '$_animations/splash.json';
}
