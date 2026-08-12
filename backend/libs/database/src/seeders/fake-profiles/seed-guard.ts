/**
 * Environment guard for the fake-profile seeder.
 *
 * This is deliberately stricter than the usual `NODE_ENV === 'development'`
 * check, because on this project that check protects nothing: the shared
 * team database runs with NODE_ENV=development, so a naive guard would let
 * the seeder write 30 fake members into the database everyone develops
 * against without a word.
 *
 * Two independent things must therefore be true:
 *   1. NODE_ENV must not be production.
 *   2. ALLOW_FAKE_SEED must be explicitly set to "true".
 *
 * The second one exists so that running the seeder is always a deliberate
 * act, never something that happens as a side effect of another command.
 */

/** Host fragments that mean "this is very likely a production database". */
const PRODUCTION_HOST_HINTS = ['prod', 'production', 'live'];

export interface SeedTarget {
  /** Masked host, safe to print. Never includes credentials. */
  host: string;
  region: string;
}

/** Strips credentials from a connection string so it can be logged. */
export function describeTarget(databaseUrl: string): SeedTarget {
  const host = (databaseUrl.match(/@([^/?]+)/) ?? [])[1] ?? '(unknown host)';
  const region = (host.match(/(us|ap|eu|sa)-[a-z]+-\d/) ?? ['unknown-region'])[0];
  return { host: host.replace(/^[^.]+/, '<endpoint>'), region };
}

export class FakeSeedBlockedError extends Error {}

/**
 * Throws unless it is unambiguously safe to write fake data.
 * Never prints the connection string.
 */
export function assertFakeSeedAllowed(databaseUrl: string | undefined): SeedTarget {
  if (!databaseUrl) {
    throw new FakeSeedBlockedError('DATABASE_URL is not set — refusing to run.');
  }

  if (process.env.NODE_ENV === 'production') {
    throw new FakeSeedBlockedError(
      'NODE_ENV=production — refusing to seed fake profiles into a production environment.',
    );
  }

  const target = describeTarget(databaseUrl);
  const hinted = PRODUCTION_HOST_HINTS.find((hint) =>
    target.host.toLowerCase().includes(hint),
  );
  if (hinted) {
    throw new FakeSeedBlockedError(
      `DATABASE_URL host contains "${hinted}", which looks like a production database ` +
        `(${target.host}). Refusing to run. If this is wrong, rename the host or seed a different database.`,
    );
  }

  if (process.env.ALLOW_FAKE_SEED !== 'true') {
    throw new FakeSeedBlockedError(
      [
        'ALLOW_FAKE_SEED is not set to "true".',
        '',
        `This would write 30 fake members into: ${target.host} [${target.region}]`,
        '',
        'That database is shared with the rest of the team, so seeding is opt-in by design.',
        'Re-run with the flag if that is what you want:',
        '',
        '  ALLOW_FAKE_SEED=true pnpm seed:fake',
        '',
        'Everything it writes can be removed again with:',
        '',
        '  ALLOW_FAKE_SEED=true pnpm unseed:fake',
      ].join('\n'),
    );
  }

  return target;
}
