import { createHmac } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import { FakeAgentClock } from '../testing/fake-agent-infra';
import {
  AgentAccessClaims,
  buildAgentAccessClaims,
} from './agent-access-claims';
import {
  AgentJwtTokenSigner,
  MIN_AGENT_JWT_SECRET_LENGTH,
} from './agent-jwt-token-signer';

// Test-only values, not secrets.
const SECRET = 'a'.repeat(32) + '-agent-test-secret';
const OTHER_SECRET = 'b'.repeat(40);
const ISSUER = 'nenjam-agent';
const AUDIENCE = 'agent-portal';
const NOW = new Date('2026-10-28T10:00:00.000Z');

const claimsFor = (
  overrides: Partial<AgentAccessClaims> = {},
): AgentAccessClaims => ({
  ...buildAgentAccessClaims({
    agentId: 'agent-1',
    phoneHash: 'phone-hash',
    scope: 'AGENT',
    now: NOW,
    ttlSeconds: 900,
    issuer: ISSUER,
    audience: AUDIENCE,
  }),
  ...overrides,
});

const b64u = (value: unknown): string =>
  Buffer.from(
    typeof value === 'string' ? value : JSON.stringify(value),
  ).toString('base64url');

/** Builds a token by hand, so tests can use any header and any algorithm. */
function forge(
  header: Record<string, unknown>,
  payload: unknown,
  secret: string | null,
  hmac: 'sha256' | 'sha384' | 'sha512' = 'sha256',
): string {
  const signingInput = `${b64u(header)}.${b64u(payload)}`;
  const signature =
    secret === null
      ? ''
      : createHmac(hmac, secret).update(signingInput).digest('base64url');
  return `${signingInput}.${signature}`;
}

describe('AgentJwtTokenSigner', () => {
  let clock: FakeAgentClock;
  let signer: AgentJwtTokenSigner;
  const make = (secret = SECRET, issuer = ISSUER, audience = AUDIENCE) =>
    new AgentJwtTokenSigner({ secret, issuer, audience }, clock);

  beforeEach(() => {
    clock = new FakeAgentClock(NOW);
    signer = make();
  });

  describe('sign and verify', () => {
    it('round-trips agent claims', async () => {
      const claims = claimsFor();
      await expect(signer.verify(await signer.sign(claims))).resolves.toEqual(
        claims,
      );
    });

    it('round-trips applicant claims', async () => {
      const claims = buildAgentAccessClaims({
        agentId: null,
        phoneHash: 'phone-hash',
        scope: 'APPLICANT',
        now: NOW,
        ttlSeconds: 900,
        issuer: ISSUER,
        audience: AUDIENCE,
      });
      await expect(signer.verify(await signer.sign(claims))).resolves.toEqual(
        claims,
      );
    });

    it('produces a three-part token with an HS256 header', async () => {
      const token = await signer.sign(claimsFor());
      const [header] = token.split('.');
      expect(token.split('.')).toHaveLength(3);
      expect(
        JSON.parse(Buffer.from(header, 'base64url').toString()),
      ).toMatchObject({
        alg: 'HS256',
      });
    });

    it('the token does not contain the secret', async () => {
      const token = await signer.sign(claimsFor());
      expect(token).not.toContain(SECRET);
      expect(
        Buffer.from(token.split('.')[1], 'base64url').toString(),
      ).not.toContain(SECRET);
    });

    it('refuses to sign claims for another issuer or audience', async () => {
      await expect(
        signer.sign(claimsFor({ iss: 'someone-else' })),
      ).rejects.toThrow(RangeError);
      await expect(
        signer.sign(claimsFor({ aud: 'someone-else' })),
      ).rejects.toThrow(RangeError);
    });
  });

  describe('the algorithm is HS256 only', () => {
    const claims = () => claimsFor();

    it('refuses an unsigned token with alg "none"', async () => {
      const token = forge({ alg: 'none', typ: 'JWT' }, claims(), null);
      await expect(signer.verify(token)).resolves.toBeNull();
    });

    it.each(['None', 'NONE', 'nOnE'])(
      'refuses alg %p with an empty signature',
      async (alg) => {
        await expect(
          signer.verify(forge({ alg, typ: 'JWT' }, claims(), null)),
        ).resolves.toBeNull();
      },
    );

    it('refuses "none" even if the token carries a signature part', async () => {
      const token = forge({ alg: 'none', typ: 'JWT' }, claims(), SECRET);
      await expect(signer.verify(token)).resolves.toBeNull();
    });

    it('refuses HS512, even signed with the right secret', async () => {
      const viaLibrary = new JwtService({ secret: SECRET }).sign(
        { ...claims() },
        { algorithm: 'HS512' },
      );
      await expect(signer.verify(viaLibrary)).resolves.toBeNull();
      const forged = forge(
        { alg: 'HS512', typ: 'JWT' },
        claims(),
        SECRET,
        'sha512',
      );
      await expect(signer.verify(forged)).resolves.toBeNull();
    });

    it('refuses HS384, even signed with the right secret', async () => {
      const forged = forge(
        { alg: 'HS384', typ: 'JWT' },
        claims(),
        SECRET,
        'sha384',
      );
      await expect(signer.verify(forged)).resolves.toBeNull();
    });

    it('refuses an RS256 header (algorithm confusion)', async () => {
      const forged = forge({ alg: 'RS256', typ: 'JWT' }, claims(), SECRET);
      await expect(signer.verify(forged)).resolves.toBeNull();
    });

    it('refuses a lower-case "hs256" header', async () => {
      const forged = forge({ alg: 'hs256', typ: 'JWT' }, claims(), SECRET);
      await expect(signer.verify(forged)).resolves.toBeNull();
    });

    it('accepts a hand-built HS256 token signed with the right secret (control)', async () => {
      const forged = forge({ alg: 'HS256', typ: 'JWT' }, claims(), SECRET);
      await expect(signer.verify(forged)).resolves.toEqual(claims());
    });
  });

  describe('the signature', () => {
    it('refuses a token signed with another secret', async () => {
      const token = await make(OTHER_SECRET).sign(claimsFor());
      await expect(signer.verify(token)).resolves.toBeNull();
    });

    it('refuses a changed payload under the old signature', async () => {
      const [header, , signature] = (await signer.sign(claimsFor())).split('.');
      const forged = `${header}.${b64u(claimsFor({ sub: 'agent-2' }))}.${signature}`;
      await expect(signer.verify(forged)).resolves.toBeNull();
    });

    it('refuses a changed scope under the old signature', async () => {
      const [header, , signature] = (await signer.sign(claimsFor())).split('.');
      const forged = `${header}.${b64u(claimsFor({ scope: 'APPLICANT' }))}.${signature}`;
      await expect(signer.verify(forged)).resolves.toBeNull();
    });

    it('refuses a changed signature', async () => {
      const [header, payload, signature] = (
        await signer.sign(claimsFor())
      ).split('.');
      const flipped = signature.startsWith('A')
        ? `B${signature.slice(1)}`
        : `A${signature.slice(1)}`;
      await expect(
        signer.verify(`${header}.${payload}.${flipped}`),
      ).resolves.toBeNull();
    });

    it('refuses a missing or truncated signature', async () => {
      const [header, payload, signature] = (
        await signer.sign(claimsFor())
      ).split('.');
      await expect(signer.verify(`${header}.${payload}.`)).resolves.toBeNull();
      await expect(signer.verify(`${header}.${payload}`)).resolves.toBeNull();
      await expect(
        signer.verify(`${header}.${payload}.${signature.slice(0, 10)}`),
      ).resolves.toBeNull();
    });

    it.each(['', 'abc', 'a.b', 'a.b.c', '..', 'not a token', '{}', 'a.b.c.d'])(
      'refuses the garbage %p',
      async (token) => {
        await expect(signer.verify(token)).resolves.toBeNull();
      },
    );

    it.each([undefined, null, 42, {}, []])(
      'refuses a non-string %p',
      async (token) => {
        await expect(signer.verify(token as string)).resolves.toBeNull();
      },
    );
  });

  describe('the claims are checked after the signature', () => {
    const signedWith = (overrides: Partial<AgentAccessClaims>) =>
      forge({ alg: 'HS256', typ: 'JWT' }, claimsFor(overrides), SECRET);

    it('refuses another issuer', async () => {
      await expect(
        signer.verify(signedWith({ iss: 'someone-else' })),
      ).resolves.toBeNull();
    });

    it('refuses another audience', async () => {
      await expect(
        signer.verify(signedWith({ aud: 'someone-else' })),
      ).resolves.toBeNull();
    });

    it('refuses a token signed by a signer for another issuer or audience (same secret)', async () => {
      const token = await make(SECRET, 'other-issuer', AUDIENCE).sign(
        claimsFor({ iss: 'other-issuer' }),
      );
      await expect(signer.verify(token)).resolves.toBeNull();
      const token2 = await make(SECRET, ISSUER, 'other-audience').sign(
        claimsFor({ aud: 'other-audience' }),
      );
      await expect(signer.verify(token2)).resolves.toBeNull();
    });

    it('refuses an unknown scope', async () => {
      await expect(
        signer.verify(signedWith({ scope: 'ADMIN' as never })),
      ).resolves.toBeNull();
    });

    it('refuses an expired token, using our clock, from the second it expires', async () => {
      const token = await signer.sign(claimsFor());
      clock.set(new Date(NOW.getTime() + 899_000));
      await expect(signer.verify(token)).resolves.not.toBeNull();
      clock.set(new Date(NOW.getTime() + 900_000));
      await expect(signer.verify(token)).resolves.toBeNull();
    });

    it('refuses a token that is not valid yet', async () => {
      const future = claimsFor({
        iat: Math.floor(NOW.getTime() / 1000) + 3600,
        exp: Math.floor(NOW.getTime() / 1000) + 4500,
      });
      await expect(
        signer.verify(forge({ alg: 'HS256', typ: 'JWT' }, future, SECRET)),
      ).resolves.toBeNull();
    });

    it('refuses a payload that is not an object or lacks claims', async () => {
      for (const payload of ['x', 7, [], null, { sub: 'a' }]) {
        await expect(
          signer.verify(forge({ alg: 'HS256', typ: 'JWT' }, payload, SECRET)),
        ).resolves.toBeNull();
      }
    });

    it('returns only the known claims, dropping extras', async () => {
      const token = forge(
        { alg: 'HS256', typ: 'JWT' },
        { ...claimsFor(), role: 'admin', isAdmin: true },
        SECRET,
      );
      const verified = await signer.verify(token);
      expect(verified).toEqual(claimsFor());
      expect(verified).not.toHaveProperty('role');
    });
  });

  describe('construction', () => {
    it(`refuses a secret shorter than ${MIN_AGENT_JWT_SECRET_LENGTH} characters`, () => {
      expect(() => make('x'.repeat(MIN_AGENT_JWT_SECRET_LENGTH - 1))).toThrow(
        RangeError,
      );
      expect(() => make('')).toThrow(RangeError);
    });

    it('accepts exactly the minimum length', () => {
      expect(() => make('x'.repeat(MIN_AGENT_JWT_SECRET_LENGTH))).not.toThrow();
    });

    it('refuses an empty issuer or audience', () => {
      expect(() => make(SECRET, '', AUDIENCE)).toThrow(RangeError);
      expect(() => make(SECRET, ISSUER, '')).toThrow(RangeError);
    });

    it('never puts the secret in an error message', () => {
      const short = 'sh0rt-s3cret-value';
      let message = '';
      try {
        make(short);
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message).not.toBe('');
      expect(message).not.toContain(short);
    });

    it('does not read the environment', async () => {
      const saved = { ...process.env };
      process.env.JWT_SECRET = OTHER_SECRET;
      process.env.AGENT_JWT_SECRET = OTHER_SECRET;
      try {
        // A token signed with the environment's secret is NOT accepted...
        const envToken = new JwtService({ secret: OTHER_SECRET }).sign(
          { ...claimsFor() },
          { algorithm: 'HS256' },
        );
        await expect(signer.verify(envToken)).resolves.toBeNull();
        // ...and our own tokens do not depend on it.
        await expect(
          signer.verify(await signer.sign(claimsFor())),
        ).resolves.not.toBeNull();
      } finally {
        process.env = saved;
      }
    });

    it("two signers with different secrets never accept each other's tokens", async () => {
      const other = make(OTHER_SECRET);
      await expect(
        other.verify(await signer.sign(claimsFor())),
      ).resolves.toBeNull();
      await expect(
        signer.verify(await other.sign(claimsFor())),
      ).resolves.toBeNull();
    });
  });

  describe('logging', () => {
    it('never writes to the console, on success or failure', async () => {
      const spies = (['log', 'info', 'warn', 'error', 'debug'] as const).map(
        (m) => jest.spyOn(console, m).mockImplementation(() => undefined),
      );
      try {
        const token = await signer.sign(claimsFor());
        await signer.verify(token);
        await signer.verify(`${token}x`);
        await signer.verify('garbage');
        await signer.verify(forge({ alg: 'none' }, claimsFor(), null));
        for (const spy of spies) expect(spy).not.toHaveBeenCalled();
      } finally {
        spies.forEach((spy) => spy.mockRestore());
      }
    });
  });
});
