import type { PrismaClient } from '@app/database';
import { AgentActorAuditAdapter } from '../adapters/platform/agent-platform.adapters';
import {
  ageOnIstDate,
  PrismaAgentMemberRead,
} from '../adapters/prisma/prisma-agent-member-read';
import { AgentJwtTokenSigner } from '../auth/agent-jwt-token-signer';
import { buildAgentAccessClaims } from '../auth/agent-access-claims';
import { FakeAgentClock } from '../testing/fake-agent-infra';
import { FakeAgentIdentifierHasher } from '../testing/fake-agent-platform';
import { AGENT_ERROR_HTTP } from './agent-errors.filter';
import { refreshTokenPepperFrom, requesterKeyFor } from './agent-program';

const NOW = new Date('2026-10-29T10:00:00.000Z');

describe('AgentJwtTokenSigner.check', () => {
  const clock = new FakeAgentClock(NOW);
  const options = {
    secret: 'test-only-agent-jwt-secret-not-real-0000',
    issuer: 'iss',
    audience: 'aud',
  };
  const signer = new AgentJwtTokenSigner(options, clock);
  const claims = buildAgentAccessClaims({
    agentId: 'agent-1',
    phoneHash: 'h',
    scope: 'AGENT',
    now: NOW,
    ttlSeconds: 60,
    issuer: 'iss',
    audience: 'aud',
  });

  it('a genuine current token is ok; once expired it is EXPIRED, and verify is null', async () => {
    const token = await signer.sign(claims);
    await expect(signer.check(token)).resolves.toEqual({ ok: true, claims });
    clock.advance(60_000);
    await expect(signer.check(token)).resolves.toEqual({
      ok: false,
      reason: 'EXPIRED',
    });
    await expect(signer.verify(token)).resolves.toBeNull();
  });

  it('an expired token from another secret is INVALID, never EXPIRED', async () => {
    const other = new AgentJwtTokenSigner(
      { ...options, secret: 'another-test-only-secret-not-real-00000' },
      new FakeAgentClock(NOW),
    );
    const forged = await other.sign(claims);
    const later = new AgentJwtTokenSigner(
      options,
      new FakeAgentClock(new Date(NOW.getTime() + 3_600_000)),
    );
    await expect(later.check(forged)).resolves.toEqual({
      ok: false,
      reason: 'INVALID',
    });
    await expect(later.check('')).resolves.toEqual({
      ok: false,
      reason: 'INVALID',
    });
  });
});

describe('requesterKeyFor and refreshTokenPepperFrom', () => {
  it('hashes the IP; a missing or unreadable one shares an opaque bucket', () => {
    const hashing = { hashIdentifier: jest.fn().mockReturnValue('v1:abc') };
    expect(requesterKeyFor(hashing, '10.0.0.1')).toBe('v1:abc');
    expect(hashing.hashIdentifier).toHaveBeenCalledWith('IP', '10.0.0.1');
    expect(requesterKeyFor(hashing, undefined)).toBe('ip:unknown');
    hashing.hashIdentifier.mockImplementation(() => {
      throw new RangeError('not an IP');
    });
    expect(requesterKeyFor(hashing, 'x')).toBe('ip:unreadable');
    const unavailable = new Error('IDENTIFIER_HASHING_UNAVAILABLE');
    hashing.hashIdentifier.mockImplementation(() => {
      throw unavailable;
    });
    expect(() => requesterKeyFor(hashing, '10.0.0.1')).toThrow(unavailable);
  });

  it('the pepper is derived, stable, and never the secret itself', () => {
    const secret = 'test-only-agent-jwt-secret-not-real-0000';
    expect(refreshTokenPepperFrom(secret)).toBe(refreshTokenPepperFrom(secret));
    expect(refreshTokenPepperFrom(secret)).not.toContain(secret);
    expect(refreshTokenPepperFrom(secret)).not.toBe(
      refreshTokenPepperFrom(`${secret}x`),
    );
  });
});

describe('AgentActorAuditAdapter', () => {
  it('an entry with an actor is AGENT, without one SYSTEM, an explicit type wins', async () => {
    const record = jest
      .fn<Promise<void>, [{ actorType?: string }]>()
      .mockResolvedValue(undefined);
    const audit = new AgentActorAuditAdapter({ record });
    const base = { action: 'a', entity: 'E', entityId: null };
    await audit.record({ ...base, actorId: 'agent-1' });
    await audit.record({ ...base, actorId: null });
    await audit.record({ ...base, actorId: 'x', actorType: 'MEMBER' });
    expect(record.mock.calls.map((c) => c[0].actorType)).toEqual([
      'AGENT',
      'SYSTEM',
      'MEMBER',
    ]);
  });
});

describe('the error table', () => {
  it('every refusal has a 4xx status (only UNKNOWN_STATUS is a 500)', () => {
    for (const [code, m] of Object.entries(AGENT_ERROR_HTTP)) {
      expect([code, m.status >= 400 && m.status < 500]).toEqual([
        code,
        code !== 'UNKNOWN_STATUS',
      ]);
    }
    expect(AGENT_ERROR_HTTP.PHONE_ALREADY_REGISTERED.code).toBe(
      'APPLICATION_EXISTS',
    );
    expect(AGENT_ERROR_HTTP.REAPPLY_NOT_ALLOWED).toMatchObject({
      status: 403,
      code: 'AGENT_NOT_ACTIVE',
    });
  });
});

describe('PrismaAgentMemberRead', () => {
  const hasher = new FakeAgentIdentifierHasher('test-secret');
  const clock = new FakeAgentClock(NOW);
  function db(user: unknown, payment: unknown) {
    return {
      user: { findFirst: jest.fn().mockResolvedValue(user) },
      paymentTransaction: { findFirst: jest.fn().mockResolvedValue(payment) },
    } as unknown as PrismaClient;
  }

  it('a member with a phone has its newest-pepper hash; no phone is null', async () => {
    const signedUp = new Date('2026-10-01T00:00:00Z');
    const read = new PrismaAgentMemberRead(
      db({ id: 'm1', phone: '+919000000002', createdAt: signedUp }, null),
      hasher,
      clock,
    );
    await expect(read.getMember('m1')).resolves.toEqual({
      memberId: 'm1',
      phoneHash: hasher.hash('PHONE', '+919000000002'),
      signedUpAt: signedUp,
      hasPaid: false,
    });
    const nophone = new PrismaAgentMemberRead(
      db({ id: 'm2', phone: null, createdAt: signedUp }, { id: 'p' }),
      hasher,
      clock,
    );
    await expect(nophone.getMember('m2')).resolves.toMatchObject({
      phoneHash: null,
      hasPaid: true,
    });
    await expect(
      new PrismaAgentMemberRead(db(null, null), hasher, clock).getMember('x'),
    ).resolves.toBeNull();
  });

  it('view fields: PURCHASED with the first paid plan, else from the profile', async () => {
    const profile = {
      firstName: 'Priya',
      lastName: 'Sharma',
      dob: new Date('1999-10-30T00:00:00Z'),
      currentCity: 'Madurai',
      isProfileComplete: true,
      profileCompletePct: 80,
    };
    const user = { phone: '+919000000002', createdAt: NOW, profile };
    const paidAt = new Date('2026-10-20T00:00:00Z');
    const paid = new PrismaAgentMemberRead(
      db(user, { paidAt, subscription: { plan: { displayName: 'Gold' } } }),
      hasher,
      clock,
    );
    await expect(paid.getReferralViewFields('m1')).resolves.toMatchObject({
      stage: 'PURCHASED',
      planName: 'Gold',
      purchasedAt: paidAt,
      age: 26,
      profileCompletenessPct: 80,
    });
    const complete = new PrismaAgentMemberRead(db(user, null), hasher, clock);
    await expect(complete.getReferralViewFields('m1')).resolves.toMatchObject({
      stage: 'PROFILE_COMPLETE',
      planName: null,
    });
    const noProfile = new PrismaAgentMemberRead(
      db({ ...user, profile: null }, null),
      hasher,
      clock,
    );
    await expect(noProfile.getReferralViewFields('m1')).resolves.toBeNull();
  });

  it('age is the calendar age on the Indian date', () => {
    const dob = new Date('2000-10-30T00:00:00Z');
    // 29 Oct 18:30 UTC is already 30 Oct in India: the birthday.
    expect(ageOnIstDate(dob, new Date('2026-10-29T18:29:00Z'))).toBe(25);
    expect(ageOnIstDate(dob, new Date('2026-10-29T18:30:00Z'))).toBe(26);
  });
});
