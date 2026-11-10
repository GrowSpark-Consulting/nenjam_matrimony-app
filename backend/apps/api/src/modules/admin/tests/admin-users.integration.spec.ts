import { INestApplication, Logger } from '@nestjs/common';
import request from 'supertest';
import type { App } from 'supertest/types';
import type { PrismaClient } from '@app/database';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from '../../profiles/tests/integration-schema-guard';
import { AdminModule } from '../admin.module';
import {
  createAdminTestApp,
  freshCode,
  provisionAndEnrol,
  type TestPerson,
} from './admin-test-harness';

/**
 * End-to-end integration tests for Admin User Management over HTTP:
 * - Listing & server-side pagination / search / filters
 * - Aggregated dashboard statistics
 * - User profile details with 9-tab structure and masked PII
 * - User blocking & unblocking with transactional audit logging and cache invalidation
 * - PII reveal with step-up MFA and audit records
 * - Internal staff notes
 * - RBAC permissions and error boundaries
 */
describeIntegration('Admin User Management HTTP API', () => {
  jest.setTimeout(90_000);
  let app: INestApplication<App>;
  let prisma: PrismaClient;

  const DOMAIN = '@admin-users-itest.local';
  const VIEWER_ROLE = 'ITEST_USER_VIEWER';

  const people: Record<string, TestPerson> = {
    alice: { uid: 'adm-usr-alice', email: `alice${DOMAIN}` },
    viewer: { uid: 'adm-usr-viewer', email: `viewer${DOMAIN}` },
    member: { uid: 'adm-usr-target-member', email: `target${DOMAIN}` },
    blockedMember: { uid: 'adm-usr-blocked-member', email: `blocked${DOMAIN}` },
  };

  const sessions: Record<string, string> = {};
  const secrets: Record<string, string> = {};
  let targetMemberId: string;
  let blockedMemberId: string;

  const http = () => request(app.getHttpServer());
  const as = (who: string) => ({
    Authorization: `Bearer ${who}`,
    'X-Admin-Session': sessions[who] ?? '',
  });

  async function cleanup() {
    const users = await prisma.user.findMany({
      where: { email: { endsWith: DOMAIN } },
      select: { id: true },
    });
    const ids = users.map((u) => u.id);

    if (ids.length > 0) {
      await prisma.memberNote.deleteMany({ where: { userId: { in: ids } } });
      await prisma.auditLog.deleteMany({
        where: { OR: [{ actorId: { in: ids } }, { entityId: { in: ids } }] },
      });
      await prisma.userProfile.deleteMany({ where: { userId: { in: ids } } });
      await prisma.userSubscription.deleteMany({
        where: { userId: { in: ids } },
      });
      await prisma.adminSession.deleteMany({
        where: { adminAccount: { user: { id: { in: ids } } } },
      });
      await prisma.adminUserRole.deleteMany({
        where: { adminAccount: { user: { id: { in: ids } } } },
      });
      await prisma.adminAccount.deleteMany({ where: { userId: { in: ids } } });
      await prisma.user.deleteMany({ where: { id: { in: ids } } });
    }
    await prisma.rolePermission.deleteMany({
      where: { role: { key: VIEWER_ROLE } },
    });
    await prisma.role.deleteMany({ where: { key: VIEWER_ROLE } });
  }

  beforeAll(async () => {
    jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);

    prisma = await connectIsolatedPrisma();
    await cleanup();

    app = await createAdminTestApp(prisma, people, [AdminModule]);

    // Create a restricted role with only 'member.view' permission
    const viewerRole = await prisma.role.create({
      data: { key: VIEWER_ROLE, name: 'User Directory Viewer' },
    });
    const memberViewPerm = await prisma.permission.findUniqueOrThrow({
      where: { key: 'member.view' },
    });
    await prisma.rolePermission.create({
      data: { roleId: viewerRole.id, permissionId: memberViewPerm.id },
    });

    // Provision admins: Alice (SUPER_ADMIN) and Viewer (VIEWER_ROLE)
    for (const [who, role] of [
      ['alice', 'SUPER_ADMIN'],
      ['viewer', VIEWER_ROLE],
    ] as const) {
      const res = await provisionAndEnrol(
        app,
        prisma,
        who,
        people[who],
        role,
      );
      sessions[who] = res.session;
      secrets[who] = res.secret;
    }

    // Seed an active member profile for testing
    const targetUser = await prisma.user.create({
      data: {
        firebaseUid: people.member.uid,
        email: people.member.email,
        phone: '+919876543210',
        status: 'ACTIVE',
        profile: {
          create: {
            firstName: 'Karthik',
            lastName: 'Raman',
            gender: 'MALE',
            dob: new Date('1992-06-15T00:00:00.000Z'),
            currentCity: 'Chennai',
            currentState: 'Tamil Nadu',
            country: 'India',
            isProfileComplete: true,
            profileCompletePct: 100,
          },
        },
      },
    });
    targetMemberId = targetUser.id;

    // Seed an already blocked member
    const blockedUser = await prisma.user.create({
      data: {
        firebaseUid: people.blockedMember.uid,
        email: people.blockedMember.email,
        phone: '+919876500000',
        status: 'BLOCKED',
        profile: {
          create: {
            firstName: 'Banned',
            lastName: 'User',
            gender: 'MALE',
            isProfileComplete: false,
          },
        },
      },
    });
    blockedMemberId = blockedUser.id;
  });

  afterAll(async () => {
    await cleanup();
    await app?.close();
  });

  describe('GET /admin/users (Directory & Filtering)', () => {
    it('returns paginated users when authorized with member.view', async () => {
      const res = await http()
        .get('/admin/users?page=1&limit=10')
        .set(as('viewer'))
        .expect(200);

      expect(res.body).toHaveProperty('items');
      expect(res.body).toHaveProperty('total');
      expect(res.body).toHaveProperty('page', 1);
      expect(res.body).toHaveProperty('limit', 10);
      expect(Array.isArray(res.body.items)).toBe(true);

      const target = res.body.items.find(
        (u: { id: string }) => u.id === targetMemberId,
      );
      expect(target).toBeDefined();
      expect(target.fullName).toBe('Karthik Raman');
      expect(target.phone).toContain('***'); // Masked by default
    });

    it('filters users by search text (email/name/phone)', async () => {
      const res = await http()
        .get('/admin/users?search=Karthik')
        .set(as('alice'))
        .expect(200);

      expect(res.body.items.some((u: { id: string }) => u.id === targetMemberId)).toBe(true);
    });

    it('filters users by account status', async () => {
      const res = await http()
        .get('/admin/users?status=BLOCKED')
        .set(as('alice'))
        .expect(200);

      expect(res.body.items.some((u: { id: string }) => u.id === blockedMemberId)).toBe(true);
      expect(res.body.items.every((u: { accountStatus: string }) => u.accountStatus === 'BLOCKED')).toBe(true);
    });

    it('rejects invalid query parameters with 400', async () => {
      await http()
        .get('/admin/users?gender=OTHER')
        .set(as('alice'))
        .expect(400);

      await http()
        .get('/admin/users?limit=500')
        .set(as('alice'))
        .expect(400);
    });

    it('refuses access when unauthenticated (401)', async () => {
      await http().get('/admin/users').expect(401);
    });
  });

  describe('GET /admin/users/stats (Statistics)', () => {
    it('returns aggregate user statistics', async () => {
      const res = await http()
        .get('/admin/users/stats')
        .set(as('viewer'))
        .expect(200);

      expect(res.body).toHaveProperty('totalUsers');
      expect(res.body).toHaveProperty('activeUsers');
      expect(res.body).toHaveProperty('blockedUsers');
      expect(res.body).toHaveProperty('registeredToday');
      expect(res.body).toHaveProperty('incompleteProfiles');
      expect(res.body).toHaveProperty('premiumMembers');
      expect(typeof res.body.totalUsers).toBe('number');
      expect(typeof res.body.blockedUsers).toBe('number');
    });
  });

  describe('GET /admin/users/:id (User Details)', () => {
    it('returns full 9-tab profile details with masked contact info', async () => {
      const res = await http()
        .get(`/admin/users/${targetMemberId}`)
        .set(as('viewer'))
        .expect(200);

      expect(res.body.id).toBe(targetMemberId);
      expect(res.body).toHaveProperty('basicInfo');
      expect(res.body).toHaveProperty('contactInfo');
      expect(res.body).toHaveProperty('careerAndFamily');
      expect(res.body).toHaveProperty('partnerPreferences');
      expect(res.body).toHaveProperty('astrologyProfile');
      expect(res.body).toHaveProperty('membership');
      expect(res.body).toHaveProperty('photosAndMedia');
      expect(res.body).toHaveProperty('internalNotes');
      expect(res.body).toHaveProperty('accountActivity');

      expect(res.body.contactInfo.isPhoneMasked).toBe(true);
      expect(res.body.contactInfo.isEmailMasked).toBe(true);
      expect(res.body.contactInfo.phone).toContain('***');
    });

    it('returns 400 for an invalid UUID', async () => {
      await http()
        .get('/admin/users/invalid-uuid')
        .set(as('alice'))
        .expect(400);
    });

    it('returns 404 for a nonexistent user ID', async () => {
      await http()
        .get('/admin/users/00000000-0000-0000-0000-000000000000')
        .set(as('alice'))
        .expect(404);
    });
  });

  describe('PATCH /admin/users/:id/block and unblock', () => {
    it('refuses block without member.suspend permission (403)', async () => {
      const res = await http()
        .patch(`/admin/users/${targetMemberId}/block`)
        .set(as('viewer'))
        .send({ reason: 'Terms of service violation' })
        .expect(403);

      expect(res.body.code).toBe('ADMIN_PERMISSION_DENIED');
      expect(res.body.missing).toContain('member.suspend');
    });

    it('blocks an active user and creates audit log', async () => {
      const res = await http()
        .patch(`/admin/users/${targetMemberId}/block`)
        .set(as('alice'))
        .send({ reason: 'Fraudulent profile activity' })
        .expect(200);

      expect(res.body.success).toBe(true);
      expect(res.body.status).toBe('BLOCKED');
      expect(res.body.previousStatus).toBe('ACTIVE');

      const user = await prisma.user.findUnique({
        where: { id: targetMemberId },
      });
      expect(user?.status).toBe('BLOCKED');

      const audit = await prisma.auditLog.findFirst({
        where: { entityId: targetMemberId, action: 'member.block' },
      });
      expect(audit).toBeDefined();
      expect(audit?.reason).toBe('Fraudulent profile activity');
    });

    it('refuses blocking an already blocked user with 409 Conflict', async () => {
      await http()
        .patch(`/admin/users/${targetMemberId}/block`)
        .set(as('alice'))
        .send({ reason: 'Another violation attempt' })
        .expect(409);
    });

    it('rejects block without a valid reason (minimum 3 characters)', async () => {
      await http()
        .patch(`/admin/users/${targetMemberId}/block`)
        .set(as('alice'))
        .send({ reason: 'no' })
        .expect(400);
    });

    it('unblocks a blocked user and restores ACTIVE status', async () => {
      const res = await http()
        .patch(`/admin/users/${targetMemberId}/unblock`)
        .set(as('alice'))
        .send({ reason: 'Verification proof submitted' })
        .expect(200);

      expect(res.body.success).toBe(true);
      expect(res.body.status).toBe('ACTIVE');
      expect(res.body.previousStatus).toBe('BLOCKED');

      const user = await prisma.user.findUnique({
        where: { id: targetMemberId },
      });
      expect(user?.status).toBe('ACTIVE');

      const audit = await prisma.auditLog.findFirst({
        where: { entityId: targetMemberId, action: 'member.unblock' },
      });
      expect(audit).toBeDefined();
    });

    it('refuses unblocking a user who is not blocked (400)', async () => {
      await http()
        .patch(`/admin/users/${targetMemberId}/unblock`)
        .set(as('alice'))
        .send({ reason: 'Already active' })
        .expect(400);
    });
  });

  describe('POST /admin/users/:id/reveal-pii (Sensitive Step-Up)', () => {
    it('reveals unmasked PII and records member.pii.reveal audit', async () => {
      const res = await http()
        .post(`/admin/users/${targetMemberId}/reveal-pii`)
        .set(as('alice'))
        .send({ reason: 'Law enforcement request' })
        .expect(200);

      expect(res.body.userId).toBe(targetMemberId);
      expect(res.body.phone).toBe('+919876543210');
      expect(res.body.email).toBe(people.member.email);

      const audit = await prisma.auditLog.findFirst({
        where: { entityId: targetMemberId, action: 'member.pii.reveal' },
      });
      expect(audit).toBeDefined();
    });

    it('denies reveal when missing member.pii.reveal permission (403)', async () => {
      await http()
        .post(`/admin/users/${targetMemberId}/reveal-pii`)
        .set(as('viewer'))
        .send({ reason: 'Attempt reveal' })
        .expect(403);
    });

    it('enforces fresh TOTP step-up check (401 if step-up is stale)', async () => {
      // Age the MFA verification time beyond the 10-minute threshold
      const admin = await prisma.adminAccount.findFirstOrThrow({
        where: { user: { email: people.alice.email } },
      });
      await prisma.adminSession.updateMany({
        where: { adminAccountId: admin.id, revokedAt: null },
        data: { mfaVerifiedAt: new Date(Date.now() - 15 * 60_000) },
      });

      const stale = await http()
        .post(`/admin/users/${targetMemberId}/reveal-pii`)
        .set(as('alice'))
        .send({ reason: 'MFA check test' })
        .expect(401);

      expect(stale.body.code).toBe('ADMIN_STEP_UP_REQUIRED');

      // Refresh step-up using fresh TOTP code
      const code = await freshCode(prisma, people.alice.email, secrets.alice);
      await http()
        .post('/admin/auth/step-up')
        .set(as('alice'))
        .send({ code })
        .expect(200);

      // Subsequent reveal request succeeds
      await http()
        .post(`/admin/users/${targetMemberId}/reveal-pii`)
        .set(as('alice'))
        .send({ reason: 'Refreshed reveal' })
        .expect(200);
    });
  });

  describe('POST /admin/users/:id/notes (Internal Staff Notes)', () => {
    it('creates an internal note on the member profile', async () => {
      const res = await http()
        .post(`/admin/users/${targetMemberId}/notes`)
        .set(as('viewer'))
        .send({ note: 'Called candidate, documents verified by phone.' })
        .expect(201);

      expect(res.body).toHaveProperty('id');
      expect(res.body.userId).toBe(targetMemberId);
      expect(res.body.note).toBe('Called candidate, documents verified by phone.');
      expect(res.body.authorName).toBe(people.viewer.email);
    });

    it('rejects empty note with 400', async () => {
      await http()
        .post(`/admin/users/${targetMemberId}/notes`)
        .set(as('viewer'))
        .send({ note: '' })
        .expect(400);
    });
  });
});
