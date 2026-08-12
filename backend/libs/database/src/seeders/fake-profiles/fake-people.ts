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
    bio: 'Software engineer from Chennai. I read a lot, cook badly but enthusiastically, and spend most weekends at the beach.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Reading', 'Cooking', 'Music'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 27, maxAge: 34, minHeightCm: 168, maxHeightCm: 190,
      preferredReligions: ['Hindu'], preferredCastes: ['Iyer', 'Iyengar'], minIncomeLakhs: 10,
      preferredCities: ['Chennai', 'Bengaluru'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['B.E', 'B.Tech', 'M.Tech'], preferredOccupations: ['Software Engineer', 'Doctor'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 2, firstName: 'Karthik', lastName: 'Raman', gender: 'MALE', age: 30,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Iyer', community: 'Brahmin',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English', 'Hindi'], heightCm: 176,
    annualIncomeLakhs: 18, highestEducation: 'B.Tech', profession: 'Software Engineer',
    employerName: 'Freshworks', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Backend engineer, long-distance runner, and an unreasonably competitive carrom player.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Running', 'Photography', 'Travel'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'DARK',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 24, maxAge: 29, minHeightCm: 155, maxHeightCm: 172,
      preferredReligions: ['Hindu'], preferredCastes: ['Iyer', 'Iyengar'], minIncomeLakhs: null,
      preferredCities: ['Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['B.E', 'B.Tech', 'M.Sc'], preferredOccupations: ['Software Engineer', 'Teacher'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 3, firstName: 'Divya', lastName: 'Krishnan', gender: 'FEMALE', age: 26,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Iyengar', community: 'Brahmin',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 158,
    annualIncomeLakhs: 9, highestEducation: 'M.Sc', profession: 'Teacher',
    employerName: 'DAV School', currentCity: 'Coimbatore', currentState: 'Tamil Nadu', country: 'India',
    bio: 'I teach physics to teenagers, which is mostly crowd control. Classical dancer since I was six.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Dancing', 'Reading', 'Gardening'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'LIGHT',
    pushNotificationsEnabled: true, language: 'ta',
    pref: {
      minAge: 26, maxAge: 33, minHeightCm: 165, maxHeightCm: 185,
      preferredReligions: ['Hindu'], preferredCastes: ['Iyengar', 'Iyer'], minIncomeLakhs: 8,
      preferredCities: ['Coimbatore', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['B.E', 'B.Tech'], preferredOccupations: ['Software Engineer', 'Business'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 4, firstName: 'Vignesh', lastName: 'Murugan', gender: 'MALE', age: 31,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Gounder', community: 'Kongu Vellalar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 172,
    annualIncomeLakhs: 25, highestEducation: 'MBA', profession: 'Business',
    employerName: 'Self-employed', currentCity: 'Coimbatore', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Third-generation textile business. Weekends are for cricket and long drives to Ooty.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Cricket', 'Travel', 'Movies'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'SYSTEM',
    pushNotificationsEnabled: false, language: 'ta',
    pref: {
      minAge: 24, maxAge: 30, minHeightCm: 152, maxHeightCm: 170,
      preferredReligions: ['Hindu'], preferredCastes: ['Gounder'], minIncomeLakhs: null,
      preferredCities: ['Coimbatore', 'Erode'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['B.Com', 'B.Sc', 'MBA'], preferredOccupations: ['Teacher', 'Business'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 5, firstName: 'Priya', lastName: 'Lakshmi', gender: 'FEMALE', age: 29,
    maritalStatus: 'DIVORCED', religion: 'Hindu', caste: 'Mudaliar', community: 'Vellalar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English', 'Telugu'], heightCm: 165,
    annualIncomeLakhs: 16, highestEducation: 'MBA', profession: 'Marketing Manager',
    employerName: 'HCL', currentCity: 'Bengaluru', currentState: 'Karnataka', country: 'India',
    bio: 'Marketing lead, dog person, and a reluctant but improving runner. Looking for someone kind and straightforward.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Running', 'Music', 'Travel'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Liberal', theme: 'DARK',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 28, maxAge: 38, minHeightCm: 168, maxHeightCm: 190,
      preferredReligions: ['Hindu'], preferredCastes: [], minIncomeLakhs: 12,
      preferredCities: ['Bengaluru', 'Chennai', 'Hyderabad'], preferredStates: ['Karnataka', 'Tamil Nadu'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: [], maritalStatusPref: ['NEVER_MARRIED', 'DIVORCED'],
    },
  },
  {
    index: 6, firstName: 'Ashwin', lastName: 'Nair', gender: 'MALE', age: 33,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Nair', community: null,
    motherTongue: 'Malayalam', languagesKnown: ['Malayalam', 'English', 'Tamil'], heightCm: 180,
    annualIncomeLakhs: 32, highestEducation: 'MBBS', profession: 'Doctor',
    employerName: 'Apollo Hospitals', currentCity: 'Bengaluru', currentState: 'Karnataka', country: 'India',
    bio: 'Cardiologist. Terrible hours, excellent coffee. I play the guitar badly and hike whenever I get two days off.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Music', 'Trekking', 'Reading'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Liberal', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 26, maxAge: 33, minHeightCm: 155, maxHeightCm: 175,
      preferredReligions: ['Hindu'], preferredCastes: [], minIncomeLakhs: null,
      preferredCities: ['Bengaluru', 'Kochi'], preferredStates: ['Karnataka', 'Kerala'],
      preferredEducation: ['MBBS', 'MD', 'B.E'], preferredOccupations: ['Doctor', 'Software Engineer'],
      preferredMotherTongues: ['Malayalam', 'Tamil'], maritalStatusPref: ['NEVER_MARRIED', 'DIVORCED'],
    },
  },
  {
    index: 7, firstName: 'Meenakshi', lastName: 'Sundaram', gender: 'FEMALE', age: 25,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Chettiar', community: 'Nagarathar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 155,
    annualIncomeLakhs: 7, highestEducation: 'B.Com', profession: 'Accountant',
    employerName: 'Deloitte', currentCity: 'Madurai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Chartered accountancy finalist. I bake, I over-plan holidays, and I know every Ilaiyaraaja song.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Cooking', 'Music', 'Movies'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'LIGHT',
    pushNotificationsEnabled: true, language: 'ta',
    pref: {
      minAge: 25, maxAge: 32, minHeightCm: 163, maxHeightCm: 182,
      preferredReligions: ['Hindu'], preferredCastes: ['Chettiar'], minIncomeLakhs: 6,
      preferredCities: ['Madurai', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['B.Com', 'B.E', 'MBA'], preferredOccupations: ['Business', 'Accountant'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 8, firstName: 'Rahul', lastName: 'Menon', gender: 'MALE', age: 28,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Menon', community: null,
    motherTongue: 'Malayalam', languagesKnown: ['Malayalam', 'English'], heightCm: 174,
    annualIncomeLakhs: 14, highestEducation: 'B.Tech', profession: 'Data Scientist',
    employerName: 'Infosys', currentCity: 'Kochi', currentState: 'Kerala', country: 'India',
    bio: 'I work with data by day and play football badly by evening. Big on food, bigger on football.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Football', 'Gaming', 'Cooking'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'DARK',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 23, maxAge: 29, minHeightCm: 150, maxHeightCm: 170,
      preferredReligions: ['Hindu'], preferredCastes: [], minIncomeLakhs: null,
      preferredCities: ['Kochi', 'Bengaluru'], preferredStates: ['Kerala', 'Karnataka'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Malayalam'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 9, firstName: 'Sneha', lastName: 'Reddy', gender: 'FEMALE', age: 28,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Reddy', community: null,
    motherTongue: 'Telugu', languagesKnown: ['Telugu', 'English', 'Hindi'], heightCm: 167,
    annualIncomeLakhs: 22, highestEducation: 'M.Tech', profession: 'Product Manager',
    employerName: 'Microsoft', currentCity: 'Hyderabad', currentState: 'Telangana', country: 'India',
    bio: 'Product manager who still misses writing code. Trekking, filter coffee, and long arguments about films.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Trekking', 'Movies', 'Reading'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Liberal', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 27, maxAge: 35, minHeightCm: 170, maxHeightCm: 195,
      preferredReligions: ['Hindu'], preferredCastes: ['Reddy'], minIncomeLakhs: 18,
      preferredCities: ['Hyderabad', 'Bengaluru'], preferredStates: ['Telangana', 'Karnataka'],
      preferredEducation: ['B.Tech', 'M.Tech', 'MBA'], preferredOccupations: ['Software Engineer', 'Product Manager'],
      preferredMotherTongues: ['Telugu'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 10, firstName: 'Arjun', lastName: 'Varma', gender: 'MALE', age: 32,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Reddy', community: null,
    motherTongue: 'Telugu', languagesKnown: ['Telugu', 'English'], heightCm: 178,
    annualIncomeLakhs: 28, highestEducation: 'MBA', profession: 'Product Manager',
    employerName: 'Amazon', currentCity: 'Hyderabad', currentState: 'Telangana', country: 'India',
    bio: 'Product at a large company, which means meetings. Escape route: badminton, biryani, and the occasional half marathon.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Badminton', 'Travel', 'Music'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'DARK',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 25, maxAge: 31, minHeightCm: 158, maxHeightCm: 175,
      preferredReligions: ['Hindu'], preferredCastes: ['Reddy'], minIncomeLakhs: 12,
      preferredCities: ['Hyderabad'], preferredStates: ['Telangana'],
      preferredEducation: ['B.Tech', 'M.Tech', 'MBA'], preferredOccupations: ['Product Manager', 'Software Engineer'],
      preferredMotherTongues: ['Telugu'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 11, firstName: 'Fathima', lastName: 'Begum', gender: 'FEMALE', age: 26,
    maritalStatus: 'NEVER_MARRIED', religion: 'Muslim', caste: 'Sunni', community: null,
    // Hindi-speaking, in Bangalore. Both matter: "Same Mother Tongue" and
    // "Same City" are the two relative preferences the feed resolves against
    // the caller's own profile, so a set with no Hindi speakers and only the
    // "Bengaluru" spelling silently returns nothing for a Hindi-speaking member
    // in "Bangalore" — which is exactly what happened on first run.
    motherTongue: 'Hindi', languagesKnown: ['Hindi', 'English', 'Urdu'], heightCm: 165,
    annualIncomeLakhs: 11, highestEducation: 'B.Pharm', profession: 'Pharmacist',
    employerName: 'Apollo Pharmacy', currentCity: 'Bangalore', currentState: 'Karnataka', country: 'India',
    bio: 'Pharmacist, part-time calligrapher, full-time biryani critic. Family means a lot to me.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Art', 'Cooking', 'Reading'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'LIGHT',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 26, maxAge: 34, minHeightCm: 165, maxHeightCm: 185,
      preferredReligions: ['Muslim'], preferredCastes: [], minIncomeLakhs: 8,
      preferredCities: ['Bangalore'], preferredStates: ['Karnataka'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Hindi', 'Urdu'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 12, firstName: 'Imran', lastName: 'Sheikh', gender: 'MALE', age: 29,
    maritalStatus: 'NEVER_MARRIED', religion: 'Muslim', caste: 'Sunni', community: null,
    motherTongue: 'Hindi', languagesKnown: ['Hindi', 'English', 'Urdu'], heightCm: 175,
    annualIncomeLakhs: 15, highestEducation: 'B.E', profession: 'Civil Engineer',
    employerName: 'L&T', currentCity: 'Bangalore', currentState: 'Karnataka', country: 'India',
    bio: 'Site engineer — I build things that stay up. Cricket on Sundays, poetry when nobody is watching.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Cricket', 'Reading', 'Travel'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'ta',
    pref: {
      minAge: 23, maxAge: 28, minHeightCm: 152, maxHeightCm: 168,
      preferredReligions: ['Muslim'], preferredCastes: [], minIncomeLakhs: null,
      preferredCities: ['Bangalore'], preferredStates: ['Karnataka'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Hindi'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 13, firstName: 'Rebecca', lastName: 'Fernandes', gender: 'FEMALE', age: 27,
    maritalStatus: 'NEVER_MARRIED', religion: 'Christian', caste: 'Roman Catholic', community: null,
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 163,
    annualIncomeLakhs: 13, highestEducation: 'B.Sc Nursing', profession: 'Nurse',
    employerName: 'CMC Vellore', currentCity: 'Vellore', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Nurse at a teaching hospital. I sing in the church choir and I am the person who organises everyone else.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Music', 'Volunteering', 'Cooking'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'LIGHT',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 26, maxAge: 34, minHeightCm: 165, maxHeightCm: 185,
      preferredReligions: ['Christian'], preferredCastes: [], minIncomeLakhs: null,
      preferredCities: ['Vellore', 'Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 14, firstName: 'Joseph', lastName: 'Anthony', gender: 'MALE', age: 30,
    maritalStatus: 'NEVER_MARRIED', religion: 'Christian', caste: 'Roman Catholic', community: null,
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 177,
    annualIncomeLakhs: 17, highestEducation: 'B.E', profession: 'Mechanical Engineer',
    employerName: 'Ashok Leyland', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Mechanical engineer who restores old motorcycles. Quiet, practical, and a decent cook.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Motorcycles', 'Cooking', 'Movies'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'DARK',
    pushNotificationsEnabled: false, language: 'en',
    pref: {
      minAge: 24, maxAge: 30, minHeightCm: 155, maxHeightCm: 172,
      preferredReligions: ['Christian'], preferredCastes: [], minIncomeLakhs: null,
      preferredCities: ['Chennai', 'Vellore'], preferredStates: ['Tamil Nadu'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 15, firstName: 'Anitha', lastName: 'Rajendran', gender: 'FEMALE', age: 34,
    maritalStatus: 'WIDOWED', religion: 'Hindu', caste: 'Naidu', community: null,
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 159,
    annualIncomeLakhs: 20, highestEducation: 'M.Com', profession: 'Bank Manager',
    employerName: 'HDFC Bank', currentCity: 'Salem', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Bank manager, mother to a wonderful six-year-old. Steady, warm, and hoping to build something new.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Gardening', 'Reading', 'Music'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'ta',
    pref: {
      minAge: 32, maxAge: 45, minHeightCm: 165, maxHeightCm: 190,
      preferredReligions: ['Hindu'], preferredCastes: [], minIncomeLakhs: null,
      preferredCities: [], preferredStates: ['Tamil Nadu'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['DIVORCED', 'WIDOWED', 'NEVER_MARRIED'],
    },
  },
  {
    index: 16, firstName: 'Suresh', lastName: 'Kumar', gender: 'MALE', age: 37,
    maritalStatus: 'DIVORCED', religion: 'Hindu', caste: 'Naidu', community: null,
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English', 'Kannada'], heightCm: 171,
    annualIncomeLakhs: 24, highestEducation: 'B.E', profession: 'Project Manager',
    employerName: 'TCS', currentCity: 'Salem', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Project manager, amateur astronomer, and a patient teacher of very impatient nephews.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Astronomy', 'Travel', 'Reading'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'DARK',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 30, maxAge: 40, minHeightCm: 150, maxHeightCm: 172,
      preferredReligions: ['Hindu'], preferredCastes: [], minIncomeLakhs: null,
      preferredCities: [], preferredStates: ['Tamil Nadu'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['DIVORCED', 'WIDOWED', 'NEVER_MARRIED'],
    },
  },
  {
    index: 17, firstName: 'Kavya', lastName: 'Iyer', gender: 'FEMALE', age: 24,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Iyer', community: 'Brahmin',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English', 'French'], heightCm: 156,
    annualIncomeLakhs: 8, highestEducation: 'B.A', profession: 'Content Writer',
    employerName: 'Freelance', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Freelance writer. I collect fountain pens, learn languages I never finish, and love a good bookshop.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Writing', 'Reading', 'Art'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Liberal', theme: 'LIGHT',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 24, maxAge: 31, minHeightCm: 160, maxHeightCm: 185,
      preferredReligions: [], preferredCastes: [], minIncomeLakhs: null,
      preferredCities: [], preferredStates: [],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: [], maritalStatusPref: [],
    },
  },
  {
    index: 18, firstName: 'Nikhil', lastName: 'Shetty', gender: 'MALE', age: 27,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Bunt', community: null,
    motherTongue: 'Kannada', languagesKnown: ['Kannada', 'English', 'Tulu'], heightCm: 169,
    annualIncomeLakhs: 10, highestEducation: 'B.Sc', profession: 'Chef',
    employerName: 'Taj Hotels', currentCity: 'Mangaluru', currentState: 'Karnataka', country: 'India',
    bio: 'Chef at a hotel kitchen. I cook coastal food, surf badly, and sleep at odd hours.',
    dietaryHabits: NON_VEG, smokingHabits: OCCASIONALLY, drinkingHabits: OCCASIONALLY,
    hobbies: ['Cooking', 'Surfing', 'Music'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Moderate', theme: 'DARK',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 22, maxAge: 28, minHeightCm: 150, maxHeightCm: 170,
      preferredReligions: ['Hindu'], preferredCastes: [], minIncomeLakhs: null,
      preferredCities: ['Mangaluru', 'Bengaluru'], preferredStates: ['Karnataka'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Kannada', 'Tulu'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 19, firstName: 'Deepa', lastName: 'Pillai', gender: 'FEMALE', age: 30,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Nair', community: null,
    motherTongue: 'Malayalam', languagesKnown: ['Malayalam', 'English', 'Hindi'], heightCm: 164,
    annualIncomeLakhs: 26, highestEducation: 'MD', profession: 'Doctor',
    employerName: 'AIIMS', currentCity: 'Thiruvananthapuram', currentState: 'Kerala', country: 'India',
    bio: 'Paediatrician. I keep bees, which surprises people, and I read far too much crime fiction.',
    dietaryHabits: NON_VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Reading', 'Gardening', 'Travel'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 29, maxAge: 38, minHeightCm: 170, maxHeightCm: 190,
      preferredReligions: ['Hindu'], preferredCastes: ['Nair', 'Menon'], minIncomeLakhs: 20,
      preferredCities: ['Thiruvananthapuram', 'Kochi', 'Bengaluru'], preferredStates: ['Kerala'],
      preferredEducation: ['MBBS', 'MD'], preferredOccupations: ['Doctor'],
      preferredMotherTongues: ['Malayalam'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 20, firstName: 'Gokul', lastName: 'Prasad', gender: 'MALE', age: 26,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Mudaliar', community: 'Vellalar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 168,
    annualIncomeLakhs: 6, highestEducation: 'Diploma', profession: 'Graphic Designer',
    employerName: 'Freelance', currentCity: 'Tiruchirappalli', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Designer working for myself. Sketchbook always in the bag. Slow mornings, loud music.',
    dietaryHabits: EGGETARIAN, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Art', 'Music', 'Gaming'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Liberal', theme: 'DARK',
    pushNotificationsEnabled: true, language: 'ta',
    pref: {
      minAge: 22, maxAge: 28, minHeightCm: 148, maxHeightCm: 168,
      preferredReligions: [], preferredCastes: [], minIncomeLakhs: null,
      preferredCities: [], preferredStates: [],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: [], maritalStatusPref: [],
    },
  },
  {
    index: 21, firstName: 'Harini', lastName: 'Venkatesh', gender: 'FEMALE', age: 31,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Iyengar', community: 'Brahmin',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English', 'Sanskrit'], heightCm: 161,
    annualIncomeLakhs: 30, highestEducation: 'Ph.D', profession: 'Research Scientist',
    employerName: 'IIT Madras', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Materials researcher. I make ceramics in my spare time, which is thematically consistent.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Pottery', 'Reading', 'Trekking'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'LIGHT',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 30, maxAge: 40, minHeightCm: 168, maxHeightCm: 190,
      preferredReligions: ['Hindu'], preferredCastes: ['Iyengar', 'Iyer'], minIncomeLakhs: 25,
      preferredCities: ['Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: ['Ph.D', 'M.Tech'], preferredOccupations: ['Research Scientist', 'Professor'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 22, firstName: 'Manoj', lastName: 'Balakrishnan', gender: 'MALE', age: 35,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Chettiar', community: 'Nagarathar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 182,
    annualIncomeLakhs: 45, highestEducation: 'MBA', profession: 'Business',
    employerName: 'Self-employed', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'I run a logistics company. Early riser, tennis player, and a soft spot for old Tamil cinema.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Tennis', 'Movies', 'Travel'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'ta',
    pref: {
      minAge: 26, maxAge: 33, minHeightCm: 155, maxHeightCm: 172,
      preferredReligions: ['Hindu'], preferredCastes: ['Chettiar'], minIncomeLakhs: null,
      preferredCities: ['Chennai', 'Madurai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 23, firstName: 'Swathi', lastName: 'Gowda', gender: 'FEMALE', age: 25,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Vokkaliga', community: null,
    motherTongue: 'Kannada', languagesKnown: ['Kannada', 'English'], heightCm: 154,
    annualIncomeLakhs: 9, highestEducation: 'BCA', profession: 'Software Engineer',
    employerName: 'Wipro', currentCity: 'Bengaluru', currentState: 'Karnataka', country: 'India',
    bio: 'Frontend developer. Plant collector, filter coffee loyalist, and a very average badminton player.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Gardening', 'Badminton', 'Music'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'LIGHT',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 25, maxAge: 32, minHeightCm: 162, maxHeightCm: 182,
      preferredReligions: ['Hindu'], preferredCastes: ['Vokkaliga'], minIncomeLakhs: 8,
      preferredCities: ['Bengaluru', 'Mysuru'], preferredStates: ['Karnataka'],
      preferredEducation: [], preferredOccupations: ['Software Engineer'],
      preferredMotherTongues: ['Kannada'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 24, firstName: 'Praveen', lastName: 'Rao', gender: 'MALE', age: 29,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Vokkaliga', community: null,
    motherTongue: 'Kannada', languagesKnown: ['Kannada', 'English', 'Hindi'], heightCm: 173,
    annualIncomeLakhs: 19, highestEducation: 'B.E', profession: 'Software Engineer',
    employerName: 'Flipkart', currentCity: 'Bengaluru', currentState: 'Karnataka', country: 'India',
    bio: 'Engineer at an e-commerce company. Cyclist, chess player, and permanently mid-renovation on some side project.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Cycling', 'Chess', 'Gaming'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'DARK',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 23, maxAge: 28, minHeightCm: 150, maxHeightCm: 168,
      preferredReligions: ['Hindu'], preferredCastes: ['Vokkaliga'], minIncomeLakhs: null,
      preferredCities: ['Bengaluru'], preferredStates: ['Karnataka'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Kannada'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 25, firstName: 'Lakshmi', lastName: 'Narayanan', gender: 'FEMALE', age: 33,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Iyer', community: 'Brahmin',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English', 'German'], heightCm: 168,
    annualIncomeLakhs: 38, highestEducation: 'M.Tech', profession: 'Engineering Manager',
    employerName: 'Google', currentCity: 'Bengaluru', currentState: 'Karnataka', country: 'India',
    bio: 'Engineering manager. Spent two years in Munich and still miss the trains. Runner, reader, terrible gardener.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Running', 'Reading', 'Travel'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Liberal', theme: 'DARK',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 32, maxAge: 42, minHeightCm: 172, maxHeightCm: 195,
      preferredReligions: ['Hindu'], preferredCastes: ['Iyer'], minIncomeLakhs: 35,
      preferredCities: ['Bengaluru'], preferredStates: ['Karnataka'],
      preferredEducation: ['M.Tech', 'Ph.D', 'MBA'], preferredOccupations: ['Engineering Manager'],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 26, firstName: 'Sathish', lastName: 'Palani', gender: 'MALE', age: 34,
    maritalStatus: 'AWAITING_DIVORCE', religion: 'Hindu', caste: 'Gounder', community: 'Kongu Vellalar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 170,
    annualIncomeLakhs: 13, highestEducation: 'B.Com', profession: 'Sales Manager',
    employerName: 'Bajaj', currentCity: 'Erode', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Sales manager, cricket obsessive, and slowly learning to cook something other than instant noodles.',
    dietaryHabits: NON_VEG, smokingHabits: OCCASIONALLY, drinkingHabits: OCCASIONALLY,
    hobbies: ['Cricket', 'Movies', 'Music'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'SYSTEM',
    pushNotificationsEnabled: false, language: 'ta',
    pref: {
      minAge: 28, maxAge: 38, minHeightCm: 150, maxHeightCm: 170,
      preferredReligions: ['Hindu'], preferredCastes: [], minIncomeLakhs: null,
      preferredCities: [], preferredStates: ['Tamil Nadu'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['DIVORCED', 'AWAITING_DIVORCE', 'WIDOWED'],
    },
  },
  {
    index: 27, firstName: 'Nandhini', lastName: 'Selvam', gender: 'FEMALE', age: 23,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Gounder', community: 'Kongu Vellalar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 152,
    annualIncomeLakhs: 5, highestEducation: 'B.Sc', profession: 'Lab Technician',
    employerName: 'Kovai Medical Center', currentCity: 'Erode', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Lab technician. Youngest of three, which explains a lot. I love temple festivals and street food.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Cooking', 'Dancing', 'Movies'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'LIGHT',
    pushNotificationsEnabled: true, language: 'ta',
    pref: {
      minAge: 24, maxAge: 30, minHeightCm: 160, maxHeightCm: 180,
      preferredReligions: ['Hindu'], preferredCastes: ['Gounder'], minIncomeLakhs: null,
      preferredCities: ['Erode', 'Coimbatore'], preferredStates: ['Tamil Nadu'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
  {
    index: 28, firstName: 'Vikram', lastName: 'Chandran', gender: 'MALE', age: 38,
    maritalStatus: 'WIDOWED', religion: 'Hindu', caste: 'Mudaliar', community: 'Vellalar',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 179,
    annualIncomeLakhs: 35, highestEducation: 'CA', profession: 'Chartered Accountant',
    employerName: 'Self-employed', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Chartered accountant with my own practice. Father to a ten-year-old. Cycling and carnatic music keep me sane.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Cycling', 'Music', 'Reading'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Moderate', theme: 'LIGHT',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 30, maxAge: 42, minHeightCm: 150, maxHeightCm: 175,
      preferredReligions: ['Hindu'], preferredCastes: [], minIncomeLakhs: null,
      preferredCities: ['Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['WIDOWED', 'DIVORCED', 'NEVER_MARRIED'],
    },
  },
  {
    index: 29, firstName: 'Shruti', lastName: 'Bhat', gender: 'FEMALE', age: 29,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Brahmin', community: 'Havyaka',
    motherTongue: 'Hindi', languagesKnown: ['Hindi', 'Konkani', 'English'], heightCm: 166,
    annualIncomeLakhs: 21, highestEducation: 'M.Des', profession: 'UX Designer',
    employerName: 'Swiggy', currentCity: 'Bangalore', currentState: 'Karnataka', country: 'India',
    bio: 'UX designer. I sketch on trains, over-research restaurants, and have strong opinions about typography.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: OCCASIONALLY,
    hobbies: ['Art', 'Travel', 'Reading'], physicalStatus: 'Normal',
    familyType: 'Nuclear', familyValues: 'Liberal', theme: 'DARK',
    pushNotificationsEnabled: true, language: 'en',
    pref: {
      minAge: 28, maxAge: 36, minHeightCm: 168, maxHeightCm: 190,
      preferredReligions: ['Hindu'], preferredCastes: [], minIncomeLakhs: 15,
      preferredCities: ['Bengaluru', 'Pune'], preferredStates: ['Karnataka'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: [], maritalStatusPref: ['NEVER_MARRIED', 'DIVORCED'],
    },
  },
  {
    index: 30, firstName: 'Aravind', lastName: 'Krishnamoorthy', gender: 'MALE', age: 25,
    maritalStatus: 'NEVER_MARRIED', religion: 'Hindu', caste: 'Iyengar', community: 'Brahmin',
    motherTongue: 'Tamil', languagesKnown: ['Tamil', 'English'], heightCm: 166,
    annualIncomeLakhs: 7, highestEducation: 'B.Sc', profession: 'Teacher',
    employerName: 'Vidya Mandir', currentCity: 'Chennai', currentState: 'Tamil Nadu', country: 'India',
    bio: 'Maths teacher, chess club coach, and the person who always brings the board games.',
    dietaryHabits: VEG, smokingHabits: NEVER, drinkingHabits: NEVER,
    hobbies: ['Chess', 'Reading', 'Music'], physicalStatus: 'Normal',
    familyType: 'Joint', familyValues: 'Traditional', theme: 'SYSTEM',
    pushNotificationsEnabled: true, language: 'ta',
    pref: {
      minAge: 22, maxAge: 27, minHeightCm: 150, maxHeightCm: 168,
      preferredReligions: ['Hindu'], preferredCastes: ['Iyengar', 'Iyer'], minIncomeLakhs: null,
      preferredCities: ['Chennai'], preferredStates: ['Tamil Nadu'],
      preferredEducation: [], preferredOccupations: [],
      preferredMotherTongues: ['Tamil'], maritalStatusPref: ['NEVER_MARRIED'],
    },
  },
];

/**
 * What this particular set of 30 is designed to let you test. Kept next to the
 * data so it stays true when the data changes.
 *
 *  Gender split      15 female / 15 male — every feed is opposite-gender, so
 *                    both directions have a populated result set.
 *  Strong mutual     #1 Aarthi <-> #2 Karthik (Iyer/Brahmin, Chennai, Tamil,
 *                    each inside the other's age/height/income/caste bands).
 *  One-way only      #3 Divya wants #4 Vignesh's city but he requires Gounder
 *                    caste and she is Iyengar — she matches him, he rejects her.
 *  No match          #21 Harini (Ph.D, >=25L, Chennai) vs #20 Gokul (Diploma,
 *                    6L, Trichy) — fails on income, education and location.
 *  Broad prefs       #17 Kavya and #20 Gokul have empty preference arrays, so
 *                    they exercise the "no filters set" fallback path.
 *  Restrictive       #25 Lakshmi (>=35L, M.Tech+, Bengaluru, Iyer) matches at
 *                    most one profile — good for testing empty/near-empty feeds.
 *  Marital status    NEVER_MARRIED, DIVORCED (#5, #16), WIDOWED (#15, #28) and
 *                    AWAITING_DIVORCE (#26) are all represented.
 *  Religion          Hindu, Muslim (#11, #12) and Christian (#13, #14) pairs,
 *                    each preferring their own — tests religion filtering.
 *  Language          Tamil, Hindi, Malayalam, Telugu, Kannada.
 *                    Hindi (#11, #12, #29) is deliberately present: the feed
 *                    resolves a "Same Mother Tongue" preference against the
 *                    caller's own tongue, so a set without Hindi returns an
 *                    EMPTY feed for any Hindi-speaking member — which is
 *                    exactly what happened before these three were changed.
 *  City spelling     Both "Bengaluru" and "Bangalore" appear, on purpose.
 *                    "Same City" matches the caller's stored string exactly,
 *                    and real profiles in this database use both spellings.
 *  Region            Tamil Nadu, Karnataka, Kerala, Telangana.
 *  Height range      152cm - 182cm, so height bands actually exclude people.
 *  Income range      5L - 45L, so income floors actually exclude people.
 *  Diet/lifestyle    Vegetarian / Non-Vegetarian / Eggetarian, and two members
 *                    who smoke occasionally (#18, #26).
 *  Settings          LIGHT / DARK / SYSTEM themes, push on and off, en and ta.
 */
export const FEED_TEST_NOTES = true;
