# Database-gated tests for the agent Prisma adapters

The Prisma adapters under `backend/apps/api/src/modules/agents/adapters/prisma/`
have two kinds of tests:

| Kind | Files | Runs in | Needs a database |
|---|---|---|---|
| Default | `*.spec.ts` (including `testing/fake-agent-repositories.contract.spec.ts`) | `pnpm test` and CI | No |
| Database-gated | `*.db-spec.ts` | `pnpm test:agent-db` only | Yes, a throwaway **local** Postgres |

The default run never touches a database and never sees a `*.db-spec.ts` file
(`pnpm test` only matches `*.spec.ts`). CI does not run the database-gated
specs. They stay out of CI until someone decides CI should have a Postgres
service for them.

## The one environment variable

`AGENT_PRISMA_TEST_DATABASE_URL` — a connection string to a local Postgres whose
schema already has every migration applied (including
`20261028095916_agent_program_phase1`).

* If it is not set, `pnpm test:agent-db` fails with a message (it does not skip).
* If its host is anything but `localhost` or `127.0.0.1`, the specs refuse to
  open a connection.
* The specs **truncate** `agents`, `referral_codes`, `referral_attributions`,
  `agent_refresh_tokens`, `agent_payout_details` and `audit_logs`. Never point
  it at a database that holds data you want.
* The specs never read `backend/prisma.config.ts` or any `.env` file, and the
  URL is printed with its credentials hidden at the start of each suite.

## Running them

1. Start a throwaway Postgres on your machine (not the one the app uses) and
   create an empty database. For example, on a spare port:
   `initdb -D <dir> -U postgres -A trust`, then
   `pg_ctl -D <dir> -o "-p 55432 -c listen_addresses=127.0.0.1" start`, then
   `createdb -h 127.0.0.1 -p 55432 -U postgres agent_core_test`.
2. Apply the migrations to that database only. Do **not** use the repo's
   `prisma.config.ts` (it loads `.env.local` with `override: true`, which can
   silently replace `DATABASE_URL`): use a scratch Prisma config that reads the
   URL from one variable and refuses any non-local host, then
   `prisma migrate deploy --config <scratch config>`.
3. Run, from `backend/`:

   ```
   AGENT_PRISMA_TEST_DATABASE_URL=postgresql://postgres@127.0.0.1:55432/agent_core_test pnpm test:agent-db
   ```

   (On Windows PowerShell: `$env:AGENT_PRISMA_TEST_DATABASE_URL = '...'; pnpm test:agent-db`.)
4. Stop the cluster and delete its data directory when you are done.

## What the database-gated specs prove

* `prisma-unique-violation.db-spec.ts` — the real engine's unique-violation
  error shape (columns in `meta.driverAdapterError.cause.constraint.fields`, the
  constraint name only in `originalMessage`; there is **no** `meta.target` with
  the pg driver adapter), which the default spec records.
* `prisma-agent-repositories.db-spec.ts` — the same contract suite the
  in-memory fakes pass (`testing/agent-repositories.contract.ts`), run against
  the Prisma adapters, plus what only a real database shows: the same phone
  under another hash, CHECK violations not hidden as conflicts, cascade delete,
  a finished transaction refused, and the transaction timeout option.

## Known limit

Postgres aborts a transaction after any failed statement, a unique violation
included. After a repository throws `AgentConflictError` inside
`AgentUnitOfWork.run`, the `tx` can no longer be used; the error has to leave
`run` (which rolls back). The three services that handle a conflict today (application submit, refresh
rotation, code attach) catch it outside `run`, so they are fine; keep it that
way. A service that caught it inside `run` and carried on with the same `tx`
would get "current transaction is aborted". The fakes do not show this.
