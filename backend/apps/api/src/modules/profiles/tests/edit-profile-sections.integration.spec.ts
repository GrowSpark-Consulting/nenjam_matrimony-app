import { readFileSync } from 'fs';
import { join } from 'path';
import { NotFoundException, ValidationPipe } from '@nestjs/common';
import { Prisma, PrismaClient } from '@app/database';
import type { PrismaService } from '@app/database';
import type { S3Service } from '@app/storage';
import { ProfileDraftController } from '../controllers/profile-draft.controller';
import { ProfileRepository } from '../repositories/profile.repository';
import { PhotoRepository } from '../repositories/photo.repository';
import { RecommendationDismissalRepository } from '../repositories/recommendation-dismissal.repository';
import { ProfileCompletionService } from '../services/profile-completion.service';
import { ProfileDraftService } from '../services/profile-draft.service';
import { ProfileService } from '../services/profile.service';
import { LocationService } from '../../reference-data/services/location.service';
import type { EmailDispatchService } from '../../notifications/services/email-dispatch.service';
import type { FeedInvalidationService } from '../../matches/cache/feed-invalidation.service';
import { BasicDetailsDto } from '../dto/basic-details.dto';
import { ReligionDetailsDto } from '../dto/religion-details.dto';
import { LocationDetailsDto } from '../dto/location-details.dto';
import { EducationDetailsDto } from '../dto/education-details.dto';
import { PhysicalDetailsDto } from '../dto/physical-details.dto';
import { LifestyleDetailsDto } from '../dto/lifestyle-details.dto';
import { FamilyDetailsDto } from '../dto/family-details.dto';
import { HoroscopeDetailsDto } from '../dto/horoscope-details.dto';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from './integration-schema-guard';

/**
 * Edit Profile's section saves, end to end against a REAL Postgres.
 *
 * Each request body is the one the Flutter client actually sends (recorded in
 * `fixtures/edit-profile-section-payloads.json`; see
 * `edit-profile-section-payloads.spec.ts`). It goes through the production
 * ValidationPipe and then into the REAL ProfileDraftController handler for
 * that section, wired to the real services and repositories — draft merge,
 * location master-data check, `user_profiles` materialisation, completion
 * recompute. Only the three side effects that leave the database are
 * stubbed: the welcome email, the Redis feed-cache invalidation and S3 URL
 * signing. What is missing versus a live request is HTTP itself and the
 * Firebase guard (covered by the guard's own specs and the e2e suite).
 *
 * Read-back is fresh: `ProfileDraftService.getDraft` (what GET
 * /profiles/draft returns — Edit Profile's reload) and a direct
 * `user_profiles` query (what other members see).
 *
 * Isolated by schema and skipped unless `INTEGRATION_DATABASE_URL` names a
 * throwaway one — never `public`, which holds the production tables. The
 * schema must have the migrations applied (`prisma migrate deploy`).
 */

type RecordedRequest = { body: Record<string, unknown> };

const fixture = JSON.parse(
  readFileSync(
    join(__dirname, 'fixtures', 'edit-profile-section-payloads.json'),
    'utf8',
  ),
) as Record<string, RecordedRequest>;

const pipe = new ValidationPipe({
  whitelist: true,
  transform: true,
  forbidNonWhitelisted: true,
});

type Handler = (
  c: ProfileDraftController,
  userId: string,
  dto: never,
) => Promise<unknown>;

/** Each section's DTO and the controller handler its PATCH route calls. */
const sections: Record<string, { dto: new () => object; call: Handler }> = {
  basicDetails: {
    dto: BasicDetailsDto,
    call: (c, u, d) => c.updateBasicDetails(u, d),
  },
  religionDetails: {
    dto: ReligionDetailsDto,
    call: (c, u, d) => c.updateReligionDetails(u, d),
  },
  locationDetails: {
    dto: LocationDetailsDto,
    call: (c, u, d) => c.updateLocationDetails(u, d),
  },
  educationDetails: {
    dto: EducationDetailsDto,
    call: (c, u, d) => c.updateEducationDetails(u, d),
  },
  physicalDetails: {
    dto: PhysicalDetailsDto,
    call: (c, u, d) => c.updatePhysicalDetails(u, d),
  },
  lifestyleDetails: {
    dto: LifestyleDetailsDto,
    call: (c, u, d) => c.updateLifestyleDetails(u, d),
  },
  familyDetails: {
    dto: FamilyDetailsDto,
    call: (c, u, d) => c.updateFamilyDetails(u, d),
  },
  horoscopeDetails: {
    dto: HoroscopeDetailsDto,
    call: (c, u, d) => c.updateHoroscopeDetails(u, d),
  },
};

/**
 * The member's stored draft before the edit: complete enough to be
 * matchable (so every save materialises `user_profiles`), with the fields
 * current registration no longer asks for populated too.
 */
const storedDraft: Record<string, Record<string, unknown>> = {
  basicDetails: {
    firstName: 'Meera',
    lastName: 'Rajan',
    gender: 'FEMALE',
    dob: '1995-03-21',
    maritalStatus: 'NEVER_MARRIED',
    profileCreatedFor: 'Myself',
  },
  religionDetails: {
    religion: 'Hindu',
    religionCode: 'HINDU',
    community: 'Iyer',
    communityCode: 'HINDU-IYER',
    subCaste: 'Vadama',
    caste: 'Brahmin',
    gothra: 'Kashyapa',
  },
  languageDetails: { motherTongue: 'Tamil', languagesKnown: ['Tamil'] },
  locationDetails: {
    country: 'India',
    countryCode: 'IN',
    state: 'Tamil Nadu',
    stateCode: 'IN-TN',
    city: 'Chennai',
    cityCode: 'IN-TN-CHENNAI',
    pinCode: '600001',
    nativePlace: 'Madurai',
  },
  educationDetails: {
    qualification: 'B.E / B.Tech',
    college: 'Anna University',
    occupation: 'Software Engineer',
    company: 'Acme',
    employmentType: 'Private',
    annualIncome: '10 - 20 Lakhs',
    workLocation: 'Chennai',
  },
  physicalDetails: {
    height: `5'4" (163 cm)`,
    weight: '55',
    bloodGroup: 'O+',
    disability: 'None',
  },
  lifestyleDetails: {
    eatingHabit: 'Vegetarian',
    aboutMe: 'I love music.',
    smoking: 'No',
    drinking: 'No',
    fitness: 'Yoga',
    hobbies: ['Music', 'Reading'],
  },
  familyDetails: { familyType: 'Nuclear', familyValues: 'Traditional' },
  horoscopeDetails: { rashi: 'Mesha' },
};

/** What `user_profiles` must hold after each section's save. */
const expectedProfile: Record<string, Record<string, unknown>> = {
  basicDetails: { firstName: 'Meenakshi', lastName: 'Rajan', gender: 'FEMALE' },
  religionDetails: { subCaste: 'Vathima', caste: 'Brahmin' },
  locationDetails: {
    currentCity: 'Ahmedabad',
    currentState: 'Gujarat',
    country: 'India',
    cityCode: 'IN-GJ-AHMEDABAD',
    stateCode: 'IN-GJ',
    countryCode: 'IN',
    pinCode: '600001',
  },
  educationDetails: {
    highestEducation: 'M.Tech / M.E',
    employerName: 'Globex',
    college: 'Anna University',
  },
  physicalDetails: { heightCm: 168, weightKg: 55 },
  lifestyleDetails: {
    dietaryHabits: 'Eggetarian',
    bio: 'I love music and travel.',
    smokingHabits: 'No',
  },
  familyDetails: { familyType: 'Joint' },
  horoscopeDetails: {},
};

describeIntegration('Edit Profile section saves, against Postgres', () => {
  let prisma: PrismaClient;
  let controller: ProfileDraftController;
  let draftService: ProfileDraftService;

  const USER = 'itest-edit-profile-1';

  beforeAll(async () => {
    prisma = await connectIsolatedPrisma();
    const db = prisma as unknown as PrismaService;
    const profiles = new ProfileRepository(db);
    const photos = new PhotoRepository(db);
    const completion = new ProfileCompletionService(
      db,
      profiles,
      photos,
      new RecommendationDismissalRepository(db),
    );
    draftService = new ProfileDraftService(profiles, completion);
    const profileService = new ProfileService(
      profiles,
      photos,
      draftService,
      completion,
      {
        sendWelcome: () => Promise.resolve(),
      } as unknown as EmailDispatchService,
      {
        invalidate: () => Promise.resolve(),
      } as unknown as FeedInvalidationService,
      { isConfigured: () => false } as unknown as S3Service,
      new LocationService(db),
    );
    controller = new ProfileDraftController(draftService, profileService);

    // The location master data the saves reference.
    await prisma.country.upsert({
      where: { code: 'IN' },
      update: {},
      create: { code: 'IN', label: 'India' },
    });
    for (const [code, label] of [
      ['IN-TN', 'Tamil Nadu'],
      ['IN-GJ', 'Gujarat'],
    ]) {
      await prisma.subdivision.upsert({
        where: { code },
        update: {},
        create: { code, label, countryCode: 'IN', type: 'State' },
      });
    }
    for (const [code, label, stateCode] of [
      ['IN-TN-CHENNAI', 'Chennai', 'IN-TN'],
      ['IN-GJ-AHMEDABAD', 'Ahmedabad', 'IN-GJ'],
    ]) {
      await prisma.city.upsert({
        where: { code },
        update: {},
        create: { code, label, stateCode, countryCode: 'IN', population: 1 },
      });
    }
  });

  beforeEach(async () => {
    // registration_steps and user_profiles cascade from users.
    await prisma.user.deleteMany({ where: { id: USER } });
    await prisma.user.create({
      data: {
        id: USER,
        firebaseUid: `fb-${USER}`,
        email: `${USER}@example.com`,
      },
    });
    await prisma.registrationStep.create({
      data: {
        userId: USER,
        currentStep: 1,
        draftData: storedDraft as Prisma.InputJsonValue,
      },
    });
  });

  afterAll(async () => {
    await prisma?.user.deleteMany({ where: { id: USER } });
    await prisma?.$disconnect();
  });

  /** The PATCH route's work: validate the body, run the handler. */
  async function patch(section: string, body: Record<string, unknown>) {
    const dto = (await pipe.transform(body, {
      type: 'body',
      metatype: sections[section].dto,
    })) as never;
    return sections[section].call(controller, USER, dto);
  }

  /** A fresh GET /profiles/draft. */
  async function readDraft(): Promise<Record<string, Record<string, unknown>>> {
    const response = await draftService.getDraft(USER);
    return response.data as Record<string, Record<string, unknown>>;
  }

  it.each(Object.keys(sections))(
    '%s: persisted, read back fresh, hidden fields and other sections intact',
    async (section) => {
      const body = fixture[section].body;
      await patch(section, body);

      // The draft — Edit Profile's reload.
      const after = await readDraft();
      expect(after[section]).toMatchObject(
        JSON.parse(JSON.stringify(body)) as Record<string, unknown>,
      );
      for (const [key, value] of Object.entries(storedDraft[section])) {
        if (!(key in body)) expect(after[section][key]).toEqual(value);
      }
      for (const other of Object.keys(storedDraft)) {
        if (other !== section) expect(after[other]).toEqual(storedDraft[other]);
      }

      // user_profiles — what other members see.
      const profile = await prisma.userProfile.findUnique({
        where: { userId: USER },
      });
      expect(profile).not.toBeNull();
      expect(profile).toMatchObject(expectedProfile[section]);
    },
  );

  it('a body omitting hidden fields does not erase them', async () => {
    // Only what the Physical Details page shows. The client sends the whole
    // hydrated section, but the server must not depend on that.
    await patch('physicalDetails', { height: `5'6" (168 cm)` });

    expect((await readDraft()).physicalDetails).toEqual({
      ...storedDraft.physicalDetails,
      height: `5'6" (168 cm)`,
    });
    const profile = await prisma.userProfile.findUnique({
      where: { userId: USER },
    });
    expect(profile).toMatchObject({ heightCm: 168, weightKg: 55 });
  });

  it('a failed user_profiles copy fails the save instead of reporting success', async () => {
    // A first, good save materialises the row.
    await patch('locationDetails', fixture.locationDetails.body);

    // A city code the master data does not hold: well-formed, so the DTO
    // accepts it, but the copy into user_profiles cannot resolve it.
    await expect(
      patch('locationDetails', {
        ...fixture.locationDetails.body,
        city: 'Nowhere',
        cityCode: 'IN-GJ-NOWHERE',
      }),
    ).rejects.toBeInstanceOf(NotFoundException);

    // The public profile still holds the last good save.
    const profile = await prisma.userProfile.findUnique({
      where: { userId: USER },
    });
    expect(profile).toMatchObject({
      currentCity: 'Ahmedabad',
      cityCode: 'IN-GJ-AHMEDABAD',
    });
  });
});
