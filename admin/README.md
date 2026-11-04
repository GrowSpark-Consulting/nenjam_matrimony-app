# Nenjam Admin (web)

The staff admin panel: a static Next.js + TypeScript app over the NestJS `/admin` API
(`backend/apps/api/src/modules/admin`). It has no server and no secrets — every
permission is checked by the API on every request; the UI only hides what `GET /admin/me`
says an admin can't use.

## Sections

| Section | Needs | What it does |
|---|---|---|
| Overview | `dashboard.view` | Member counts, active paid memberships, plan drafts awaiting approval, revenue (only with `finance.view`) |
| Agents | `agent.view` | Placeholder until the agent admin API (`/admin/agents/*`, agent-program team) is live — nothing simulated |
| Plans | `plan.view` | Catalogue, prices, entitlements, version history; edit name (`plan.edit`), stop/start selling (`plan.publish`) |
| Plan draft | `plan.view` / `plan.edit` / `plan.publish` | Edit entitlements and prices, review the server's validation and diff, submit; a **different** admin publishes or rejects |
| Subscriptions | `subscription.view` | Exact-identifier lookup (masked contacts), detail with payments and history; extend ≤ 30 days (`subscription.extend`), revoke (`subscription.cancel`) |
| Audit log | `audit.view` | Read-only, filterable |
| Roles & permissions | `rbac.manage` (sensitive) | Read-only roles, grants and admins |

Every sensitive action asks for a reason (stored in the audit log). Sensitive permissions
ask for a fresh authenticator code (step-up).

## Sign-in

1. Email + password (Firebase — a dedicated staff account created by an operator).
2. A code from an authenticator app → an admin session (12 h max, 30 min idle; kept in
   `sessionStorage`, this tab only).

First time: enter the one-time enrolment code from `pnpm admin:provision grant …`, scan the
QR code, confirm with the first code. Lost phone: an operator runs
`pnpm admin:provision reset-mfa <email>`. See `docs/admin/README.md`.

## Run locally

```bash
cd admin
cp .env.example .env.local     # fill in the Firebase web values and the API URL
pnpm install
pnpm dev                       # http://localhost:3001
```

The API must allow this origin: add `http://localhost:3001` to the API's `CORS_ORIGINS`
(development already reflects any origin), and set `ADMIN_MFA_ENCRYPTION_KEY` on the API.

Checks: `pnpm typecheck`, `pnpm lint`, `pnpm test`, `pnpm build` (all run in CI).

## Deploy

`pnpm build` writes a static site to `out/`. Host it anywhere static (Vercel, Render static
site, S3 + CloudFront) on its own domain, e.g. `admin.<domain>`:

- Set the `NEXT_PUBLIC_*` variables at build time (they are public).
- Add the admin origin to the API's `CORS_ORIGINS`.
- Add the admin domain to Firebase → Authentication → Settings → Authorized domains.
- On Vercel, `vercel.json` (this folder) sets the security headers (`X-Frame-Options: DENY`,
  `frame-ancestors 'none'`, `nosniff`, `Referrer-Policy: no-referrer`, `X-Robots-Tag: noindex`).
  It also sends a direct browser visit to a page's `index.txt` to the 404 page. That file is
  the page's React data, written by the static export and fetched by the app's own
  navigation, which sends `rsc: 1` and `?_rsc=`, so navigation is unaffected. If a request is
  ever caught by mistake, Next.js falls back to a full page load.
- `ignoreCommand` builds this project only when `admin/` changed. A deploy refused by
  Vercel's daily limit is not retried, so redeploy it by hand (Deployments → Redeploy).
