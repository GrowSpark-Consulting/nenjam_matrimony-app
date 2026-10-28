# Nenjam Agent Portal

The phone-first website for the Partner Program, at
**https://agent.nenjammatrimony.com** (once deployed). Agents sign in with
their phone and an OTP, apply, see their status, share their referral code,
and follow the people who joined, their earnings and their payouts.

It is separate from the Flutter member app. Agents use their own tokens
(`/agent/auth/*`), never Firebase. The "Partner Program" link that opens this
portal belongs on the website landing page only, not in the app.

The API contract is `docs/agent-program/agent-api.openapi.yaml`. The contract
wins over any handoff note.

> **Backend status:** the agent endpoints are **not live yet**. Their services
> exist on `main` (Ishu), but there are no controllers, no module registration
> and no database tables (the Phase 1 migration is PR #116, unmerged). Until
> they ship, a production build shows network or 404 errors on sign-in. It
> never shows sample data.

## Run locally

```bash
cd agent-portal
npm ci
cp .env.example .env.local   # VITE_USE_MOCKS=true for the in-browser mock
npm run dev                  # http://localhost:5173 (or http://127.0.0.1:5173)
```

| Script | What |
|---|---|
| `npm run dev` | Dev server on port 5173 |
| `npm run typecheck` | TypeScript |
| `npm run lint` | ESLint |
| `npm test` | Vitest (unit, component and route tests) |
| `npm run build` | Production build into `dist/` |

### Mock API (development and tests only)

`VITE_USE_MOCKS=true` runs the portal on an in-browser mock
(`src/api/mockAgentApi.ts`), with a "Test mode" banner. A production build
refuses it and does not even include the mock module. There is **no** fallback:
a missing or invalid `VITE_API_BASE_URL` shows a configuration error, never
sample data. Any 4–8 digit OTP works on the mock. Seeded phones:

| Phone | Status |
|---|---|
| 90000 00001 | Pending approval |
| 90000 00002 | Rejected |
| 90000 00003 | Paused (suspended) |
| 90000 00004 | Terminated |
| 90000 00005 | Active |
| any other | New applicant |

The mock's English labels other than "Under review", "Paused" and
"Processing" (the only ones in the contract's examples) are test data. Real
labels always come from `GET /agent/config`.

## Environment variables

Every `VITE_*` value is compiled into public JavaScript. **Never put a secret
in one.** The portal needs no secrets.

| Variable | Production | Notes |
|---|---|---|
| `VITE_API_BASE_URL` | `https://nenjam-matrimony.onrender.com` | Required. Must be `https`; `http` is accepted only for localhost in a dev build. No query, fragment or credentials. |
| `VITE_USE_MOCKS` | unset | `true` only for local development. A production build refuses it. |

## Deploy to Render (Static Site)

`render.yaml` describes the site. It sets the build (`npm ci && npm run build`
in `agent-portal/`), publishes `dist`, and:

- **SPA fallback:** every path is rewritten to `/index.html`, so refreshing
  `/referrals` works.
- **Security headers:** CSP (scripts and styles from self only; `connect-src`
  limited to the API origin), `X-Frame-Options: DENY`, `nosniff`,
  `Referrer-Policy: no-referrer`, a restrictive `Permissions-Policy`, and HSTS.
- **Caching:** `index.html` is always revalidated; hashed `/assets/*` files are
  cached for a year.
- **Custom domain:** `agent.nenjammatrimony.com`.

Steps (someone with access to Render and DNS; none of these were done by this
change):

1. Create the Static Site from `render.yaml` (Blueprint) or with the same
   settings, on the branch that holds this code.
2. Add the custom domain `agent.nenjammatrimony.com` in Render, then create the
   DNS record Render asks for (a `CNAME` to the site's `onrender.com` host) at
   the DNS provider. Render issues the HTTPS certificate once DNS resolves.
3. On the **API** service, add the exact origin
   `https://agent.nenjammatrimony.com` (no trailing slash) to `CORS_ORIGINS`.
   The API matches origins exactly and already allows the `Authorization` and
   `Accept-Version` headers and exposes `Retry-After`.
4. If the API URL ever changes, update `VITE_API_BASE_URL` **and** the CSP
   `connect-src` in `render.yaml`, then rebuild.
5. Check: `https://agent.nenjammatrimony.com/referrals` loads (fallback), the
   response headers are present, and the browser console shows no CSP or CORS
   errors.

## Rules this code follows

- `Accept-Version: 1` on every request. Every call here is an agent-contract
  call; the member API stays unversioned.
- **Token refresh is serialised across tabs** (Web Locks; inside the lock the
  stored session is re-read, so a tab never re-presents a refresh token another
  tab already used, which the server treats as theft). It is retried once. Any
  `REFRESH_TOKEN_*` failure signs the agent out. Applicant sessions have no
  refresh token and go back to OTP when they expire.
- Tokens are sent only in the `Authorization` header (`credentials: 'omit'`,
  `no-referrer`), never in URLs, and never logged. A sign-out in one tab signs
  out the others.
- `POST /agent/application` returns a full agent session: there is no second
  OTP. Refusals (`409 APPLICATION_EXISTS`, `403 AGENT_NOT_ACTIVE`) show the
  server's message plus "Sign in again". There is no "Apply again" button for
  rejected agents while that decision is pending.
- 4xx errors show the server's `message`. Server errors and network failures
  show a fixed sentence (never raw server output), with "Try again". Buttons
  are disabled while a request runs, so nothing is submitted twice.
- Share messages are shown and shared exactly as `GET /agent/referral-links`
  returns them. The link and QR code are hidden while null, and sharing is off
  while the agent is paused.
- Labels come from `GET /agent/config`. A Tamil label that is still
  `<to be supplied>` falls back to English.
- Money is integer paise, shown as rupees. Agents cannot create payouts.
- The Help text is the approved wording (`src/lib/helpContent.ts`), pinned by a
  snapshot test. The support contact is still a placeholder.
