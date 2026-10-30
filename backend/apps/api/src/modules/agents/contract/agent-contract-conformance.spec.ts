/**
 * Contract conformance: every implemented agent-program route matches
 * docs/agent-program/agent-api.openapi.yaml or agent-admin-api.openapi.yaml
 * (method, path, auth or permission, step-up, success status), and every
 * contract route is either implemented or listed below with a reason.
 *
 * Read from Nest's own route metadata, so it checks what actually serves
 * requests. The YAML is read with a small reader for these two files' fixed
 * layout (no YAML dependency).
 *
 * PENDING: on a branch that is not merged yet; allowed to be missing, and
 * checked like any other route once it exists. GAP: deliberately not built;
 * must be missing (implementing it means removing the entry).
 */
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { RequestMethod } from '@nestjs/common';
import {
  GUARDS_METADATA,
  HTTP_CODE_METADATA,
  METHOD_METADATA,
  PATH_METADATA,
} from '@nestjs/common/constants';

const DOCS = join(__dirname, '../../../../../../../docs/agent-program');

type Auth = 'none' | 'agent' | 'member' | 'admin';

interface ContractRoute {
  key: string;
  file: string;
  auth: Auth;
  permission: string | null;
  stepUp: boolean;
  successCodes: number[];
  statuses: number[];
}

/** Reads `paths:` of one of our OpenAPI files (fixed 2/4/6/8-space layout). */
export function readContract(file: string, defaultAuth: Auth): ContractRoute[] {
  const lines = readFileSync(join(DOCS, file), 'utf8').split(/\r?\n/);
  const routes: ContractRoute[] = [];
  let path: string | null = null;
  let current: ContractRoute | null = null;
  let inPaths = false;
  let inSecurity = false;
  for (const line of lines) {
    if (/^paths:/.test(line)) {
      inPaths = true;
      continue;
    }
    if (!inPaths) continue;
    if (/^\S/.test(line)) break; // components:
    const p = /^ {2}(\/\S+):\s*$/.exec(line);
    if (p) {
      path = p[1];
      current = null;
      continue;
    }
    const m = /^ {4}(get|post|patch|put|delete):\s*$/.exec(line);
    if (m && path) {
      current = {
        key: `${m[1].toUpperCase()} ${path}`,
        file,
        auth: defaultAuth,
        permission: null,
        stepUp: false,
        successCodes: [],
        statuses: [],
      };
      routes.push(current);
      inSecurity = false;
      continue;
    }
    if (!current) continue;
    const perm = /^ {6}x-permission:\s*(\S+)/.exec(line);
    if (perm) current.permission = perm[1];
    if (/^ {6}x-step-up:\s*true/.test(line)) current.stepUp = true;
    if (/^ {6}security:\s*\[\]/.test(line)) current.auth = 'none';
    if (/^ {6}security:\s*$/.test(line)) inSecurity = true;
    else if (/^ {6}\S/.test(line)) inSecurity = false;
    const scheme = /^ {8}- (agentBearer|memberBearer):/.exec(line);
    if (inSecurity && scheme) {
      current.auth = scheme[1] === 'agentBearer' ? 'agent' : 'member';
    }
    const status = /^ {8}'(\d{3})':/.exec(line);
    if (status) {
      const code = Number(status[1]);
      current.statuses.push(code);
      if (code >= 200 && code < 300) current.successCodes.push(code);
    }
  }
  return routes;
}

interface ImplementedRoute {
  key: string;
  auth: Auth;
  permission: string | null;
  successCode: number;
}

/** The controllers of the agent program, on whichever branch this runs. */
const CONTROLLER_FILES = [
  '../admin/agent-admin.controller',
  '../admin/agent-admin-actions.controller',
  '../admin/agent-admin-money.controller',
  '../http/agent-auth.controller',
  '../http/agent.controller',
  '../http/member-referral.controller',
];

const ADMIN_ROUTE_POLICY = 'nenjam:admin-route-policy';

function guardNames(target: object): string[] {
  const guards = (Reflect.getMetadata(GUARDS_METADATA, target) ?? []) as Array<
    { name?: string } | object
  >;
  return guards.map((g) => (g as { name?: string }).name ?? '');
}

export function implementedRoutes(): ImplementedRoute[] {
  const routes: ImplementedRoute[] = [];
  for (const rel of CONTROLLER_FILES) {
    if (!existsSync(join(__dirname, `${rel}.ts`))) continue;
    const exports = jest.requireActual<Record<string, unknown>>(
      join(__dirname, rel),
    );
    for (const value of Object.values(exports)) {
      if (typeof value !== 'function') continue;
      const ctrl = value as { prototype: Record<string, unknown> };
      const base = Reflect.getMetadata(PATH_METADATA, ctrl) as
        string | undefined;
      if (base === undefined) continue;
      for (const name of Object.getOwnPropertyNames(ctrl.prototype)) {
        const handler = ctrl.prototype[name];
        if (typeof handler !== 'function' || name === 'constructor') continue;
        const sub = Reflect.getMetadata(PATH_METADATA, handler) as
          string | undefined;
        const method = Reflect.getMetadata(METHOD_METADATA, handler) as
          RequestMethod | undefined;
        if (sub === undefined || method === undefined) continue;
        const path = `/${[base, sub].filter((s) => s && s !== '/').join('/')}`
          .replace(/\/+/g, '/')
          .replace(/:(\w+)/g, '{$1}');
        const verb = RequestMethod[method];
        const guards = [...guardNames(ctrl), ...guardNames(handler)];
        const policy = Reflect.getMetadata(ADMIN_ROUTE_POLICY, handler) as
          { permissions: readonly string[] } | undefined;
        const auth: Auth = guards.includes('AgentAccessGuard')
          ? 'agent'
          : guards.includes('AdminGuard')
            ? 'admin'
            : guards.includes('FirebaseAuthGuard')
              ? 'member'
              : 'none';
        const code =
          (Reflect.getMetadata(HTTP_CODE_METADATA, handler) as
            number | undefined) ?? (verb === 'POST' ? 201 : 200);
        routes.push({
          key: `${verb} ${path}`,
          auth,
          permission: policy?.permissions.join(',') || null,
          successCode: code,
        });
      }
    }
  }
  return routes;
}

const ROUTES_BRANCH = 'feat/agent-routes-flagged';
const ADMIN_BRANCH = 'feat/agent-admin-routes-rest';

/** Contract routes that may be missing on this branch, and why. */
const PENDING: Record<string, string> = Object.fromEntries<string>(
  [
    'POST /agent/auth/otp/request',
    'POST /agent/auth/otp/verify',
    'POST /agent/auth/refresh',
    'POST /agent/auth/logout',
    'POST /agent/application',
    'GET /agent/me',
    'PATCH /agent/me/payout-details',
    'GET /agent/config',
    'GET /agent/referral-links',
    'GET /agent/referrals',
    'GET /agent/referrals/{id}',
    'POST /referrals/codes/validate',
    'POST /registration/referral-code',
  ]
    .map((k): [string, string] => [k, ROUTES_BRANCH])
    .concat(
      [
        'POST /admin/agents/{id}/pause',
        'POST /admin/agents/{id}/resume',
        'POST /admin/agents/{id}/terminate',
        'POST /admin/agents/{id}/codes/replace',
        'POST /admin/agents/{id}/payout-details/verify',
        'POST /admin/agents/{id}/reveal',
        'POST /admin/agents/{id}/pan/verify',
        'GET /admin/agents/{id}/referrals',
        'POST /admin/referrals/{id}/correct',
        'GET /admin/commissions',
        'POST /admin/commissions/{id}/approve',
        'POST /admin/commissions/{id}/cancel',
        'POST /admin/commissions/{id}/override',
        'GET /admin/payouts',
        'POST /admin/payouts',
        'GET /admin/payouts/{id}',
        'POST /admin/payouts/{id}/mark-paid',
        'POST /admin/payouts/{id}/cancel',
      ].map((k): [string, string] => [k, ADMIN_BRANCH]),
    ),
);

/** Contract routes deliberately not built yet. */
const GAPS: Record<string, string> = {
  'GET /agent/commissions':
    'not in the 29 Oct route list; the commission services exist on the stack',
  'GET /agent/balance': 'not in the 29 Oct route list',
  'GET /agent/payouts': 'not in the 29 Oct route list',
  'POST /agent/devices': 'no agent push yet (the portal is a website)',
};

const contract = [
  ...readContract('agent-api.openapi.yaml', 'agent'),
  ...readContract('agent-admin-api.openapi.yaml', 'admin'),
];
const implemented = implementedRoutes();
const byKey = new Map(contract.map((r) => [r.key, r]));

describe('agent-program routes conform to the contracts', () => {
  it('read both contracts', () => {
    expect(contract.length).toBeGreaterThan(40);
    expect(new Set(contract.map((r) => r.key)).size).toBe(contract.length);
  });

  it('every implemented route is in a contract', () => {
    expect(implemented.map((r) => r.key).filter((k) => !byKey.has(k))).toEqual(
      [],
    );
  });

  it.each(implemented.map((r) => [r.key, r] as const))(
    '%s: auth, permission and success status match',
    (_key, route) => {
      const c = byKey.get(route.key);
      if (!c) return; // reported by the test above
      expect({
        auth: route.auth,
        permission: route.permission,
        success: c.successCodes.includes(route.successCode),
      }).toEqual({ auth: c.auth, permission: c.permission, success: true });
    },
  );

  it('every contract route that needs a caller documents 401; every permission route 403', () => {
    const problems = contract.flatMap((c) => [
      ...(c.auth !== 'none' && !c.statuses.includes(401)
        ? [`${c.key}: no 401`]
        : []),
      ...(c.permission && !c.statuses.includes(403)
        ? [`${c.key}: no 403`]
        : []),
    ]);
    expect(problems).toEqual([]);
  });

  it('a step-up route is a payout.execute or agent.pii.reveal route', () => {
    for (const c of contract.filter((r) => r.stepUp)) {
      expect([
        c.key,
        ['payout.execute', 'agent.pii.reveal'].includes(c.permission ?? ''),
      ]).toEqual([c.key, true]);
    }
  });

  it('every contract route is implemented, pending on a named branch, or a listed gap', () => {
    const done = new Set(implemented.map((r) => r.key));
    const unexplained = contract
      .map((c) => c.key)
      .filter((k) => !done.has(k) && !PENDING[k] && !GAPS[k]);
    expect(unexplained).toEqual([]);
  });

  it('every error code the agent routes can send is in the contract enum', () => {
    const text = readFileSync(join(DOCS, 'agent-api.openapi.yaml'), 'utf8');
    const block = /\n {8}code:\n[\s\S]*?enum:\n((?: {12}- \S+\n)+)/.exec(text);
    const documented = new Set(
      (block?.[1] ?? '').split('\n').map((l) => l.trim().replace(/^- /, '')),
    );
    const sent = new Set<string>(['AGENT_PROGRAM_UNAVAILABLE']);
    const filterFile = '../http/agent-errors.filter';
    if (existsSync(join(__dirname, `${filterFile}.ts`))) {
      const { AGENT_ERROR_HTTP } = jest.requireActual<{
        AGENT_ERROR_HTTP: Record<string, { code?: string; status: number }>;
      }>(join(__dirname, filterFile));
      for (const [code, m] of Object.entries(AGENT_ERROR_HTTP)) {
        if (m.status < 500) sent.add(m.code ?? code);
      }
      sent.add('CONCURRENT_CHANGE');
    }
    expect([...sent].filter((c) => !documented.has(c))).toEqual([]);
  });

  it('the 503 codes passed through from the platform services are in the enum, spelled as those services send them', () => {
    const text = readFileSync(join(DOCS, 'agent-api.openapi.yaml'), 'utf8');
    const block = /\n {8}code:\n[\s\S]*?enum:\n((?: {12}- \S+\n)+)/.exec(text);
    const documented = new Set(
      (block?.[1] ?? '').split('\n').map((l) => l.trim().replace(/^- /, '')),
    );
    const platform = join(__dirname, '../../platform');
    for (const [file, code] of [
      ['identifier-hash.service.ts', 'IDENTIFIER_HASHING_UNAVAILABLE'],
      ['otp/otp.service.ts', 'OTP_DELIVERY_UNAVAILABLE'],
    ]) {
      expect(readFileSync(join(platform, file), 'utf8')).toContain(
        `code: '${code}'`,
      );
      expect([code, documented.has(code)]).toEqual([code, true]);
    }
  });

  it('every code the contract text names as `NNN CODE` is in the enum', () => {
    const text = readFileSync(join(DOCS, 'agent-api.openapi.yaml'), 'utf8');
    const block = /\n {8}code:\n[\s\S]*?enum:\n((?: {12}- \S+\n)+)/.exec(text);
    const documented = new Set(
      (block?.[1] ?? '').split('\n').map((l) => l.trim().replace(/^- /, '')),
    );
    const named = [
      ...text.matchAll(/`[1-5][0-9]{2}\s+([A-Z][A-Z_]{3,})`/g),
    ].map((m) => m[1]);
    expect(named).toContain('IDENTIFIER_HASHING_UNAVAILABLE');
    expect([...new Set(named)].filter((c) => !documented.has(c))).toEqual([]);
  });

  it('a listed gap is really missing (remove it when it is built)', () => {
    const done = new Set(implemented.map((r) => r.key));
    expect(Object.keys(GAPS).filter((k) => done.has(k))).toEqual([]);
    expect(Object.keys(GAPS).filter((k) => !byKey.has(k))).toEqual([]);
    expect(Object.keys(PENDING).filter((k) => !byKey.has(k))).toEqual([]);
  });
});
