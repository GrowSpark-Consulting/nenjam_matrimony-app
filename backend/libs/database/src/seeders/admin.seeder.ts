import { PrismaClient } from '../../generated/client';

/**
 * Seeds the default platform administrator account.
 *
 * ⚠️  IMPORTANT — Firebase Auth step (manual):
 *   This seeder only creates the PostgreSQL records.
 *   Before going to production you MUST also:
 *   1. Create admin@nenjammatrimony.com in Firebase Console →
 *      Authentication → Users → Add user
 *   2. Copy the generated Firebase UID and replace the placeholder
 *      ADMIN_FIREBASE_UID below with the real value.
 *
 * In development the placeholder is fine — the API will not be
 * called with admin credentials until the Firebase account exists.
 */

const ADMIN_FIREBASE_UID = 'admin-seed-placeholder-uid-001';
const ADMIN_EMAIL = 'admin@nenjammatrimony.com';
const ADMIN_PHONE = '+919999999999';

const ADMIN_PERMISSIONS = {
  users: ['read', 'write', 'suspend', 'ban', 'delete'],
  subscriptions: ['read', 'write', 'cancel'],
  reports: ['read', 'write', 'resolve', 'dismiss'],
  kyc: ['read', 'approve', 'reject'],
  support: ['read', 'write', 'resolve', 'close'],
  audit: ['read'],
  content: ['read', 'write', 'delete'],
};

export async function seedAdmin(prisma: PrismaClient): Promise<void> {
  console.log('\n👤  Seeding default admin account…');

  // 1. Upsert the User record (role = ADMIN)
  const user = await prisma.user.upsert({
    where: { email: ADMIN_EMAIL },
    update: {
      firebaseUid: ADMIN_FIREBASE_UID,
      phone: ADMIN_PHONE,
      role: 'ADMIN',
      status: 'ACTIVE',
      trustScore: 100,
    },
    create: {
      firebaseUid: ADMIN_FIREBASE_UID,
      email: ADMIN_EMAIL,
      phone: ADMIN_PHONE,
      role: 'ADMIN',
      status: 'ACTIVE',
      trustScore: 100,
    },
  });

  console.log(
    `  ✅  User record: ${user.email}  role=${user.role}  [id: ${user.id}]`,
  );

  // 2. Upsert the AdminAccount extension record
  const adminAccount = await prisma.adminAccount.upsert({
    where: { userId: user.id },
    update: {
      department: 'PLATFORM',
      permissions: ADMIN_PERMISSIONS,
    },
    create: {
      userId: user.id,
      department: 'PLATFORM',
      permissions: ADMIN_PERMISSIONS,
    },
  });

  console.log(
    `  ✅  AdminAccount: department=${adminAccount.department}  [id: ${adminAccount.id}]`,
  );

  // 3. Log the permissions summary
  const permSummary = Object.entries(ADMIN_PERMISSIONS)
    .map(([module, actions]) => `      ${module}: [${actions.join(', ')}]`)
    .join('\n');

  console.log(`  📋  Permissions granted:\n${permSummary}`);
  console.log('');
  console.log(
    '  ⚠️   Remember: create the Firebase Auth account for',
  );
  console.log(
    `       ${ADMIN_EMAIL} in the Firebase Console and update`,
  );
  console.log(
    '       ADMIN_FIREBASE_UID in admin.seeder.ts before production.',
  );
}
