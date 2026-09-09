/// Nenjam Matrimony — Shared Profile Option Lists
///
/// The option lists behind the matrimony selectors. These are *values*, not
/// display text: they are persisted verbatim on the profile draft and sent
/// to the backend as-is, so screens localize them for display (see the
/// `*Label` helpers next to each call site) and never translate them here.
///
/// They live in one place because the same list is offered by more than one
/// screen — the registration wizard's Location step and the onboarding
/// Location & Sub-community step both offer states, and both
/// [NmLocationSelector] and the onboarding step offer cities. Before this,
/// every screen carried its own copy and they had already drifted.
abstract final class ProfileOptions {
  /// Indian states, in the order the wizard has always listed them.
  ///
  /// Deliberately without an "Other" entry: a screen that pairs the list
  /// with a free-text field (the wizard's [OtherOptionField]) appends its
  /// own, while a plain dropdown must not offer a choice that would persist
  /// the literal string "Other" as somebody's home state.
  static const List<String> states = [
    'Tamil Nadu',
    'Karnataka',
    'Kerala',
    'Andhra Pradesh',
    'Telangana',
    'Maharashtra',
    'Delhi',
    'Gujarat',
    'West Bengal',
    'Rajasthan',
    'UP',
  ];

  /// Countries — the onboarding step's "Living in", and the wizard's
  /// Country field. Same "no Other entry" rule as [states].
  static const List<String> countries = [
    'India',
    'United States',
    'United Kingdom',
    'Singapore',
    'UAE',
    'Malaysia',
    'Australia',
    'Canada',
  ];

  /// The states/provinces offered for a given country.
  ///
  /// Same reasoning as [communitiesFor] and [citiesFor]: no backend lookup
  /// exists, so the scoping lives here, in one place. A country with no entry
  /// falls back to [states] rather than an empty dropdown — a member abroad
  /// must never be blocked because our table stops at the countries we know.
  ///
  /// India's list is [states] verbatim: it is what the wizard has always
  /// offered and what every stored profile was chosen from.
  static const Map<String, List<String>> _statesByCountry = {
    'India': states,
    'United States': [
      'California',
      'New Jersey',
      'New York',
      'Texas',
      'Illinois',
      'Washington',
      'Georgia',
      'Massachusetts',
    ],
    'United Kingdom': ['England', 'Scotland', 'Wales', 'Northern Ireland'],
    'Singapore': ['Singapore'],
    'UAE': ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman'],
    'Malaysia': ['Kuala Lumpur', 'Selangor', 'Penang', 'Johor'],
    'Australia': [
      'New South Wales',
      'Victoria',
      'Queensland',
      'Western Australia',
      'South Australia',
    ],
    'Canada': ['Ontario', 'British Columbia', 'Alberta', 'Quebec'],
  };

  /// States/provinces for [country], or India's list when the country is
  /// unknown or not yet chosen.
  static List<String> statesFor(String country) =>
      _statesByCountry[country.trim()] ?? states;

  /// Whether [state] is offered for [country] — the test the Location step's
  /// cascade uses to decide whether a stored state survives a country change.
  /// An empty value is "not yet answered", never "invalid".
  static bool isStateInCountry(String country, String state) =>
      state.trim().isEmpty || statesFor(country).contains(state.trim());

  /// Whether [city] is offered for [state].
  static bool isCityInState(String state, String city) =>
      city.trim().isEmpty || citiesFor(state).contains(city.trim());

  /// Whether [community] is offered for [religion].
  static bool isCommunityInReligion(String religion, String community) =>
      community.trim().isEmpty ||
      communitiesFor(religion).contains(community.trim());

  /// "Industry" — the sector a member works in, asked between "You work with"
  /// and "You work as".
  ///
  /// Promoted from the private `_industryOptions` that lived inside
  /// partner_preferences_page.dart, so the sector a member states about
  /// themselves and the sector they filter partners by come from one list
  /// rather than two that can drift. Every value that page offered is still
  /// here, so no stored preference is orphaned.
  static const List<String> industries = [
    'IT / Software',
    'Healthcare',
    'Finance',
    'Government',
    'Education',
    'Business / Self-Employed',
    'Engineering / Manufacturing',
    'Legal',
    'Media / Creative',
    'Hospitality',
  ];

  /// Religions, in the order every screen has always listed them.
  static const List<String> religions = [
    'Hindu',
    'Christian',
    'Muslim',
    'Jain',
    'Sikh',
    'Buddhist',
    'Inter-Religion',
  ];

  /// The communities offered for a given religion.
  ///
  /// The backend has no lookup endpoint for this pairing, so the scoping is
  /// held here rather than fetched — one place to widen it, or to swap for
  /// an API call, without touching a screen. A religion with no entry (or
  /// none chosen yet) gets the full list rather than an empty dropdown: a
  /// member must never be blocked because our table is incomplete.
  static const Map<String, List<String>> _communitiesByReligion = {
    'Hindu': [
      'Vellalar',
      'Nadar',
      'Chettiar',
      'Mudaliar',
      'Iyer',
      'Iyengar',
      'Naidu',
      'Reddy',
      'Tamil',
      'Telugu',
      'Malayalam',
      'Kannada',
    ],
    'Muslim': ['Urdu', 'Tamil', 'Malayalam', 'Rowther', 'Lebbai', 'Marakayar'],
    'Christian': ['Tamil', 'Malayalam', 'Telugu', 'Roman Catholic', 'Protestant'],
    'Jain': ['Digambar', 'Shwetambar', 'Gujarati', 'Marwari'],
    'Sikh': ['Jat', 'Khatri', 'Ramgarhia', 'Punjabi'],
    'Buddhist': ['Tamil', 'Marathi', 'Other'],
  };

  /// Communities for [religion], or the full union when the religion is
  /// unknown or not yet chosen.
  static List<String> communitiesFor(String religion) =>
      _communitiesByReligion[religion.trim()] ?? communities;

  /// Every community the app knows, in a stable order — the fallback for
  /// [communitiesFor] and the list Edit Profile offers.
  static final List<String> communities = <String>{
    for (final entry in _communitiesByReligion.values) ...entry,
  }.toList();

  /// The cities offered for a given state. Same reasoning as
  /// [communitiesFor]: no backend lookup exists, so an unknown state gets
  /// the full list rather than an empty dropdown.
  static const Map<String, List<String>> _citiesByState = {
    'Tamil Nadu': [
      'Chennai',
      'Coimbatore',
      'Madurai',
      'Trichy',
      'Salem',
      'Erode',
      'Tirunelveli',
    ],
    'Karnataka': ['Bangalore', 'Mysore', 'Mangalore', 'Hubli'],
    'Kerala': ['Kochi', 'Thiruvananthapuram', 'Kozhikode', 'Thrissur'],
    'Andhra Pradesh': ['Visakhapatnam', 'Vijayawada', 'Guntur', 'Tirupati'],
    'Telangana': ['Hyderabad', 'Warangal', 'Nizamabad'],
    'Maharashtra': ['Mumbai', 'Pune', 'Nagpur', 'Nashik'],
    'Delhi': ['New Delhi', 'Delhi'],
    'Gujarat': ['Ahmedabad', 'Surat', 'Vadodara', 'Rajkot'],
    'West Bengal': ['Kolkata', 'Howrah', 'Siliguri'],
    'Rajasthan': ['Jaipur', 'Jodhpur', 'Udaipur', 'Kota'],
    'UP': ['Lucknow', 'Kanpur', 'Noida', 'Varanasi', 'Agra'],
  };

  /// Cities for [state], or the full list when the state is unknown or not
  /// yet chosen.
  static List<String> citiesFor(String state) =>
      _citiesByState[state.trim()] ?? cities;

  /// Cities offered to a member choosing where they live. Ends with a
  /// catch-all for members abroad, which is a real answer rather than an
  /// "Other" placeholder.
  static const List<String> cities = [
    'Chennai',
    'Coimbatore',
    'Madurai',
    'Trichy',
    'Bangalore',
    'Hyderabad',
    'Mumbai',
    'Singapore',
    'USA / UK / Abroad',
  ];

  /// Heights, in the exact `5'9" (175 cm)` form the wizard's Physical step
  /// stores — generated from the same 122–213 cm range so a value chosen in
  /// onboarding and one chosen in Edit Profile are the same string.
  static final List<String> heights = [
    for (var cm = _minHeightCm; cm <= _maxHeightCm; cm++) heightLabel(cm),
  ];

  static const int _minHeightCm = 122;
  static const int _maxHeightCm = 213;

  /// The wizard's own formatting, lifted verbatim so the two agree.
  static String heightLabel(int cm) {
    final totalInches = (cm / 2.54).round();
    return '${totalInches ~/ 12}\'${totalInches % 12}" ($cm cm)';
  }

  /// Diets — the wizard's Lifestyle step calls this "eating habit".
  static const List<String> diets = [
    'Vegetarian',
    'Non-Vegetarian',
    'Eggetarian',
    'Vegan',
    'Jain',
  ];

  /// Marital statuses, matching the wizard's Basic Info step exactly.
  static const List<String> maritalStatuses = [
    'Never Married',
    'Divorced',
    'Widowed',
    'Awaiting Divorce',
  ];

  /// Highest qualifications, matching the wizard's Education step.
  static const List<String> qualifications = [
    'B.E / B.Tech',
    'M.Tech / M.E',
    'MBBS / MD',
    'MBA / PGDM',
    'B.Sc / M.Sc',
    'CA / CFA',
    'B.Com / M.Com',
    'Ph.D',
    'Diploma',
  ];

  /// "You work as" — occupations, matching the wizard's Education step.
  static const List<String> occupations = [
    'Software Engineer',
    'Doctor',
    'IAS / IPS / Govt',
    'Business Owner',
    'Finance / Banking',
    'Civil / Mechanical Engg',
    'Teacher / Professor',
    'Lawyer',
    'Architect',
  ];

  /// "You work with" — employment types.
  ///
  /// `Business` and `Self-Employed` stay two entries rather than the single
  /// "Business / Self-employed" the spec sketched: both strings are already
  /// stored on live profiles, and collapsing them would orphan every member
  /// holding one (the dropdown blanks a value it cannot offer — see
  /// `OnboardingScaffold.optionsWith` for the data loss that causes).
  /// `Retired` was genuinely missing and is added.
  ///
  /// No literal "Other" entry here. The step wraps this list in
  /// [OtherOptionField], which appends its own escape and persists the text
  /// the member types — never the placeholder string, which the backend's
  /// `has()` treats as an unanswered field.
  static const List<String> employmentTypes = [
    'Private',
    'Government',
    'Business',
    'Self-Employed',
    'Not Working',
    'Student',
    'Retired',
  ];

  /// Annual income bands, matching the wizard's Education step.
  static const List<String> incomeRanges = [
    'Below 5 Lakhs',
    '5 - 10 Lakhs',
    '10 - 20 Lakhs',
    '20 - 50 Lakhs',
    '50 Lakhs - 1 Crore',
    '1 Crore+',
  ];

  /// Sub-communities (the caste/division taxonomy). "Don't Wish to Specify"
  /// is a deliberate answer, not a missing one — a member who picks it has
  /// answered the question.
  static const List<String> subCommunities = [
    'Iyer',
    'Iyengar',
    'Mudaliar',
    'Pillai',
    'Chettiar',
    'Gounder',
    'Nadar',
    'Vanniyar',
    "Don't Wish to Specify",
  ];
}
