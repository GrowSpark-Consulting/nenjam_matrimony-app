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
  String get homeSeeAllButton => 'See All';

  @override
  String get homeAiRecommendationsTitle => 'AI Match Recommendations';

  @override
  String get homeRecentlyJoinedTitle => 'Recently Joined';

  @override
  String get homeCompleteProfileTitle => 'Complete Your Profile';

  @override
  String homeProfileNextStep(String step) {
    return 'Next: $step';
  }

  @override
  String get homeStepUploadHoroscope => 'Upload Horoscope';

  @override
  String get homeStepAddPhoto => 'Add profile photo';

  @override
  String get homeAiPickBadge => 'AI Pick';

  @override
  String get homeAiMatchLabel => 'match';

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
  String get chatTitle => 'Conversations';

  @override
  String get notificationsTitle => 'Notifications';

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
  String registrationStepIndicator(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get registrationSaveExit => 'Save & Exit';

  @override
  String registrationPercentCompleted(int percent) {
    return '$percent% Completed';
  }

  @override
  String get registrationBack => 'Back';

  @override
  String get registrationFinishLogin => 'Finish & Login';

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
  String get registrationCasteLabel => 'Caste';

  @override
  String get registrationCasteHint => 'e.g., Iyer, Iyengar, Mudaliar';

  @override
  String get registrationSubCasteLabel => 'Sub Caste (Optional)';

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
  String get registrationAreaLabel => 'Area (Optional)';

  @override
  String get registrationAreaHint => 'e.g., T. Nagar';

  @override
  String get registrationPinLabel => 'PIN Code (Optional)';

  @override
  String get registrationPinHint => '600017';

  @override
  String get registrationNativePlaceLabel => 'Native Place (Optional)';

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
  String get registrationCollegeLabel => 'College / University (Optional)';

  @override
  String get registrationCollegeHint => 'e.g., IIT Madras';

  @override
  String get registrationOccupationLabel => 'Occupation';

  @override
  String get registrationCompanyLabel => 'Company (Optional)';

  @override
  String get registrationCompanyHint => 'e.g., Google';

  @override
  String get registrationEmploymentTypeLabel => 'Employment Type';

  @override
  String get registrationAnnualIncomeLabel => 'Annual Income';

  @override
  String get registrationWorkLocationLabel => 'Work Location (Optional)';

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
  String get incomePreferNotSay => 'Prefer not to say';

  @override
  String get registrationPhysicalTitle => 'Physical Details';

  @override
  String get registrationPhysicalSubtitle => 'Describe your appearance';

  @override
  String get registrationHeightLabel => 'Height';

  @override
  String get registrationWeightLabel => 'Weight';

  @override
  String get registrationBodyTypeLabel => 'Body Type';

  @override
  String get registrationComplexionLabel => 'Complexion';

  @override
  String get registrationBloodGroupLabel => 'Blood Group';

  @override
  String get registrationDisabilityLabel => 'Disability';

  @override
  String get bodySlim => 'Slim';

  @override
  String get bodyAverage => 'Average';

  @override
  String get bodyAthletic => 'Athletic';

  @override
  String get bodyHeavy => 'Heavy';

  @override
  String get complexionVeryFair => 'Very Fair';

  @override
  String get complexionFair => 'Fair';

  @override
  String get complexionWheatish => 'Wheatish';

  @override
  String get complexionDark => 'Dark';

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
  String get registrationFamilyTitle => 'Family Details';

  @override
  String get registrationFamilySubtitle => 'Tell us about your family';

  @override
  String get registrationFatherNameLabel => 'Father\'s Name (Optional)';

  @override
  String get registrationFatherNameHint => 'Enter father\'s name';

  @override
  String get registrationFatherOccLabel => 'Father\'s Occupation (Optional)';

  @override
  String get registrationFatherOccHint => 'e.g., Retired Government Officer';

  @override
  String get registrationMotherNameLabel => 'Mother\'s Name (Optional)';

  @override
  String get registrationMotherNameHint => 'Enter mother\'s name';

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
  String get registrationBrothersLabel => 'No. of Brothers';

  @override
  String get registrationSistersLabel => 'No. of Sisters';

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
  String get registrationPrivacyTitle => '100% Privacy Guaranteed';

  @override
  String get registrationPrivacySubtitle =>
      'Your identity documents are encrypted and never shown publicly to any user.';

  @override
  String get registrationVerifyButton => 'Verify';

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
}
