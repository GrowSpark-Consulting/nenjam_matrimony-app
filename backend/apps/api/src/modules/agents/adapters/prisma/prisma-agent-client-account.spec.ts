import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { InternalServerErrorException } from '@nestjs/common';
import type { PrismaClient } from '@app/database';
import { AgentConfigError } from '../../config/agent-config.service';
import { PrismaAgentClientAccount } from './prisma-agent-client-account';

const PHONE = '+919000000001';

function make(firebase: {
  findOrCreateUser?: () => Promise<{ uid: string; created: boolean }>;
  createCustomToken?: () => Promise<string>;
}) {
  return new PrismaAgentClientAccount({} as PrismaClient, {
    findOrCreateUser:
      firebase.findOrCreateUser ??
      (() => Promise.resolve({ uid: 'uid-1', created: true })),
    createCustomToken:
      firebase.createCustomToken ?? (() => Promise.resolve('custom-token')),
  });
}

const notConfigured = () =>
  Promise.reject(
    new InternalServerErrorException(
      'Firebase Admin SDK is not configured on this server.',
    ),
  );

describe('PrismaAgentClientAccount and Firebase', () => {
  it('passes the Firebase account and the custom token through', async () => {
    const account = make({});
    await expect(account.ensureFirebaseUser(PHONE)).resolves.toEqual({
      uid: 'uid-1',
    });
    await expect(account.mintSessionToken('uid-1')).resolves.toBe(
      'custom-token',
    );
  });

  it('missing Firebase credentials are a 503 (AgentConfigError naming the source), not a 500', async () => {
    const account = make({
      findOrCreateUser: notConfigured,
      createCustomToken: notConfigured,
    });
    for (const call of [
      () => account.ensureFirebaseUser(PHONE),
      () => account.mintSessionToken('uid-1'),
    ]) {
      const error = await call().catch((e: unknown) => e);
      expect(error).toBeInstanceOf(AgentConfigError);
      expect((error as AgentConfigError).missing).toEqual([
        'Firebase Admin credentials (FIREBASE_*)',
      ]);
    }
  });

  it('any other Firebase failure passes through unchanged', async () => {
    const boom = new Error('Firebase createUser timed out.');
    await expect(
      make({ findOrCreateUser: () => Promise.reject(boom) }).ensureFirebaseUser(
        PHONE,
      ),
    ).rejects.toBe(boom);
  });

  it('matches what FirebaseService really says when it is not configured', () => {
    const source = readFileSync(
      join(
        __dirname,
        '../../../../../../../libs/firebase/src/firebase.service.ts',
      ),
      'utf8',
    );
    expect(source).toContain(
      "'Firebase Admin SDK is not configured on this server.'",
    );
  });
});
