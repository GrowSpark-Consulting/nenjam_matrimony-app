# Admin panel — access, API and operations

Who is staff, what each staff member may do, how they prove a second factor, the admin
API over membership, and the audit trail. Backend: `backend/apps/api/src/modules/admin/`.
Web app: `admin/` (see [admin/README.md](../../admin/README.md)). Design source: *Nenjam
Admin Architecture v3* (sections 4, 11 and 13), adapted to what the repository already had.

**Built:** RBAC tables and permission keys, `AdminGuard` + `@RequirePermissions`, our own
TOTP second factor with admin sessions, the audit writer, operator provisioning,
protection of staff accounts from the member sign-in paths, plan drafts with two-admin
publishing, subscription lookup/extend/revoke, audit search, overview and roles, and the
Next.js web app for all of it.
**Not built yet:** agent screens (they need Ishu's `/admin/agents/*`), complimentary grants
and extensions over 30 days (need a second-approver workflow), payments/refunds screens
(no live payments yet), platform settings, role editing in the UI.

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
| `GET /admin/overview` | `dashboard.view` | Member counts, active memberships by plan, drafts awaiting approval; revenue only with `finance.view` |
| `GET /admin/plans` | `plan.view` | Every plan: current entitlements, version history, prices, open draft, subscriber count; the feature registry |
| `PATCH /admin/plans/:code/display` `{ displayName?, description?, displayOrder?, reason }` | `plan.edit` | Name and description |
| `POST /admin/plans/:code/status` `{ isActive, reason }` | `plan.publish` | Start / stop selling (existing subscriptions untouched; Free can't be switched off) |
| `GET /admin/plan-drafts` `?planCode&status` · `GET /admin/plan-drafts/:id` | `plan.view` | Drafts, each with the server's review: problems, changed features, reductions, price changes, `publishable`, `stale` |
| `POST /admin/plan-drafts` `{ planCode, changeNote }` | `plan.edit` | Start a draft from the plan as it is (one open draft per plan) |
| `PUT /admin/plan-drafts/:id` `{ entitlements?, durations?, changeNote? }` | `plan.edit` | Edit a DRAFT (the complete entitlement map / price list; paise) |
| `POST /admin/plan-drafts/:id/submit` | `plan.edit` | Send for approval — must be valid and change something |
| `POST /admin/plan-drafts/:id/publish` `{ note? }` | `plan.publish`, **not the submitter** | New version (if entitlements changed) + prices, one transaction |
| `POST /admin/plan-drafts/:id/reject` `{ reason }` | `plan.publish`, not the submitter | |
| `POST /admin/plan-drafts/:id/discard` `{ reason }` | `plan.edit` | |
| `GET /admin/subscriptions` `?q&status&planCode&cursor&limit` | `subscription.view` | `q` = exact email, phone, user id or subscription id; contacts masked; `{ items, nextCursor }` |
| `GET /admin/subscriptions/:id` | `subscription.view` | With events and payments |
| `POST /admin/subscriptions/:id/extend` `{ days ≤ 30, reason }` | `subscription.extend` | Pushes queued renewals back too |
| `POST /admin/subscriptions/:id/revoke` `{ reason }` | `subscription.cancel` | Ends it now; no refund |
| `GET /admin/audit-logs` `?action&entity&entityId&actorId&from&to&cursor&limit` | `audit.view` | Newest first; read-only (no edit/delete route exists) |
| `GET /admin/roles` | `rbac.manage` (step-up) | Roles, grants and admins, read-only |

**Maker-checker:** a plan draft is published or rejected only by an admin other than the
one who submitted it — enforced in the service and by a database CHECK. Keep at least two
admins with `plan.publish`. Prices are changed only through drafts.

Session policy: 12 h absolute, 30 min idle, step-up valid 10 min. A code is accepted once
per 30-second step (no replay). Five wrong codes (or enrolment codes) lock the second
factor for 15 minutes (**429** `ADMIN_MFA_LOCKED`, `retryAfterSeconds`). The auth routes
are also rate limited to 10 per 15 minutes per IP. The session token is returned once and
stored only as a SHA-256 hash; TOTP secrets are AES-256-GCM encrypted.

## Roles and permissions

Tables: `roles`, `permissions`, `role_permissions`, `admin_user_roles`. Permission keys are
`<resource>.<action>`, defined in `admin/rbac/permissions.ts` and seeded by migration
`20261029053600_admin_rbac_foundation` (a unit test keeps the two identical). 48 keys — the
architecture document's, plus `agent.pii.reveal` (requested for the first agent payout): dashboard/members, verification and support, subscriptions,
plans, payments and refunds, the agent program (`agent.*`, `attribution.*`,
`commission.*`, `payout.*`) and platform (`config.edit`, `rbac.manage`, `audit.view`, …).
Sensitive (step-up): `member.pii.reveal`, `agent.pii.reveal`, `refund.approve`,
`payout.execute`, `rbac.manage`.

Seeded roles (Raja, 28 Oct):

| Role | Permissions | Who |
|---|---|---|
| `SUPER_ADMIN` | all 48 | Raja + one more |
| `PARTNER_MANAGER` | `agent.view`, `agent.approve` | approves / rejects agent applications |
| `PAYOUT_MANAGER` | `payout.view`, `payout.execute` (sensitive: step-up) | Raja + the person who pays; the payout detail/create response shows the full UPI or bank destination to `payout.execute` holders (never in lists); PAN stays Super Admin only |

Everything else — pausing/terminating agents, code replacement, PAN or phone reveal,
commissions, attribution — stays Super Admin only until decided. Other roles in the
architecture document (Operations, Finance, Support, Verification, Marketing, Read-only)
are added by later migrations once their permission matrix is confirmed.

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
| `CORS_ORIGINS` | API | Add the admin panel's origin (e.g. `https://admin.<domain>`). `X-Admin-Session` is already an allowed header. |
| `NEXT_PUBLIC_API_BASE_URL`, `NEXT_PUBLIC_FIREBASE_*` | admin web build | Public values, set at build time — see `admin/.env.example`. |

## Deploying

1. Back up (Neon branch or `pg_dump`, restore-tested) — there is no down-migration.
2. `pnpm prisma migrate deploy` → applies the agent tables (`20261028095916_agent_program_phase1`, Ishu), `20261029053600_admin_rbac_foundation` and
   `20261029053700_plan_drafts` (additive: new tables and enum, nullable/defaulted columns,
   CHECKs, seed). Verify: `SELECT count(*) FROM permissions` = 48; `SUPER_ADMIN` has 48
   grants; the placeholder admin's `is_active` is false.
3. Set `ADMIN_MFA_ENCRYPTION_KEY` on the API service; deploy the code.
4. `GET /admin/me` without a token → 401; with a member token → 403.
5. Build and host the web app (`admin/README.md` § Deploy); add its origin to
   `CORS_ORIGINS` and to Firebase's authorised domains.
6. Provision the first two Super Admins (two, because a plan change needs a second
   approver) and have each enrol in the web app.

## Security notes

- **Fixed for staff:** `POST /auth/dummy-otp/session` and `FirebaseAuthGuard` re-linked an
  existing `users` row to any new Firebase account that claimed the same email or phone,
  and dummy OTP resolved the Firebase account by a caller-supplied email. Both now refuse
  any staff row; the TOTP factor covers a hijacked Firebase login on top.
- **Fixed for members — claimed email:** dummy OTP no longer looks a Firebase account up by
  the email the caller typed, and never re-links a row by it; an email already on another
  account is refused (409 `EMAIL_ALREADY_REGISTERED`). `FirebaseAuthGuard` re-links a row
  by email only when Firebase has **verified** that email.
- **Still open for members — claimed phone (needs a launch decision):** while
  `DUMMY_OTP_ENABLED=true` with an empty `DUMMY_OTP_PHONES`, the dummy-OTP endpoint signs
  in whoever supplies a member's **phone number**: that is what "dummy" means, nothing is
  verified. Before real users depend on the app, either turn on real SMS OTP (Firebase
  Phone Auth on the Blaze plan + the app's real verifier + `USE_REAL_OTP=true`), or
  restrict `DUMMY_OTP_PHONES` to testers' numbers.
- Not yet: DB-level insert-only grants on `audit_logs` (needs a separate migration role),
  Redis caching of permission sets (not needed at admin traffic levels), a general
  approvals queue (grants, long extensions, refunds) — plan publishing already has one.
