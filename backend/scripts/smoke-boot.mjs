#!/usr/bin/env node
/**
 * Boots every built app and asserts it actually starts.
 *
 * This exists because neither of the checks the team already runs can catch a
 * broken application graph:
 *
 *   - `nest build` type-checks and bundles, but never constructs the Nest
 *     container, so it cannot see an unresolvable dependency.
 *   - the specs construct services directly with mocks, so they never exercise
 *     dependency injection either.
 *
 * A real instance of exactly that reached main: NotificationsModule was missing
 * AppConfigModule, so EmailDispatchService could not resolve AppConfigService
 * and the API refused to start — with a green build and 403 passing tests.
 *
 * Usage (after `pnpm build:all`):
 *   node scripts/smoke-boot.mjs
 *
 * Cross-platform on purpose: the team develops on Windows, CI runs on Linux.
 */
import { spawn } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
import { existsSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';

const BOOT_TIMEOUT_MS = 90_000;
/** Lines that mean the app gave up. Checked before the ready marker so a
 *  failure is reported as a failure rather than waiting out the timeout. */
const FAILURE_RE =
  /UnknownDependenciesException|Nest can't resolve dependencies|ERROR \[ExceptionHandler\]|EADDRINUSE|Cannot find module/i;

const APPS = [
  {
    name: 'api',
    entry: 'dist/apps/api/main.js',
    ready: /API running/,
    // The HTTP layer is the point of this app — a process that starts but
    // never serves is still broken, so poll the real endpoint.
    healthUrl: 'http://127.0.0.1:3000/health',
    // The agent routes are booted too, and GET /agent/config must answer 200:
    // it reads the seeded settings and the commission policy through the real
    // wiring (it was 503 in production while a placeholder stood in for the
    // policy). Smoke-only secret, not a real one.
    env: {
      PORT: '3000',
      AGENT_PROGRAM_ENABLED: 'true',
      AGENT_JWT_SECRET: SMOKE_AGENT_JWT_SECRET,
    },
    probe: probeAgentConfig,
  },
  {
    name: 'worker',
    entry: 'dist/apps/worker/main.js',
    ready: /Worker service started/,
  },
  {
    name: 'scheduler',
    entry: 'dist/apps/scheduler/main.js',
    ready: /Scheduler service started/,
  },
  {
    name: 'websocket',
    entry: 'dist/apps/websocket/main.js',
    // No bespoke log line in its bootstrap — Nest's own is the marker.
    ready: /Nest application successfully started/,
    env: { WEBSOCKET_PORT: '3101' },
  },
];

/** Smoke-only: signs the agent token the probe sends. Not a real secret. */
const SMOKE_AGENT_JWT_SECRET = 'smoke-only-agent-jwt-secret-not-real-0000';
/** The deployment identifiers of agent tokens (agents/http/agent-program.ts). */
const AGENT_TOKEN_ISSUER = 'nenjam-api';
const AGENT_TOKEN_AUDIENCE = 'nenjam-agent-portal';

const b64url = (value) => Buffer.from(value).toString('base64url');

/** An HS256 agent access token, with node:crypto only. */
function smokeAgentToken() {
  const iat = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const payload = b64url(
    JSON.stringify({
      sub: randomUUID(),
      scope: 'AGENT',
      iss: AGENT_TOKEN_ISSUER,
      aud: AGENT_TOKEN_AUDIENCE,
      iat,
      exp: iat + 300,
    }),
  );
  const signature = createHmac('sha256', SMOKE_AGENT_JWT_SECRET)
    .update(`${header}.${payload}`)
    .digest('base64url');
  return `${header}.${payload}.${signature}`;
}

/** Null when GET /agent/config answers 200 with the four displayed settings. */
async function probeAgentConfig() {
  const url = 'http://127.0.0.1:3000/agent/config';
  try {
    const res = await fetch(url, {
      headers: {
        Authorization: `Bearer ${smokeAgentToken()}`,
        'Accept-Version': '1',
      },
      signal: AbortSignal.timeout(10_000),
    });
    if (res.status !== 200) {
      return `GET /agent/config answered ${res.status} (expected 200; a 503 means a setting or the commission policy is missing - see the API log)`;
    }
    const body = await res.json();
    const wanted = ['holdDays', 'creditWindowDays', 'minPayoutPaise', 'referredMemberDiscountPercent'];
    const missing = wanted.filter((k) => typeof body?.settings?.[k] !== 'number');
    return missing.length === 0 ? null : `GET /agent/config has no ${missing.join(', ')}`;
  } catch (error) {
    return `GET /agent/config failed: ${error.message}`;
  }
}

async function pollHealth(url, deadline) {
  while (Date.now() < deadline) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(5_000) });
      if (res.ok) return true;
    } catch {
      // not up yet
    }
    await sleep(500);
  }
  return false;
}

async function boot(app) {
  if (!existsSync(app.entry)) {
    return { ok: false, reason: `${app.entry} missing — run \`pnpm build:all\` first` };
  }

  const child = spawn(process.execPath, [app.entry], {
    env: { ...process.env, NODE_ENV: 'development', ...app.env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let output = '';
  let ready = false;
  let failedWith = null;

  const collect = (chunk) => {
    const text = chunk.toString();
    output += text;
    if (!failedWith && FAILURE_RE.test(text)) failedWith = firstMatchingLine(text);
    if (app.ready.test(text)) ready = true;
  };
  child.stdout.on('data', collect);
  child.stderr.on('data', collect);

  let exitedEarly = null;
  child.on('exit', (code) => {
    if (!ready) exitedEarly = code;
  });

  const deadline = Date.now() + BOOT_TIMEOUT_MS;
  try {
    while (Date.now() < deadline && !ready && !failedWith && exitedEarly === null) {
      await sleep(250);
    }

    if (failedWith) return { ok: false, reason: failedWith, output };
    if (exitedEarly !== null) {
      return { ok: false, reason: `exited with code ${exitedEarly} before becoming ready`, output };
    }
    if (!ready) {
      return { ok: false, reason: `no ready marker within ${BOOT_TIMEOUT_MS / 1000}s`, output };
    }

    if (app.healthUrl) {
      const healthy = await pollHealth(app.healthUrl, deadline);
      if (!healthy) {
        return { ok: false, reason: `started but ${app.healthUrl} never returned 200`, output };
      }
    }

    if (app.probe) {
      const problem = await app.probe();
      if (problem) return { ok: false, reason: problem, output };
    }

    return { ok: true };
  } finally {
    child.kill('SIGTERM');
    // SIGTERM is advisory on Windows; make sure nothing is left holding a port.
    const gone = await Promise.race([
      new Promise((r) => child.once('exit', () => r(true))),
      sleep(5_000).then(() => false),
    ]);
    if (!gone) child.kill('SIGKILL');
  }
}

function firstMatchingLine(text) {
  return (
    text
      .split(/\r?\n/)
      .find((l) => FAILURE_RE.test(l))
      ?.trim()
      .slice(0, 300) ?? 'unknown failure'
  );
}

const results = [];
for (const app of APPS) {
  process.stdout.write(`  ${app.name.padEnd(10)} `);
  const result = await boot(app);
  results.push({ app: app.name, ...result });
  console.log(result.ok ? 'OK' : `FAILED — ${result.reason}`);
  if (!result.ok && result.output) {
    console.log(
      result.output
        .split(/\r?\n/)
        .filter(Boolean)
        .slice(-25)
        .map((l) => `      | ${l}`)
        .join('\n'),
    );
  }
}

const failed = results.filter((r) => !r.ok);
console.log('');
if (failed.length > 0) {
  console.log(`Smoke boot FAILED for: ${failed.map((f) => f.app).join(', ')}`);
  process.exit(1);
}
console.log(`Smoke boot passed — all ${results.length} apps started.`);
