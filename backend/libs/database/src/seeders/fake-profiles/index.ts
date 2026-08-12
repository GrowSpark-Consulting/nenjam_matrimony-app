/**
 * Seeds 30 fake members that behave, to the database, exactly like members
 * created through the real registration flow.
 *
 * Why the row set below is what it is: `buildFeedWhere` requires
 * `UserProfile.isProfileComplete = true`, `User.deletedAt = null` and a
 * `User.status` outside {SUSPENDED, DEACTIVATED, BANNED} for a profile to be
 * discoverable — and `ProfileService.finalize()` is what normally produces
 * that state, alongside a RegistrationStep marked complete, a
 * PartnerPreference row and photos. Each seeded member therefore gets the same
 * set of rows finalize() would have left behind.
 *
 * Identity is deterministic. Everything hangs off `firebaseUid`
 * = `seed-fake-user-NN`, which is the natural key for the upserts, so running
 * the seeder twice updates the same 30 members instead of creating 60. Emails
 * use the reserved `.invalid` TLD (RFC 2606) so that no transactional email
 * this app sends can ever reach a real inbox.
 *
 * These members have no Firebase Auth accounts — the backend has no
 * createUser, only verifyIdToken/deleteUser (FirebaseService), because the
 * Flutter client owns signup. They are browsable, discoverable, searchable and
 * matchable content; you cannot sign in AS one.
 */
import type { Prisma, PrismaClient } from '../../../generated/client';
import { FAKE_PEOPLE, type FakePerson } from './fake-people';
import {
  makeS3Client,
  uploadFakePhoto,
  type PhotoStorageConfig,
  type PhotoUploadResult,
} from './fake-photos';

/** Marks every row this seeder owns. Never change — `unseed` matches on it. */
export const SEED_UID_PREFIX = 'seed-fake-user-';
export const SEED_EMAIL_DOMAIN = 'nenjam-seed.invalid';

export function seedUid(index: number): string {
  return `${SEED_UID_PREFIX}${String(index).padStart(2, '0')}`;
}

export function seedEmail(index: number): string {
  return `seed.fake.${String(index).padStart(2, '0')}@${SEED_EMAIL_DOMAIN}`;
}

/** Deterministic DOB so re-runs don't drift the member's age by a day. */
function dobForAge(age: number): Date {
  return new Date(Date.UTC(2026 - age, 5, 15));
}

/**
 * The wizard has 12 steps; a finalized member has completed all of them.
 * Mirrors the shape RegistrationStep carries after finalize().
 */
const ALL_STEPS = Array.from({ length: 12 }, (_, i) => i + 1);

export interface SeedReport {
  users: number;
  profiles: number;
  preferences: number;
  settings: number;
  registrationSteps: number;
  photos: number;
  photosUploaded: number;
  photosAlreadyPresent: number;
  interests: number;
  shortlists: number;
  blocks: number;
  reports: number;
  conversations: number;
  messages: number;
  notifications: number;
  storageSkipped: boolean;
}

/**
 * Creates (or refreshes) one member and everything the app expects to hang off
 * them. One transaction per member: a failure leaves that member absent rather
 * than half-built, and the other 29 are unaffected.
 */
async function seedPerson(
  prisma: PrismaClient,
  person: FakePerson,
  photo: PhotoUploadResult | null,
): Promise<string> {
  const uid = seedUid(person.index);

  return prisma.$transaction(async (tx) => {
    const user = await tx.user.upsert({
      where: { firebaseUid: uid },
      create: {
        firebaseUid: uid,
        email: seedEmail(person.index),
        // ACTIVE rather than PENDING_VERIFICATION: buildFeedWhere tolerates
        // both, but ACTIVE is what a fully onboarded member should look like
        // and keeps these rows honest if the status filter is ever tightened.
        status: 'ACTIVE',
        role: 'USER',
      },
      update: { status: 'ACTIVE', deletedAt: null },
      select: { id: true },
    });

    const profileData = {
      firstName: person.firstName,
      lastName: person.lastName,
      dob: dobForAge(person.age),
      gender: person.gender,
      maritalStatus: person.maritalStatus,
      religion: person.religion,
      caste: person.caste,
      community: person.community,
      motherTongue: person.motherTongue,
      languagesKnown: person.languagesKnown as Prisma.InputJsonValue,
      heightCm: person.heightCm,
      annualIncomeLakhs: person.annualIncomeLakhs.toString(),
      highestEducation: person.highestEducation,
      profession: person.profession,
      employerName: person.employerName,
      currentCity: person.currentCity,
      currentState: person.currentState,
      country: person.country,
      bio: person.bio,
      dietaryHabits: person.dietaryHabits,
      smokingHabits: person.smokingHabits,
      drinkingHabits: person.drinkingHabits,
      hobbies: person.hobbies as Prisma.InputJsonValue,
      physicalStatus: person.physicalStatus,
      familyType: person.familyType,
      familyValues: person.familyValues,
      // The invariant Discover actually filters on.
      isProfileComplete: true,
      // These members fill every field the wizard collects except the optional
      // family/astrology extras, which is what this works out to.
      profileCompletePct: 85,
    };

    await tx.userProfile.upsert({
      where: { userId: user.id },
      create: { userId: user.id, ...profileData },
      update: profileData,
    });

    const prefData = {
      minAge: person.pref.minAge,
      maxAge: person.pref.maxAge,
      minHeightCm: person.pref.minHeightCm,
      maxHeightCm: person.pref.maxHeightCm,
      preferredReligions: person.pref.preferredReligions as Prisma.InputJsonValue,
      preferredCastes: person.pref.preferredCastes as Prisma.InputJsonValue,
      minIncomeLakhs: person.pref.minIncomeLakhs?.toString() ?? null,
      preferredCities: person.pref.preferredCities as Prisma.InputJsonValue,
      preferredStates: person.pref.preferredStates as Prisma.InputJsonValue,
      preferredEducation: person.pref.preferredEducation as Prisma.InputJsonValue,
      preferredOccupations: person.pref.preferredOccupations as Prisma.InputJsonValue,
      preferredMotherTongues: person.pref.preferredMotherTongues as Prisma.InputJsonValue,
      maritalStatusPref: person.pref.maritalStatusPref as Prisma.InputJsonValue,
    };

    await tx.partnerPreference.upsert({
      where: { userId: user.id },
      create: { userId: user.id, ...prefData },
      update: prefData,
    });

    const stepData = {
      currentStep: 12,
      totalSteps: 12,
      completedSteps: ALL_STEPS as Prisma.InputJsonValue,
      isComplete: true,
    };
    await tx.registrationStep.upsert({
      where: { userId: user.id },
      create: { userId: user.id, ...stepData },
      update: stepData,
    });

    const settingsData = {
      theme: person.theme,
      pushNotificationsEnabled: person.pushNotificationsEnabled,
      language: person.language,
    };
    await tx.userSettings.upsert({
      where: { userId: user.id },
      create: { userId: user.id, ...settingsData },
      update: settingsData,
    });

    if (photo) {
      // Keyed on the deterministic s3Key so a re-run updates the same row.
      const existing = await tx.profilePhoto.findFirst({
        where: { userId: user.id, s3Key: photo.s3Key },
        select: { id: true },
      });
      const photoData = {
        s3Key: photo.s3Key,
        cdnUrl: photo.cdnUrl,
        isPrimary: true,
        order: 0,
        isApproved: true,
      };
      if (existing) {
        await tx.profilePhoto.update({ where: { id: existing.id }, data: photoData });
      } else {
        await tx.profilePhoto.create({ data: { userId: user.id, ...photoData } });
      }
    }

    return user.id;
  });
}

/**
 * Relationship data. Deliberately small: enough to exercise each screen, not
 * enough to bury the real members' data in the shared database.
 */
async function seedRelationships(
  prisma: PrismaClient,
  ids: Map<number, string>,
): Promise<Pick<SeedReport, 'interests' | 'shortlists' | 'blocks' | 'reports' | 'conversations' | 'messages' | 'notifications'>> {
  const id = (n: number): string => {
    const v = ids.get(n);
    if (!v) throw new Error(`seeded member ${n} missing`);
    return v;
  };

  // Interests: one accepted pair (so a conversation is legitimate), one
  // pending, one declined — every InterestStatus represented.
  const interestPairs: Array<[number, number, 'ACCEPTED' | 'PENDING' | 'DECLINED']> = [
    [2, 1, 'ACCEPTED'],
    [4, 3, 'PENDING'],
    [20, 21, 'DECLINED'],
  ];
  let interests = 0;
  for (const [from, to, status] of interestPairs) {
    await prisma.expressInterest.upsert({
      where: { senderId_receiverId: { senderId: id(from), receiverId: id(to) } },
      create: { senderId: id(from), receiverId: id(to), status },
      update: { status },
    });
    interests++;
  }

  const shortlistPairs: Array<[number, number]> = [[1, 6], [3, 22], [9, 10], [5, 16]];
  let shortlists = 0;
  for (const [owner, target] of shortlistPairs) {
    await prisma.shortlist.upsert({
      where: { userId_targetUserId: { userId: id(owner), targetUserId: id(target) } },
      create: { userId: id(owner), targetUserId: id(target) },
      update: {},
    });
    shortlists++;
  }

  // A block, so you can confirm blocked members vanish from Discover.
  await prisma.userBlock.upsert({
    where: { blockerId_blockedUserId: { blockerId: id(7), blockedUserId: id(18) } },
    create: { blockerId: id(7), blockedUserId: id(18) },
    update: {},
  });

  // A report. No natural key, so guard on an existing row.
  const existingReport = await prisma.userReport.findFirst({
    where: { reporterId: id(11), reportedUserId: id(26) },
    select: { id: true },
  });
  if (!existingReport) {
    await prisma.userReport.create({
      data: {
        reporterId: id(11),
        reportedUserId: id(26),
        reason: 'FAKE_PROFILE',
        description: 'Seeded test report.',
        status: 'OPEN',
      },
    });
  }

  // Two conversations, only between members whose interest was ACCEPTED or who
  // shortlisted each other — mirroring the app's own gating.
  const conversationPairs: Array<[number, number]> = [[1, 2], [9, 10]];
  let conversations = 0;
  let messages = 0;
  for (const [a, b] of conversationPairs) {
    // ChatRoom's unique key is (user1Id, user2Id); order it consistently so a
    // re-run finds the same room rather than creating its mirror image.
    const [u1, u2] = [id(a), id(b)].sort();
    const room = await prisma.chatRoom.upsert({
      where: { user1Id_user2Id: { user1Id: u1, user2Id: u2 } },
      create: { user1Id: u1, user2Id: u2 },
      update: {},
      select: { id: true },
    });
    conversations++;

    const script: Array<[number, string, boolean]> = [
      [a, 'Hi! Thanks for accepting my interest.', true],
      [b, 'Hello — happy to connect. How was your week?', true],
      [a, 'Busy but good. Are you free to talk this weekend?', false],
    ];
    for (const [senderIdx, content, isRead] of script) {
      const clientMessageId = `seed-msg-${a}-${b}-${messages}`;
      await prisma.chatMessage.upsert({
        where: {
          senderId_clientMessageId: { senderId: id(senderIdx), clientMessageId },
        },
        create: {
          roomId: room.id,
          senderId: id(senderIdx),
          clientMessageId,
          content,
          type: 'TEXT',
          status: isRead ? 'READ' : 'DELIVERED',
          isRead,
        },
        update: { content, isRead, status: isRead ? 'READ' : 'DELIVERED' },
      });
      messages++;
    }
    await prisma.chatRoom.update({
      where: { id: room.id },
      data: { lastMessageAt: new Date() },
    });
  }

  // A few notifications, including one unread, so the badge has something to
  // show. No natural key on Notification — guard on (userId, type).
  const notificationSpecs: Array<[number, 'INTEREST_RECEIVED' | 'PROFILE_VIEW' | 'NEW_MESSAGE', string, string, boolean]> = [
    [1, 'INTEREST_RECEIVED', 'New interest received', 'Someone is interested in your profile.', false],
    [1, 'PROFILE_VIEW', 'Someone viewed your profile', 'Your profile was viewed.', true],
    [3, 'INTEREST_RECEIVED', 'New interest received', 'Someone is interested in your profile.', false],
  ];
  let notifications = 0;
  for (const [idx, type, title, body, isRead] of notificationSpecs) {
    const existing = await prisma.notification.findFirst({
      where: { userId: id(idx), type },
      select: { id: true },
    });
    if (!existing) {
      await prisma.notification.create({
        data: { userId: id(idx), type, title, body, isRead, data: {} },
      });
    }
    notifications++;
  }

  return { interests, shortlists, blocks: 1, reports: 1, conversations, messages, notifications };
}

export async function seedFakeProfiles(
  prisma: PrismaClient,
  storage: PhotoStorageConfig | null,
  log: (msg: string) => void = console.log,
): Promise<SeedReport> {
  const report: SeedReport = {
    users: 0, profiles: 0, preferences: 0, settings: 0, registrationSteps: 0,
    photos: 0, photosUploaded: 0, photosAlreadyPresent: 0,
    interests: 0, shortlists: 0, blocks: 0, reports: 0,
    conversations: 0, messages: 0, notifications: 0,
    storageSkipped: storage === null,
  };

  if (!storage) {
    log('  ! S3 is not configured — seeding members without photos.');
    log('    Set AWS_REGION / AWS_S3_BUCKET_NAME / AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY');
    log('    and re-run to attach them; the seeder is idempotent.');
  }

  const client = storage ? makeS3Client(storage) : null;
  const ids = new Map<number, string>();

  for (const person of FAKE_PEOPLE) {
    // The user row must exist before the photo key can be built (the key
    // embeds the user id, exactly as PhotoService.buildKey does), so this runs
    // in two passes for members that are new.
    const bootstrapId = await seedPerson(prisma, person, null);
    ids.set(person.index, bootstrapId);
    report.users++;
    report.profiles++;
    report.preferences++;
    report.settings++;
    report.registrationSteps++;

    if (storage && client) {
      const uploaded = await uploadFakePhoto(storage, client, bootstrapId, person.index);
      await seedPerson(prisma, person, uploaded);
      report.photos++;
      if (uploaded.uploaded) report.photosUploaded++;
      else report.photosAlreadyPresent++;
    }

    log(
      `  ${String(person.index).padStart(2, '0')}  ${`${person.firstName} ${person.lastName}`.padEnd(26)} ` +
        `${person.gender.padEnd(6)} ${String(person.age).padStart(2)}  ${person.currentCity}`,
    );
  }

  const rel = await seedRelationships(prisma, ids);
  Object.assign(report, rel);
  return report;
}
