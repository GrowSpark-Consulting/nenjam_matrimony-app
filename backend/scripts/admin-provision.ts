/**
 * Provision and manage admin-panel staff accounts — the only way to create an
 * admin or change roles until the admin panel's own role screens exist.
 *
 *   pnpm admin:provision list
 *   pnpm admin:provision grant <email> <ROLE_KEY> --reason "..." --yes
 *   pnpm admin:provision revoke <email> <ROLE_KEY> --reason "..." --yes
 *   pnpm admin:provision reset-mfa <email> --reason "..." --yes
 *   pnpm admin:provision deactivate <email> --reason "..." --yes
 *
 * Before `grant`: create the person's Firebase account (Firebase console →
 * Authentication → Add user, email + password) with a dedicated staff email —
 * never a member's own account. `grant` links that account, switches the
 * admin on, adds the role and prints a ONE-TIME enrolment code (valid 24 h).
 * Give the code to the person out of band; they enter it in the admin panel to
 * set up their authenticator app. It is never shown again (only its hash is
 * stored); `reset-mfa` issues a new one.
 *
 * Writes need --yes, and print the target database host first: this runs
 * against whatever DATABASE_URL points at. Every write is audited with the
 * reason. No secrets are printed except that one-time code.
 */
import { config } from 'dotenv';
config({ path: '.env' });
config({ path: '.env.local', override: true });

import { Logger, Module } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppConfigModule } from '@app/config';
import { PrismaModule, PrismaService } from '@app/database';
import { RedisModule, RedisService } from '@app/cache';
import { FirebaseModule, FirebaseService } from '@app/firebase';
import { invalidateCachedUserId } from '@app/common';
import {
  deactivateAdmin,
  grantAdminRole,
  listAdmins,
  ProvisioningError,
  resetAdminMfa,
  revokeAdminRole,
} from '../apps/api/src/modules/admin/provisioning/admin-provisioning';

@Module({
  imports: [AppConfigModule, PrismaModule, RedisModule, FirebaseModule],
})
class AdminProvisionModule {}

const USAGE = `
  Usage:
    pnpm admin:provision list
    pnpm admin:provision grant <email> <ROLE_KEY> --reason "..." --yes
    pnpm admin:provision revoke <email> <ROLE_KEY> --reason "..." --yes
    pnpm admin:provision reset-mfa <email> --reason "..." --yes
    pnpm admin:provision deactivate <email> --reason "..." --yes
`;

function fail(message: string): never {
  console.error(`${message}\n${USAGE}`);
  process.exit(1);
}

function parseArgs(argv: string[]) {
  const positional: string[] = [];
  let reason = '';
  let yes = false;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--yes') yes = true;
    else if (arg === '--reason') reason = argv[++i] ?? '';
    else positional.push(arg);
  }
  return { positional, reason, yes };
}

/** host/database of DATABASE_URL — never the credentials. */
function databaseTarget(): string {
  try {
    const url = new URL(process.env.DATABASE_URL ?? '');
    return `${url.hostname}${url.pathname}`;
  } catch {
    return '(DATABASE_URL not set or unparseable)';
  }
}

async function main(): Promise<void> {
  const { positional, reason, yes } = parseArgs(process.argv.slice(2));
  const [command, email, roleKey] = positional;
  if (!command) fail('A command is required.');

  const writes = command !== 'list';
  const target = databaseTarget();
  console.log(`Database: ${target}`);
  if (writes && !yes) {
    fail(`Nothing changed. Re-run with --yes to apply this to ${target}.`);
  }

  Logger.overrideLogger(['error']);
  const app = await NestFactory.createApplicationContext(AdminProvisionModule, {
    logger: ['error'],
  });

  try {
    const prisma = app.get(PrismaService);

    switch (command) {
      case 'list': {
        console.table(await listAdmins(prisma));
        break;
      }
      case 'grant': {
        if (!email || !roleKey) fail('grant needs <email> <ROLE_KEY>.');
        const firebase = app.get(FirebaseService);
        const account = await firebase.findUserByEmail(email);
        if (!account) {
          fail(
            `No Firebase account for ${email}. Create it in the Firebase ` +
              'console (Authentication → Add user) first.',
          );
        }
        if (account.disabled)
          fail(`The Firebase account for ${email} is disabled.`);
        if (account.hasPhone) {
          fail(
            `The Firebase account for ${email} has a phone number, so it is ` +
              'a member-style account. Use a dedicated email-only staff account.',
          );
        }
        const result = await grantAdminRole(prisma, {
          firebaseUid: account.uid,
          email,
          roleKey: roleKey.toUpperCase(),
          reason,
        });
        // The auth guard caches each uid's status; drop it so the new
        // ACTIVE status applies on the very next request.
        await invalidateCachedUserId(app.get(RedisService), account.uid);
        console.log(
          `Admin ${email}: ${result.createdUser ? 'created' : 'updated'}, ` +
            `role ${roleKey.toUpperCase()} ${result.roleAdded ? 'added' : 'already held'}.`,
        );
        if (!account.emailVerified) {
          console.log(
            'Note: Firebase reports this email as unverified. Make sure you ' +
              'created this account yourself.',
          );
        }
        printEnrollmentCode(result.enrollmentCode);
        break;
      }
      case 'revoke': {
        if (!email || !roleKey) fail('revoke needs <email> <ROLE_KEY>.');
        const { removed } = await revokeAdminRole(prisma, {
          email,
          roleKey: roleKey.toUpperCase(),
          reason,
        });
        console.log(
          removed
            ? `Removed ${roleKey.toUpperCase()} from ${email}.`
            : `${email} did not hold ${roleKey.toUpperCase()}. Nothing removed.`,
        );
        break;
      }
      case 'reset-mfa': {
        if (!email) fail('reset-mfa needs <email>.');
        const { enrollmentCode, sessionsEnded } = await resetAdminMfa(prisma, {
          email,
          reason,
        });
        console.log(
          `Authenticator cleared; ${sessionsEnded} session(s) ended.`,
        );
        printEnrollmentCode(enrollmentCode);
        break;
      }
      case 'deactivate': {
        if (!email) fail('deactivate needs <email>.');
        const { sessionsEnded } = await deactivateAdmin(prisma, {
          email,
          reason,
        });
        console.log(`${email} deactivated; ${sessionsEnded} session(s) ended.`);
        break;
      }
      default:
        fail(`Unknown command "${command}".`);
    }
  } catch (error) {
    if (error instanceof ProvisioningError) fail(error.message);
    throw error;
  } finally {
    await app.close();
  }
}

function printEnrollmentCode(code: string | null): void {
  if (!code) {
    console.log('Authenticator already enrolled; no enrolment code issued.');
    return;
  }
  console.log(
    `\nOne-time enrolment code (valid 24 hours, shown only now):\n\n    ${code}\n\n` +
      'Give it to the admin privately. They enter it in the admin panel to ' +
      'set up their authenticator app.',
  );
}

main().catch((error: unknown) => {
  console.error((error as Error).message);
  process.exit(1);
});
