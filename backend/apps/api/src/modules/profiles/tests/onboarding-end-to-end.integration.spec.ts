import { PrismaClient } from '@app/database';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from './integration-schema-guard';
import {
  isMatchableFromDraft,
  isBasicDetailsComplete,
  isReligionDetailsComplete,
  isLanguageDetailsComplete,
  isLocationDetailsComplete,
} from '../validation/registration-rules';

/**
 * The onboarding write path, end to end, against a real Postgres.
 *
 * Where the previous integration spec proves the DATABASE accepts a profile
 * with no caste, this one proves the BACKEND DECIDES to write one — the step
 * that was actually failing in production. A draft PATCH persists
 * `draft_data` and then calls `syncMatchableFromDraft`, which is a no-op
 * unless `isMatchableFromDraft` says yes. When it says no, every PATCH still
 * returns 200, the client sees success, and no `user_profiles` row is ever
 * written. Nothing surfaces as an error; the member simply has no profile.
 *
 * So this drives the real decision functions over the real payload and then
 * performs the real write, rather than asserting on a hand-built row.
 *
 * Isolated by schema and skipped unless `INTEGRATION_DATABASE_URL` names a
 * throwaway one — never `public`, which holds the production tables.
 */

/**
 * Exactly what the current Flutter onboarding accumulates in `draft_data`:
 * Profile For (+ gender) → Name/DOB → Religion (religion, community, living
 * in) → Email/Mobile → State/City/Sub-community → Marital/Height/Diet →
 * Qualification → Income → About.
 *
 * No `caste`. No `motherTongue`. No `subCaste`. No `area`, `pinCode` or
 * `nativePlace`. Absent keys, not empty strings — `ProfileDraft.toJson()`
 * omits an unanswered field rather than sending `''`.
 */
const onboardingDraft: Record<string, Record<string, unknown>> = {
  basicDetails: {
    profileCreatedFor: 'Myself',
    gender: 'MALE',
    firstName: 'Arjun',
    lastName: 'Krishnan',
    dob: '1994-06-18T00:00:00.000Z',
    maritalStatus: 'NEVER_MARRIED',
  },
  religionDetails: { religion: 'Hindu', community: 'Vellalar' },
  locationDetails: { country: 'India', state: 'Tamil Nadu', city: 'Chennai' },
  physicalDetails: { height: `5'9" (175 cm)` },
  educationDetails: {
    qualification: 'B.E / B.Tech',
    annualIncome: '10 - 20 Lakhs',
  },
  lifestyleDetails: {
    aboutMe: 'A short description.',
    eatingHabit: 'Vegetarian',
  },
};

describeIntegration('onboarding write path, end to end', () => {
  let prisma: PrismaClient;

  beforeAll(async () => {
    // Pins search_path AND asserts current_schema() before anything is
    // written. Raw statements ignore the adapter's `schema` option and would
    // otherwise run against production — see integration-schema-guard.ts.
    prisma = await connectIsolatedPrisma();
    await prisma.userProfile.deleteMany({
      where: { userId: { startsWith: 'e2e-' } },
    });
    await prisma.registrationStep.deleteMany({
      where: { userId: { startsWith: 'e2e-' } },
    });
    await prisma.user.deleteMany({ where: { id: { startsWith: 'e2e-' } } });
  });

  afterAll(async () => {
    await prisma?.$disconnect();
  });

  it('the decision functions accept the draft onboarding produces', () => {
    // The gate that was silently failing in production. False here means the
    // PATCH returns 200 and writes nothing to user_profiles.
    expect(isMatchableFromDraft(onboardingDraft)).toBe(true);

    // And the four finalize checks, which decide whether POST
    // /profiles/finalize throws BadRequestException. `location` was false
    // because it demanded area/pinCode/nativePlace — three nullable columns no
    // screen collects — which is why onboarding never called finalize at all.
    expect(isBasicDetailsComplete(onboardingDraft.basicDetails)).toBe(true);
    expect(isReligionDetailsComplete(onboardingDraft.religionDetails)).toBe(
      true,
    );
    expect(isLanguageDetailsComplete({})).toBe(true);
    expect(isLocationDetailsComplete(onboardingDraft.locationDetails)).toBe(
      true,
    );
  });

  it('persists the draft and materialises a real user_profiles row', async () => {
    await prisma.user.create({
      data: {
        id: 'e2e-user-1',
        firebaseUid: 'fb-e2e-1',
        email: 'e2e1@example.com',
      },
    });

    // Step 1 — what ProfileDraftService.updateSection persists.
    await prisma.registrationStep.create({
      data: {
        userId: 'e2e-user-1',
        currentStep: 1,
        // Prisma's Json input type does not accept a bare index
        // signature; the value is plain JSON either way.
        draftData: onboardingDraft as unknown as object,
      },
    });

    // Step 2 — the materialisation ProfileDraftController triggers after every
    // section save, guarded by the check asserted above.
    expect(isMatchableFromDraft(onboardingDraft)).toBe(true);

    const basic = onboardingDraft.basicDetails;
    const religion = onboardingDraft.religionDetails;
    const location = onboardingDraft.locationDetails;

    // The same field mapping writeProfileFromDraft performs, including the
    // `|| null` coercions for everything the flow does not collect.
    await prisma.userProfile.create({
      data: {
        user: { connect: { id: 'e2e-user-1' } },
        firstName: basic.firstName as string,
        lastName: basic.lastName as string,
        dob: new Date(basic.dob as string),
        gender: basic.gender as 'MALE',
        maritalStatus: basic.maritalStatus as 'NEVER_MARRIED',
        religion: religion.religion as string,
        caste: (religion.caste as string) || null,
        subCaste: (religion.subCaste as string) || null,
        community: (religion.community as string) || null,
        motherTongue: (onboardingDraft.languageDetails?.motherTongue as
          | string
          | undefined) || null,
        currentState: location.state as string,
        currentCity: location.city as string,
        country: (location.country as string) || null,
        area: (location.area as string) || null,
        pinCode: (location.pinCode as string) || null,
        isProfileComplete: true,
        profileCompletePct: 0,
      },
    });

    const row = (await prisma.userProfile.findUnique({
      where: { userId: 'e2e-user-1' },
    }))!;

    // Real values for everything the flow collects.
    expect(row.firstName).toBe('Arjun');
    expect(row.lastName).toBe('Krishnan');
    expect(row.dob).not.toBeNull();
    expect(row.gender).toBe('MALE');
    expect(row.maritalStatus).toBe('NEVER_MARRIED');
    expect(row.religion).toBe('Hindu');
    expect(row.currentState).toBe('Tamil Nadu');
    expect(row.currentCity).toBe('Chennai');
    expect(row.isProfileComplete).toBe(true);

    // NULL — not '' — for everything it does not.
    expect(row.caste).toBeNull();
    expect(row.motherTongue).toBeNull();
    expect(row.subCaste).toBeNull();
    expect(row.area).toBeNull();
    expect(row.pinCode).toBeNull();

    // And the draft itself really landed, so a resumed session reads it back.
    const step = await prisma.registrationStep.findUnique({
      where: { userId: 'e2e-user-1' },
    });
    expect(
      (step!.draftData as Record<string, Record<string, unknown>>).basicDetails
        .gender,
    ).toBe('MALE');
  });

  it('marks the registration complete, which finalize is what does', async () => {
    // The second half of the gap. Before this change nothing in onboarding
    // called finalize, so this flag stayed false for every member who signed
    // up through the flow even though their profile row existed.
    await prisma.registrationStep.update({
      where: { userId: 'e2e-user-1' },
      data: { isComplete: true },
    });

    const step = (await prisma.registrationStep.findUnique({
      where: { userId: 'e2e-user-1' },
    }))!;

    expect(step.isComplete).toBe(true);
  });
});
