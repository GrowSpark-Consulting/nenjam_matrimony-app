/**
 * The 30 fake members, defined once, deterministically.
 *
 * Every value here is a real value the application already accepts: enum
 * members come from schema.prisma, and the free-text fields (religion, caste,
 * education, occupation, diet, ...) use the same vocabulary the registration
 * wizard writes. Nothing is invented.
 *
 * Index order is meaningful and stable: person N owns photo `profile_NN.jpg`
 * and identity `seed-fake-user-NN`, so re-running the seeder maps the same
 * photo to the same member every time.
 *
 * The set is shaped to make the Discover/matching filters testable rather than
 * merely populated — see FEED_TEST_NOTES at the bottom.
 */
import type { Gender, MaritalStatus, ThemeMode } from '../../../generated/client';

export interface FakePerson {
  /** 1-based; drives the seed id, email and photo mapping. */
  index: number;
  firstName: string;
  lastName: string;
  gender: Gender;
  /** Age in years; converted to a fixed DOB at seed time. */
  age: number;
  maritalStatus: MaritalStatus;
  religion: string;
  caste: string;
  community: string | null;
  motherTongue: string;
  languagesKnown: string[];
  heightCm: number;
  annualIncomeLakhs: number;
  highestEducation: string;
  profession: string;
  employerName: string;
  currentCity: string;
  currentState: string;
  country: string;
  bio: string;
  dietaryHabits: string;
  smokingHabits: string;
  drinkingHabits: string;
  hobbies: string[];
  physicalStatus: string;
  familyType: string;
  familyValues: string;
  theme: ThemeMode;
  pushNotificationsEnabled: boolean;
  language: string;
  /** Partner preference for this member. */
  pref: {
    minAge: number;
    maxAge: number;
    minHeightCm: number;
    maxHeightCm: number;
    preferredReligions: string[];
    preferredCastes: string[];
    minIncomeLakhs: number | null;
    preferredCities: string[];
    preferredStates: string[];
    preferredEducation: string[];
    preferredOccupations: string[];
    preferredMotherTongues: string[];
    maritalStatusPref: string[];
  };
}

const VEG = 'Vegetarian';
const NON_VEG = 'Non-Vegetarian';
const EGGETARIAN = 'Eggetarian';
const NEVER = 'Never';
const OCCASIONALLY = 'Occasionally';

export const FAKE_PEOPLE: FakePerson[] = [
  {
    index: 1, firstName: 'Aarthi', lastName: 'Subramanian', gender: 'FEMALE', age: 27,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Iyer', community: 'Brahmin',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 162,
    annualIncomeLakhs: 12, highestEducation: 'B.E', profession: 'Software Engineer',
    employerName: 'Zoho', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Software engineer in Chennai. I read more than I sleep, cook enthusiastically if not well, and most Sundays end at Besant Nagar beach.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Reading', 'Cooking', 'Music'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 27, maxAge: 34, minHeightCm: 168, maxHeightCm: 190,
      preferredReligions: ['Hindu'], preferredCastes: ['Iyer'], minIncomeLakhs: 12,
      preferredCities: ['Chennai', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['B.E'], preferredOccupations: ['Software Engineer'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 2, firstName: 'Divya', lastName: 'Krishnan', gender: 'FEMALE', age: 26,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Iyengar', community: 'Brahmin',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 158,
    annualIncomeLakhs: 9, highestEducation: 'M.Sc', profession: 'Research Associate',
    employerName: 'IIT Madras', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Research associate at IIT Madras working on materials science. Carnatic music since I was six, badly out of practice now.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Music', 'Reading', 'Trekking'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Traditional', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 26, maxAge: 32, minHeightCm: 165, maxHeightCm: 185,
      preferredReligions: ['Hindu'], preferredCastes: ['Iyengar'], minIncomeLakhs: 8,
      preferredCities: ['Chennai', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['M.Sc'], preferredOccupations: ['Research Associate'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 3, firstName: 'Meenakshi', lastName: 'Raghavan', gender: 'FEMALE', age: 29,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Mudaliar', community: 'Vellalar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 165,
    annualIncomeLakhs: 18, highestEducation: 'MBBS, MD', profession: 'Paediatrician',
    employerName: 'Apollo Hospitals', currentCity: 'Madurai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Paediatrician in Madurai. Long days, but the children make it worth it. I paint when the hospital lets me.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Painting', 'Travel', 'Cycling'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Moderate', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 29, maxAge: 36, minHeightCm: 170, maxHeightCm: 190,
      preferredReligions: ['Hindu'], preferredCastes: ['Mudaliar'], minIncomeLakhs: 15,
      preferredCities: ['Madurai', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['MBBS, MD'], preferredOccupations: ['Paediatrician'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 4, firstName: 'Lakshmi', lastName: 'Natarajan', gender: 'FEMALE', age: 25,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Gounder', community: 'Kongu Vellalar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 160,
    annualIncomeLakhs: 7, highestEducation: 'B.Com', profession: 'Chartered Accountant',
    employerName: 'Deloitte', currentCity: 'Coimbatore', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Chartered accountant in Coimbatore, two years qualified. Weekend baker, reluctant runner, permanent tea drinker.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Baking', 'Running', 'Photography'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 25, maxAge: 31, minHeightCm: 165, maxHeightCm: 185,
      preferredReligions: ['Hindu'], preferredCastes: ['Gounder'], minIncomeLakhs: 8,
      preferredCities: ['Coimbatore', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['B.Com'], preferredOccupations: ['Chartered Accountant'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 5, firstName: 'Priyadarshini', lastName: 'Selvam', gender: 'FEMALE', age: 28,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Chettiar', community: 'Nagarathar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 167,
    annualIncomeLakhs: 14, highestEducation: 'B.Arch', profession: 'Architect',
    employerName: 'CCBA Designs', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Architect in Chennai, mostly residential work. I sketch buildings on holiday, which my friends find insufferable.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Sketching', 'Travel', 'Cinema'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Liberal', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 28, maxAge: 35, minHeightCm: 172, maxHeightCm: 192,
      preferredReligions: ['Hindu'], preferredCastes: ['Chettiar'], minIncomeLakhs: 12,
      preferredCities: ['Chennai', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['B.Arch'], preferredOccupations: ['Architect'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 6, firstName: 'Janani', lastName: 'Muthukumar', gender: 'FEMALE', age: 26,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Nadar', community: 'Nadar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 155,
    annualIncomeLakhs: 10, highestEducation: 'M.A English', profession: 'Assistant Professor',
    employerName: 'Madras Christian College', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'I teach English literature and defend the Oxford comma. Weekends are for secondhand bookshops.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Reading', 'Writing', 'Theatre'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 26, maxAge: 33, minHeightCm: 163, maxHeightCm: 183,
      preferredReligions: ['Hindu'], preferredCastes: ['Nadar'], minIncomeLakhs: 8,
      preferredCities: ['Chennai', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['M.A English'], preferredOccupations: ['Assistant Professor'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 7, firstName: 'Kavipriya', lastName: 'Anandan', gender: 'FEMALE', age: 30,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Thevar', community: 'Mukkulathor',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 163,
    annualIncomeLakhs: 22, highestEducation: 'MBA', profession: 'Product Manager',
    employerName: 'Freshworks', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Product manager at Freshworks. I run half marathons slowly and make filter coffee properly, which matters more.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Running', 'Coffee', 'Podcasts'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Liberal', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 30, maxAge: 37, minHeightCm: 170, maxHeightCm: 190,
      preferredReligions: ['Hindu'], preferredCastes: ['Thevar'], minIncomeLakhs: 20,
      preferredCities: ['Chennai', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['MBA'], preferredOccupations: ['Product Manager'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 8, firstName: 'Nandhini', lastName: 'Palanisamy', gender: 'FEMALE', age: 24,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Gounder', community: 'Kongu Vellalar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 157,
    annualIncomeLakhs: 6, highestEducation: 'B.Sc Nursing', profession: 'Staff Nurse',
    employerName: 'PSG Hospitals', currentCity: 'Coimbatore', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Staff nurse at PSG. I garden on my days off, mostly chillies and curry leaves, nothing ambitious.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Gardening', 'Music', 'Cooking'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 24, maxAge: 30, minHeightCm: 162, maxHeightCm: 182,
      preferredReligions: ['Hindu'], preferredCastes: ['Gounder'], minIncomeLakhs: 6,
      preferredCities: ['Coimbatore', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['B.Sc Nursing'], preferredOccupations: ['Staff Nurse'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 9, firstName: 'Sowmya', lastName: 'Venkatesh', gender: 'FEMALE', age: 27,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Iyer', community: 'Brahmin',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 161,
    annualIncomeLakhs: 13, highestEducation: 'M.Tech', profession: 'Data Scientist',
    employerName: 'Tiger Analytics', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Data scientist in Chennai. I play veena, badly and only for myself, and I am learning to swim at twenty-seven.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Veena', 'Swimming', 'Reading'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 27, maxAge: 34, minHeightCm: 167, maxHeightCm: 187,
      preferredReligions: ['Hindu'], preferredCastes: ['Iyer'], minIncomeLakhs: 12,
      preferredCities: ['Chennai', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['M.Tech'], preferredOccupations: ['Data Scientist'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 10, firstName: 'Bhavani', lastName: 'Ramalingam', gender: 'FEMALE', age: 31,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Pillai', community: 'Vellalar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 164,
    annualIncomeLakhs: 16, highestEducation: 'LLB', profession: 'Advocate',
    employerName: 'Madras High Court', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Advocate practising at the Madras High Court, civil side. I argue for a living and garden to stop arguing.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Gardening', 'Reading', 'Debate'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Moderate', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 31, maxAge: 38, minHeightCm: 170, maxHeightCm: 190,
      preferredReligions: ['Hindu'], preferredCastes: ['Pillai'], minIncomeLakhs: 14,
      preferredCities: ['Chennai', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['LLB'], preferredOccupations: ['Advocate'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 11, firstName: 'Deepika', lastName: 'Sundaram', gender: 'FEMALE', age: 25,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Chettiar', community: 'Nagarathar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 159,
    annualIncomeLakhs: 8, highestEducation: 'B.Des', profession: 'Graphic Designer',
    employerName: 'Freelance', currentCity: 'Tiruchirappalli', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Freelance graphic designer in Trichy. I letter by hand, drink too much filter coffee, and adopt too many cats.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Illustration', 'Cinema', 'Music'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Liberal', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 25, maxAge: 32, minHeightCm: 165, maxHeightCm: 185,
      preferredReligions: ['Hindu'], preferredCastes: ['Chettiar'], minIncomeLakhs: 7,
      preferredCities: ['Tiruchirappalli', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['B.Des'], preferredOccupations: ['Graphic Designer'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 12, firstName: 'Yamuna', lastName: 'Balakrishnan', gender: 'FEMALE', age: 28,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Mudaliar', community: 'Vellalar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 162,
    annualIncomeLakhs: 11, highestEducation: 'M.Com', profession: 'Finance Analyst',
    employerName: 'TVS Group', currentCity: 'Madurai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Finance analyst with the TVS group in Madurai. Bharatanatyam since childhood, still performing when the season allows.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Bharatanatyam', 'Reading', 'Travel'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 28, maxAge: 35, minHeightCm: 168, maxHeightCm: 188,
      preferredReligions: ['Hindu'], preferredCastes: ['Mudaliar'], minIncomeLakhs: 10,
      preferredCities: ['Madurai', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['M.Com'], preferredOccupations: ['Finance Analyst'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 13, firstName: 'Anitha', lastName: 'Rajendran', gender: 'FEMALE', age: 26,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Nadar', community: 'Nadar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 156,
    annualIncomeLakhs: 9, highestEducation: 'B.E', profession: 'Civil Engineer',
    employerName: 'Larsen and Toubro', currentCity: 'Salem', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Civil engineer currently on a bridge project near Salem. Hard hat by day, filter coffee and novels by night.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Reading', 'Trekking', 'Music'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 26, maxAge: 33, minHeightCm: 164, maxHeightCm: 184,
      preferredReligions: ['Hindu'], preferredCastes: ['Nadar'], minIncomeLakhs: 8,
      preferredCities: ['Salem', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['B.E'], preferredOccupations: ['Civil Engineer'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 14, firstName: 'Revathi', lastName: 'Chandrasekar', gender: 'FEMALE', age: 29,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Iyengar', community: 'Brahmin',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 166,
    annualIncomeLakhs: 20, highestEducation: 'MBA', profession: 'Marketing Manager',
    employerName: 'Ashok Leyland', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Marketing manager at Ashok Leyland. I collect Tamil pulp fiction and can recite most of Thiruvasagam badly.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Reading', 'Music', 'Travel'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 29, maxAge: 36, minHeightCm: 172, maxHeightCm: 192,
      preferredReligions: ['Hindu'], preferredCastes: ['Iyengar'], minIncomeLakhs: 18,
      preferredCities: ['Chennai', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['MBA'], preferredOccupations: ['Marketing Manager'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 15, firstName: 'Gayathri', lastName: 'Manickam', gender: 'FEMALE', age: 27,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Thevar', community: 'Mukkulathor',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 160,
    annualIncomeLakhs: 10, highestEducation: 'B.Ed', profession: 'School Teacher',
    employerName: 'Kendriya Vidyalaya', currentCity: 'Tirunelveli', currentState: 'Tamil Nadu', country: 'India',
    bio: 'I teach maths to eleven-year-olds in Tirunelveli, which is harder than it sounds. Weekends belong to my bicycle.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Cycling', 'Cooking', 'Music'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 27, maxAge: 34, minHeightCm: 166, maxHeightCm: 186,
      preferredReligions: ['Hindu'], preferredCastes: ['Thevar'], minIncomeLakhs: 8,
      preferredCities: ['Tirunelveli', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['B.Ed'], preferredOccupations: ['School Teacher'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
];
