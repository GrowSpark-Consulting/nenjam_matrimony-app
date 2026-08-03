# Git hooks

Tracked hooks, shared by the whole team. Git does not use this directory
automatically — each clone must be pointed at it once:

```bash
git config core.hooksPath scripts/git-hooks
```

`backend`'s `prepare` script runs that for you on `pnpm install`, so in
practice a fresh clone is covered as soon as dependencies are installed.

Verify it is active:

```bash
git config --get core.hooksPath    # -> scripts/git-hooks
```

## `pre-commit` — secret-leak guard

Blocks a commit that would write real credentials into git history.

This exists because of a real near-miss: live Neon, Firebase, AWS and
Elasticsearch credentials were pasted into `backend/.env.example` — the one
env file git tracks, via the `!.env.example` negation in `.gitignore`. It was
caught by hand before being committed. This hook makes that catch automatic.

### What it checks

Only **staged additions**, so cost scales with the size of the change.

**File level** — refuses any real env file (`.env`, `.env.local`,
`.env.production`, …; `.env.example` is allowed), service-account JSON, and
private keys / keystores / `key.properties`. `.gitignore` already covers
these, but `git add -f` overrides it and a file tracked *before* an ignore
rule was added is not covered at all.

**Content level** — AWS access key ids and secret keys, PEM private keys with
real key material, Postgres / Redis / MongoDB URLs with inline passwords, Neon
`npg_` passwords, Google API keys, GitHub tokens, Stripe live keys, Slack
tokens, and JWTs.

### What it deliberately allows

- **Placeholders.** Lines containing `YOUR_`, `CHANGEME`, `username:password`,
  `xxxxx`, `placeholder`, `MOCKKEY`, `REDACTED`, … are exempt, so
  `.env.example` stays committable.
- **Public client config.** `google-services.json`, `GoogleService-Info.plist`,
  `firebase_options.dart` and `firebase.json` are exempt from the Google API
  key rule. Firebase client config is public by design — it ships inside every
  APK, IPA and web bundle. Security there comes from Firebase Security Rules,
  not from secrecy.

Rules target structured, high-entropy credentials on purpose. A loose rule
that fires on the word `password` trains people to reflexively `--no-verify`,
which is worse than having no hook.

### When it fires

Move the real value into a gitignored `.env`, put a placeholder in the
template, then re-stage.

**If the value was already pushed, rotate it.** Deleting the line does not
remove it from history.

Genuine false positive:

```bash
git commit --no-verify
```

If you find yourself doing that often, fix the pattern instead — tune
`PLACEHOLDER_RE` or add a path to `is_public_client_config()`.
