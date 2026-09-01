#!/usr/bin/env node
/**
 * Copies row data from one PostgreSQL database into another that already has
 * an identical schema (created here by `prisma migrate deploy`).
 *
 * SAFETY — the source is opened and only ever SELECTed from. There is no code
 * path in this file that writes to, alters, or deletes anything in the source.
 *
 *   OLD_DATABASE_URL=... NEW_DATABASE_URL=... node scripts/db-copy-data.mjs
 *
 * Add --dry-run to report what it would copy without writing.
 *
 * Why this and not pg_dump: the PostgreSQL client tools are not installed on
 * this machine, and Neon's Import Data Assistant is console-only. The schema
 * therefore comes from the 19 committed migrations — already verified to
 * reproduce the source schema exactly — and only the ~1k data rows move here.
 *
 * Ordering: tables are topologically sorted by their foreign keys so parents
 * are always inserted before children, which keeps every constraint enforced
 * throughout. Constraints are never disabled — if a row would violate one, the
 * copy fails loudly rather than silently producing an orphan.
 *
 * Idempotence: `ON CONFLICT DO NOTHING` means a re-run tops up rather than
 * duplicating, so an interrupted copy can simply be run again.
 */
import pg from 'pg';

const DRY_RUN = process.argv.includes('--dry-run');
const oldUrl = process.env.OLD_DATABASE_URL;
const newUrl = process.env.NEW_DATABASE_URL;
if (!oldUrl || !newUrl) {
  console.error('Set both OLD_DATABASE_URL and NEW_DATABASE_URL.');
  process.exit(2);
}

/** Prisma owns this table; `migrate deploy` already populated it correctly on
 *  the target, and copying it would clash with the rows it just wrote. */
const SKIP = new Set(['_prisma_migrations']);

const connect = async (url) => {
  const c = new pg.Client({ connectionString: url, connectionTimeoutMillis: 30_000 });
  await c.connect();
  return c;
};

const src = await connect(oldUrl);
const dst = await connect(newUrl);

const tables = (
  await src.query(`SELECT table_name FROM information_schema.tables
                   WHERE table_schema='public' AND table_type='BASE TABLE'
                   ORDER BY table_name`)
).rows.map((r) => r.table_name).filter((t) => !SKIP.has(t));

/**
 * json/jsonb columns, as "table.column".
 *
 * These need explicit JSON.stringify on the way in. node-postgres reads jsonb
 * back as a live JS value, and when that value is an ARRAY it re-encodes it as
 * a PostgreSQL array literal (`{a,b}`) rather than JSON (`["a","b"]`) — which
 * Postgres then rejects with `invalid input syntax for type json`. Objects
 * happen to survive; arrays do not. This schema has 25 such columns, several
 * holding arrays (preferred_castes, hobbies, completed_steps, ...).
 */
const jsonCols = new Set(
  (
    await src.query(`SELECT table_name, column_name FROM information_schema.columns
                     WHERE table_schema='public' AND data_type IN ('json','jsonb')`)
  ).rows.map((r) => `${r.table_name}.${r.column_name}`),
);

/** Values are passed through untouched except json/jsonb, which are serialized
 *  so Postgres receives JSON rather than an array literal. */
const encode = (table, col, value) =>
  value !== null && value !== undefined && jsonCols.has(`${table}.${col}`)
    ? JSON.stringify(value)
    : value;

// child -> set of parents it depends on. Self-references are ignored: a row can
// point at another row in its own table, which ordering between tables cannot
// fix, so those are handled by the retry pass at the end.
const deps = new Map(tables.map((t) => [t, new Set()]));
for (const r of (
  await src.query(`SELECT src.relname AS child, tgt.relname AS parent
                   FROM pg_constraint con
                   JOIN pg_class src ON src.oid = con.conrelid
                   JOIN pg_class tgt ON tgt.oid = con.confrelid
                   JOIN pg_namespace ns ON ns.oid = con.connamespace
                   WHERE con.contype='f' AND ns.nspname='public'`)
).rows) {
  if (r.child === r.parent) continue;
  if (deps.has(r.child) && tables.includes(r.parent)) deps.get(r.child).add(r.parent);
}

// Kahn's algorithm; any cycle falls through to the end and is retried.
const ordered = [];
const placed = new Set();
let progress = true;
while (progress) {
  progress = false;
  for (const t of tables) {
    if (placed.has(t)) continue;
    if ([...deps.get(t)].every((p) => placed.has(p))) {
      ordered.push(t);
      placed.add(t);
      progress = true;
    }
  }
}
const cyclic = tables.filter((t) => !placed.has(t));
ordered.push(...cyclic);

console.log(`Tables to copy: ${ordered.length}${cyclic.length ? ` (${cyclic.length} in a dependency cycle, copied last)` : ''}`);
if (DRY_RUN) console.log('DRY RUN — nothing will be written.\n');

let totalRead = 0;
let totalWritten = 0;
const deferred = [];

for (const table of ordered) {
  const { rows } = await src.query(`SELECT * FROM "${table}"`);
  totalRead += rows.length;
  if (rows.length === 0) {
    console.log(`  ${table.padEnd(30)} ${String(0).padStart(5)} rows  (empty)`);
    continue;
  }
  if (DRY_RUN) {
    console.log(`  ${table.padEnd(30)} ${String(rows.length).padStart(5)} rows  (would copy)`);
    continue;
  }

  const cols = Object.keys(rows[0]);
  const colList = cols.map((c) => `"${c}"`).join(', ');
  let written = 0;

  // One transaction per table: a failure rolls that table back rather than
  // leaving it half-populated.
  await dst.query('BEGIN');
  try {
    for (const row of rows) {
      const params = cols.map((c) => encode(table, c, row[c]));
      const placeholders = cols.map((_, i) => `$${i + 1}`).join(', ');
      // Each row gets a SAVEPOINT. Without one, a single failed INSERT poisons
      // the whole transaction — Postgres refuses every subsequent command with
      // "current transaction is aborted" — so the deferral below could never
      // work. Rolling back to the savepoint discards just the failed row and
      // leaves the transaction usable.
      await dst.query('SAVEPOINT row_sp');
      try {
        const res = await dst.query(
          `INSERT INTO "${table}" (${colList}) VALUES (${placeholders}) ON CONFLICT DO NOTHING`,
          params,
        );
        written += res.rowCount ?? 0;
        await dst.query('RELEASE SAVEPOINT row_sp');
      } catch (e) {
        await dst.query('ROLLBACK TO SAVEPOINT row_sp');
        // A self-referencing row whose target is not inserted yet (e.g. a chat
        // message replying to a later one) — park it for the retry pass, which
        // runs once the rest of the table is present.
        if (e.code === '23503') {
          deferred.push({ table, cols, colList, row });
        } else {
          throw e;
        }
      }
    }
    await dst.query('COMMIT');
  } catch (e) {
    await dst.query('ROLLBACK');
    console.error(`\n  FAILED on "${table}": ${e.message}`);
    console.error('  Nothing from this table was written. Source is untouched.');
    await src.end();
    await dst.end();
    process.exit(1);
  }

  totalWritten += written;
  const note = written === rows.length ? '' : `  (${rows.length - written} already present or deferred)`;
  console.log(`  ${table.padEnd(30)} ${String(written).padStart(5)} rows${note}`);
}

// Second pass for self-referencing rows (e.g. a chat message replying to
// another message in the same table).
if (deferred.length > 0 && !DRY_RUN) {
  console.log(`\nRetrying ${deferred.length} deferred self-referencing row(s)...`);
  let recovered = 0;
  for (const d of deferred) {
    const placeholders = d.cols.map((_, i) => `$${i + 1}`).join(', ');
    const res = await dst.query(
      `INSERT INTO "${d.table}" (${d.colList}) VALUES (${placeholders}) ON CONFLICT DO NOTHING`,
      d.cols.map((c) => encode(d.table, c, d.row[c])),
    );
    recovered += res.rowCount ?? 0;
  }
  totalWritten += recovered;
  console.log(`  recovered ${recovered}/${deferred.length}`);
  if (recovered < deferred.length) {
    console.error('  Some deferred rows still could not be inserted — investigate before switching.');
    await src.end();
    await dst.end();
    process.exit(1);
  }
}

console.log('');
console.log(`Rows read from source : ${totalRead}`);
console.log(`Rows written to target: ${totalWritten}`);
console.log(DRY_RUN ? 'Dry run complete.' : 'Copy complete — now run db-compare.mjs to verify.');

await src.end();
await dst.end();
