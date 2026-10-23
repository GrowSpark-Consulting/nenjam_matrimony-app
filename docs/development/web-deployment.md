# Flutter web — build and Vercel deployment

The web app is the same Flutter project (`Frontend/`) built for the browser and
served as static files by Vercel. The API stays on Railway.

## Build

```bash
cd Frontend
flutter pub get
flutter build web --release        # output: Frontend/build/web
```

`build/web` is complete and self-contained: `web/vercel.json` is copied into it
by the build, so deploying that folder deploys the routing rules too.

The API origin is compiled in. It defaults to the production Railway host; to
point a build somewhere else:

```bash
flutter build web --release --dart-define=API_BASE_URL=https://<api-host>
```

`--dart-define` values are **public** — they end up in the JavaScript bundle.
Never pass a secret through it.

## Deploy (recommended: deploy the prebuilt output)

Vercel's build image has no Flutter SDK, so build locally or in CI (the
`Flutter` job in `.github/workflows/ci.yml` already runs the release build) and
upload the folder:

```bash
cd Frontend
flutter build web --release
npx vercel deploy build/web           # preview URL
npx vercel deploy build/web --prod    # production — only when authorised
```

If a Git-connected Vercel project is wanted instead, its settings are
Root Directory `Frontend`, Framework Preset *Other*, Output Directory
`build/web`, and a build command that first installs Flutter 3.44.6 (the
version pinned in CI). That route has not been executed.

## Routing and caching (`web/vercel.json`)

- Any path that does not end in a file extension is rewritten to `/index.html`,
  so `/chat-detail/<id>`, `/profile-detail/<id>`, `/discover`, … work on a
  refresh or a direct link. Real files are served first; a missing asset (for
  example `/assets/x.png`) is a genuine 404, not the app.
- `index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js`,
  `version.json` and `manifest.json` are `no-cache`, so a new release is picked
  up rather than a stale bootstrap being paired with new code.

## Variables and settings

Nothing secret belongs in the web bundle. The one Google API key in it is the
public Firebase web key (see "Restrict the web API key").

| Name | Purpose | Visible to browser? | Set where |
|---|---|---|---|
| `API_BASE_URL` (`--dart-define`) | API origin | Yes (compiled in) | Build command |
| `DUMMY_OTP`, `USE_REAL_OTP` (`--dart-define`) | Phone-OTP mode. **Never** pass `DUMMY_OTP=true` for a production web build. | Yes | Build command |
| `CORS_ORIGINS` | Comma-separated browser origins allowed to call the API **and** open the Socket.IO connection, e.g. `https://app.example.com`. Unset in production = every browser origin refused. | No | Railway, `api` service |
| `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` | Server-side Firebase token verification | No | Railway |
| `DUMMY_OTP_ENABLED`, `DEV_AUTH_ENABLED`, `DUMMY_OTP_PHONES` | Dummy-OTP session endpoint. Must stay off against real data. | No | Railway |

## One-time console actions (not done by the code)

1. **Railway** — set `CORS_ORIGINS` to the exact Vercel production (and preview)
   origins, then redeploy the `api` service.
2. **Firebase Console → Authentication → Settings → Authorized domains** — add
   the Vercel domain(s). Required for Google sign-in and phone OTP.
3. **Firebase Console → Authentication → Sign-in method** — Phone enabled; SMS
   billing/quota active (or add a *test phone number* for testing without SMS).
4. **Google Cloud Console → Credentials** — the web OAuth client must list the
   Vercel origin under Authorized JavaScript origins.
5. **Restrict the web API key** — in Google Cloud Console restrict the Firebase
   web API key (`AIza…` in `firebase_options.dart`) to HTTP referrers for the
   Vercel domain(s). Firebase web keys are public by design; the restriction is
   what limits abuse.

## Known web limitations

- Voice notes are unsupported: the backend accepts only MP4/M4A/AAC audio and
  browsers record WebM/Opus. The mic button says so.
- Face verification is unsupported (Android-only native liveness); the screen
  says so before asking for the camera.
- Web push notifications are not implemented (FCM is skipped on web).
- A photo chosen during sign-up is held in the page's memory until OTP; a
  reload before that loses it and the member picks it again.
- A signed-out visitor to a protected link lands on the sign-up page; logging
  in (not signing up) returns them to that link, held in memory only — a
  reload of the sign-up page forgets it. A link reached by signing out is
  never remembered.
- Location blocked for the site cannot be fixed from inside the page: Near Me
  says where the browser setting is and offers Try Again instead of an
  "Open Settings" button that browsers cannot honour.
- Swipe-only gestures have mouse equivalents: horizontal chip bars and
  carousels scroll with a mouse drag, the Matches reel moves one profile per
  wheel notch, the photo viewer has previous/next buttons and arrow keys, and
  the Inbox options sheet (long-press, or press-and-hold with a mouse) lists
  Pin and Mark Unread. Right-click is not used: the browser's own context
  menu would open on top of it.
- Share on Matches copies the profile's link (`/profile-detail/<id>`) on the
  web; it is still a no-op in the native apps.
