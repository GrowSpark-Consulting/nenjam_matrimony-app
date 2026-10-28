# Admin access (RBAC, staff sign-in, audit) — Phase 1

The backend foundation for the admin panel: who is staff, what each staff member may
do, how they prove a second factor, and the audit trail. Code:
`backend/apps/api/src/modules/admin/`. Design source: *Nenjam Admin Architecture v3*
(sections 4 and 13), adapted to what the repository already had.

**Built:** RBAC tables and permission keys, `AdminGuard` + `@RequirePermissions`,
our own TOTP second factor with admin sessions, `GET /admin/me`, the audit writer,
operator provisioning, and protection of staff accounts from the member sign-in paths.
**Not built yet:** the Next.js admin panel (Phase 2), agent screens (Phase 3, on Ishu's
`/admin/agents/*`), plan and subscription admin routes (Phase 4).

## How a request to `/admin/*` is authorised

1. `FirebaseAuthGuard` — a valid Firebase ID token; account not suspended/banned/deleted.
2. `AdminGuard`:
   1. the route declares a policy, else **403** `ADMIN_ROUTE_UNPROTECTED` (deny by default;
      the API also refuses to boot with such a route — `AdminRouteCheck`);
   2. the user is **active staff** (role ≠ USER, `AdminAccount.isActive`), else **403**
      `ADMIN_ACCESS_REQUIRED`;
   3. a live **admin session** of their own in `X-Admin-Session` (issued only after an
      authenticator code), else **401** `ADMIN_SESSION_REQUIRED` / `ADMIN_SESSION_INVALID`;
   4. their **roles** grant every required permission, else **403** `ADMIN_PERMISSION_DENIED`
      (with `missing`);
   5. a sensitive permission needs an authenticator check in the last 10 minutes, else
      **401** `ADMIN_STEP_UP_REQUIRED`.
3. Services that change money or plans re-check the permission **inside their own
   transaction** (`assertAdminPermission(tx, actorId, key)`), so a missing guard or a
   script can't skip it.

Refusals at 2.1, 2.2 and 2.4 are audited (`admin.access.denied`). Roles and status are
read from the database on every request — revoking a role or deactivating an account
takes effect on the next request. Errors keep Nest's shape plus a stable `code`:
`{ statusCode, error, code, message }`.

Hiding a button in the panel is not authorisation; the panel reads `GET /admin/me` only to
decide what to show.

## Routes

| Route | Policy | Purpose |
|---|---|---|
| `POST /admin/auth/mfa/enrollment` `{ enrollmentCode }` | staff, no session | New authenticator secret (`secret`, `otpauthUri`) — needs the one-time code from provisioning |
| `POST /admin/auth/mfa/enrollment/confirm` `{ enrollmentCode, code }` | staff, no session | First code proves the app is set up; spends the enrolment code; returns a session |
| `POST /admin/auth/session` `{ code }` | staff, no session | Sign in: code → `{ sessionToken, expiresAt, idleTimeoutSeconds }` |
| `POST /admin/auth/step-up` `{ code }` | any admin | Fresh check before a sensitive action |
| `POST /admin/auth/logout` | any admin | Ends the session (204) |
| `GET /admin/me` | any admin | `{ adminAccountId, userId, email, department, lastLoginAt, roles, permissions }` |

Session policy: 12 h absolute, 30 min idle, step-up valid 10 min. A code is accepted once
per 30-second step (no replay). Five wrong codes (or enrolment codes) lock the second
factor for 15 minutes (**429** `ADMIN_MFA_LOCKED`, `retryAfterSeconds`). The auth routes
are also rate limited to 10 per 15 minutes per IP. The session token is returned once and
stored only as a SHA-256 hash; TOTP secrets are AES-256-GCM encrypted.

## Roles and permissions

Tables: `roles`, `permissions`, `role_permissions`, `admin_user_roles`. Permission keys are
`<resource>.<action>`, defined in `admin/rbac/permissions.ts` and seeded by migration
`20261028070845_admin_rbac_foundation` (a unit test keeps the two identical). 47 keys, from
the architecture document: dashboard/members, verification and support, subscriptions,
plans, payments and refunds, the agent program (`agent.*`, `attribution.*`,
`commission.*`, `payout.*`) and platform (`config.edit`, `rbac.manage`, `audit.view`, …).
Sensitive (step-up): `member.pii.reveal`, `refund.approve`, `payout.execute`, `rbac.manage`.

Seeded role: **`SUPER_ADMIN`** (all 47). The other roles in the architecture document
(Operations, Finance, Partner Manager, Support, Verification, Marketing, Read-only) are
**not seeded** — their permission matrix needs product sign-off; add them in a migration
or via the future roles screen.

The legacy `AdminAccount.permissions` JSON is kept but **no longer read**. Membership's
admin services now use: `subscription.grant` / `.extend` / `.cancel`, `plan.publish`
(versions, prices, availability), `plan.edit` (display text).

## Provisioning admins (operator, until the roles screen exists)

Run from `backend/` with `DATABASE_URL` (and Firebase Admin credentials) for the target
environment. Every write prints the target database host, needs `--yes`, and is audited
with the reason (`actorId: null`).

1. In the Firebase console → Authentication → **Add user**: a **dedicated staff email**
   and a strong password. Never a member's own account (the script refuses an account
   with a member profile, or a Firebase account with a phone number).
2. `pnpm admin:provision grant ops@example.com SUPER_ADMIN --reason "Founding admin" --yes`
   → prints a **one-time enrolment code** (valid 24 h, shown once). Give it to the person
   privately.
3. They sign in to the admin panel with email + password, enter the enrolment code, scan
   the QR code into an authenticator app (Google Authenticator, Microsoft Authenticator,
   1Password…) and confirm with the first code.

Other commands: `list`, `revoke <email> <ROLE>`, `reset-mfa <email>` (lost phone: clears
the authenticator, ends sessions, new enrolment code), `deactivate <email>` (ends sessions;
roles kept). Keep at least two Super Admins.

The production database has one admin row today: the old seeder's placeholder
(`admin@nenjammatrimony.com`, placeholder Firebase uid). After this migration it is
**inactive** and has no role, so it has no access. Either provision a real account or
leave it; don't reuse the seeder against production.

## For other modules (agent program)

```ts
@AdminController('admin/agents')          // FirebaseAuthGuard + AdminGuard
export class AdminAgentsController {
  @Post(':id/approve')
  @RequirePermissions('agent.approve')
  approve(@CurrentAdmin() admin: AuthenticatedAdmin, @AdminContext() ctx: AdminRequestContext, ...) {
    // in the service: one transaction for the change AND
    // adminAudit.record(tx, { actorId: admin.userId, action: 'agent.approve', entity: 'Agent',
    //   entityId, reason, before, after, context: ctx })
  }
}
```

Import `AdminModule` in the module that declares the controller. `AgentPermissionPort`
maps 1:1: `{ module: 'agent', action: 'approve' }` ↔ key `agent.approve`; an adapter calls
`assertAdminPermission(tx, actorId, key)` (throws `ForbiddenException`). The actor always
comes from `@CurrentAdmin()`, never from a request body.

## Environment

| Var | Where | Notes |
|---|---|---|
| `ADMIN_MFA_ENCRYPTION_KEY` | API | 32 random bytes, base64 (`node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"`). Unset → admin sign-in answers 503, the app still boots. Malformed → the API refuses to boot. One per environment; changing it invalidates every enrolled authenticator (`reset-mfa` each admin). |
| `CORS_ORIGINS` | API | Add the admin panel's origin when it is deployed (Phase 2). `X-Admin-Session` is already an allowed header. |

## Deploying Phase 1

1. Back up (Neon branch or `pg_dump`, restore-tested) — there is no down-migration.
2. `pnpm prisma migrate deploy` → applies `20261028070845_admin_rbac_foundation`
   (additive: new tables, nullable/defaulted columns, CHECKs, seed). Verify:
   `SELECT count(*) FROM permissions` = 47; `SUPER_ADMIN` has 47 grants; the placeholder
   admin's `is_active` is false.
3. Set `ADMIN_MFA_ENCRYPTION_KEY` on the API service; deploy the code.
4. `GET /admin/me` without a token → 401; with a member token → 403.
5. Provision the first Super Admin (above) once the admin panel can run the enrolment
   (Phase 2), or enrol through the API directly.

## Security notes

- **Fixed for staff:** `POST /auth/dummy-otp/session` and `FirebaseAuthGuard` re-linked an
  existing `users` row to any new Firebase account that claimed the same email or phone,
  and dummy OTP resolved the Firebase account by a caller-supplied email. Both now refuse
  any staff row; the TOTP factor covers a hijacked Firebase login on top.
- **Still open for members (separate decision):** with `DUMMY_OTP_ENABLED` and no
  `DUMMY_OTP_PHONES` allow-list, dummy OTP can still sign a caller in as a member whose
  email they supply. Fix before real users depend on it: stop resolving accounts by the
  supplied email in dummy OTP, or switch to real OTP (`USE_REAL_OTP=true`).
- Not yet: DB-level insert-only grants on `audit_logs` (needs a separate migration role),
  Redis caching of permission sets (not needed at admin traffic levels), maker-checker
  approvals for publishing plans (Phase 4).
