#!/usr/bin/env node
/**
 * Structural + data comparison between two PostgreSQL databases, for verifying
 * a region migration before anything switches over.
 *
 * Everything it does is READ-ONLY. There is no code path here that writes,
 * drops, truncates or alters either database.
 *
 *   Snapshot one database (baseline, before migrating):
 *     node scripts/db-compare.mjs --snapshot <out.json>
 *
 *   Compare live source against the new target:
 *     OLD_DATABASE_URL=... NEW_DATABASE_URL=... node scripts/db-compare.mjs
 *
 *   Compare a saved baseline against the new target:
 *     NEW_DATABASE_URL=... node scripts/db-compare.mjs --baseline <in.json>
 *
 * Falls back to DATABASE_URL for the source when OLD_DATABASE_URL is unset.
 *
 * Row-count parity alone is NOT treated as proof of a good migration — it
 * cannot see a row that arrived with a mangled foreign key or a truncated
 * column. So this also fingerprints the schema (tables, columns, indexes,
 * enums with their exact member lists, constraints) and walks every foreign
 * key looking for orphans.
 *
 * Exit code is 0 only when every check passes, so it is safe to gate on.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import pg from 'pg';
import { config } from 'dotenv';

config({ path: '.env' });
config({ path: '.env.local', override: true });

const args = process.argv.slice(2);
const flag = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? (args[i + 1] ?? true) : undefined;
};

/** Mask a connection string down to something safe to print. */
function describe(url) {
  const host = (url.match(/@([^/?]+)/) || [])[1] || '(unknown host)';
  const region = (host.match(/(us|ap|eu|sa)-[a-z]+-\d/) || ['unknown-region'])[0];
  return `${host.replace(/^[^.]+/, '<endpoint>')}  [${region}]`;
}

async function connect(url) {
  const client = new pg.Client({ connectionString: url, connectionTimeoutMillis: 30_000 });
  await client.connect();
  return client;
}

/** Everything we compare, in one pass. */
async function inspect(client) {
  const one = async (sql) => (await client.query(sql)).rows;

  const tables = (
    await one(`SELECT table_name FROM information_schema.tables
               WHERE table_schema='public' AND table_type='BASE TABLE'
               ORDER BY table_name`)
  ).map((r) => r.table_name);

  const rowCounts = {};
  for (const t of tables) {
    const r = await client.query(`SELECT count(*)::int AS n FROM "${t}"`);
    rowCounts[t] = r.rows[0].n;
  }

  // Column-level fingerprint catches a type or nullability that did not survive.
  const columns = (
    await one(`SELECT table_name, column_name, data_type, is_nullable
               FROM information_schema.columns WHERE table_schema='public'
               ORDER BY table_name, column_name`)
  ).map((r) => `${r.table_name}.${r.column_name}:${r.data_type}:${r.is_nullable}`);

  const indexes = (
    await one(`SELECT indexname FROM pg_indexes WHERE schemaname='public' ORDER BY indexname`)
  ).map((r) => r.indexname);

  // Enum members matter as much as enum names — a missing value breaks inserts.
  const enums = (
    await one(`SELECT t.typname, string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder) AS labels
               FROM pg_type t
               JOIN pg_enum e ON e.enumtypid = t.oid
               JOIN pg_namespace ns ON ns.oid = t.typnamespace
               WHERE ns.nspname='public'
               GROUP BY t.typname ORDER BY t.typname`)
  ).map((r) => `${r.typname}(${r.labels})`);

  const constraints = (
    await one(`SELECT conname, contype FROM pg_constraint c
               JOIN pg_namespace ns ON ns.oid = c.connamespace
               WHERE ns.nspname='public' AND contype IN ('p','f','u')
               ORDER BY conname`)
  ).map((r) => `${r.contype}:${r.conname}`);

  const version = (await one(`SHOW server_version`))[0].server_version;
  const extensions = (await one(`SELECT extname FROM pg_extension ORDER BY extname`)).map(
    (r) => r.extname,
  );

  let migrations = null;
  if (tables.includes('_prisma_migrations')) {
    migrations = (
      await one(`SELECT migration_name, checksum FROM _prisma_migrations
                 WHERE finished_at IS NOT NULL ORDER BY migration_name`)
    ).map((r) => `${r.migration_name}:${r.checksum.slice(0, 12)}`);
  }

  return { version, tables, rowCounts, columns, indexes, enums, constraints, extensions, migrations };
}

/**
 * Walks every foreign key and counts rows whose referenced parent is missing.
 * Discovered from the catalog rather than hardcoded, so it stays correct as the
 * schema evolves. NULL child values are legal and excluded.
 */
async function findOrphans(client) {
  const fks = (
    await client.query(`
      SELECT con.conname,
             src.relname  AS child_table,
             srcatt.attname AS child_col,
             tgt.relname  AS parent_table,
             tgtatt.attname AS parent_col
      FROM pg_constraint con
      JOIN pg_class src ON src.oid = con.conrelid
      JOIN pg_class tgt ON tgt.oid = con.confrelid
      JOIN pg_attribute srcatt ON srcatt.attrelid = con.conrelid AND srcatt.attnum = con.conkey[1]
      JOIN pg_attribute tgtatt ON tgtatt.attrelid = con.confrelid AND tgtatt.attnum = con.confkey[1]
      JOIN pg_namespace ns ON ns.oid = con.connamespace
      WHERE con.contype='f' AND ns.nspname='public' AND array_length(con.conkey,1)=1
      ORDER BY con.conname`)
  ).rows;

  const orphans = [];
  for (const fk of fks) {
    const { rows } = await client.query(
      `SELECT count(*)::int AS n FROM "${fk.child_table}" c
       WHERE c."${fk.child_col}" IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM "${fk.parent_table}" p WHERE p."${fk.parent_col}" = c."${fk.child_col}")`,
    );
    if (rows[0].n > 0) {
      orphans.push({ constraint: fk.conname, detail: `${fk.child_table}.${fk.child_col} -> ${fk.parent_table}.${fk.parent_col}`, count: rows[0].n });
    }
  }
  return { checked: fks.length, orphans };
}

function diffLists(label, a, b, results) {
  const missing = a.filter((x) => !b.includes(x));
  const extra = b.filter((x) => !a.includes(x));
  const ok = missing.length === 0 && extra.length === 0;
  results.push({ label, ok, detail: ok ? `${a.length} identical` : `missing ${missing.length}, extra ${extra.length}` });
  if (!ok) {
    for (const m of missing.slice(0, 10)) console.log(`      MISSING in new: ${m}`);
    for (const e of extra.slice(0, 10)) console.log(`      EXTRA in new  : ${e}`);
  }
}

// ── main ────────────────────────────────────────────────────────────────────
const snapshotPath = flag('--snapshot');
const baselinePath = flag('--baseline');
const sourceUrl = process.env.OLD_DATABASE_URL || process.env.DATABASE_URL;
const targetUrl = process.env.NEW_DATABASE_URL;

if (snapshotPath) {
  if (!sourceUrl) throw new Error('Set OLD_DATABASE_URL or DATABASE_URL');
  console.log(`Snapshotting  ${describe(sourceUrl)}`);
  const client = await connect(sourceUrl);
  const state = await inspect(client);
  const integrity = await findOrphans(client);
  await client.end();
  writeFileSync(snapshotPath, JSON.stringify({ takenAt: new Date().toISOString(), state, integrity }, null, 2));
  const rows = Object.values(state.rowCounts).reduce((a, b) => a + b, 0);
  console.log(`  pg ${state.version} · ${state.tables.length} tables · ${rows} rows · ${state.indexes.length} indexes · ${state.enums.length} enums`);
  console.log(`  foreign keys checked: ${integrity.checked} · orphaned rows: ${integrity.orphans.length === 0 ? 'none' : integrity.orphans.length + ' FKs affected'}`);
  for (const o of integrity.orphans) console.log(`    ORPHANS ${o.detail}: ${o.count}`);
  console.log(`  written to ${snapshotPath}`);
  process.exit(0);
}

if (!targetUrl) {
  console.error('Set NEW_DATABASE_URL to the target database (and OLD_DATABASE_URL or --baseline for the source).');
  process.exit(2);
}

let oldState;
if (baselinePath) {
  oldState = JSON.parse(readFileSync(baselinePath, 'utf8')).state;
  console.log(`Source   : baseline file ${baselinePath}`);
} else {
  if (!sourceUrl) throw new Error('Set OLD_DATABASE_URL/DATABASE_URL or pass --baseline');
  console.log(`Source   : ${describe(sourceUrl)}`);
  const oldClient = await connect(sourceUrl);
  oldState = await inspect(oldClient);
  await oldClient.end();
}
console.log(`Target   : ${describe(targetUrl)}`);
console.log('');

const newClient = await connect(targetUrl);
const newState = await inspect(newClient);
const integrity = await findOrphans(newClient);
await newClient.end();

const results = [];

console.log('=== ROW COUNT VERIFICATION ===');
let rowsOk = true;
for (const t of oldState.tables) {
  const o = oldState.rowCounts[t];
  const n = newState.rowCounts[t];
  const pass = o === n;
  if (!pass) rowsOk = false;
  console.log(`  ${t.padEnd(30)} OLD ${String(o).padStart(6)}  NEW ${String(n ?? '—').padStart(6)}   ${pass ? 'PASS' : '*** FAIL ***'}`);
}
results.push({ label: 'row counts', ok: rowsOk, detail: `${oldState.tables.length} tables compared` });

console.log('');
console.log('=== STRUCTURE ===');
diffLists('tables', oldState.tables, newState.tables, results);
diffLists('columns', oldState.columns, newState.columns, results);
diffLists('indexes', oldState.indexes, newState.indexes, results);
diffLists('enums', oldState.enums, newState.enums, results);
diffLists('constraints', oldState.constraints, newState.constraints, results);
if (oldState.migrations) diffLists('prisma migrations', oldState.migrations, newState.migrations ?? [], results);

const majorOld = oldState.version.split('.')[0];
const majorNew = newState.version.split('.')[0];
results.push({
  label: 'pg major version',
  ok: majorOld === majorNew,
  detail: `old ${oldState.version} / new ${newState.version}`,
});

results.push({
  label: 'referential integrity',
  ok: integrity.orphans.length === 0,
  detail: `${integrity.checked} FKs walked, ${integrity.orphans.length} with orphans`,
});
for (const o of integrity.orphans) console.log(`  ORPHANS ${o.detail}: ${o.count}`);

console.log('');
console.log('=== SUMMARY ===');
for (const r of results) {
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.label.padEnd(22)} ${r.detail}`);
}

const allOk = results.every((r) => r.ok);
console.log('');
console.log(allOk ? 'VERDICT: PASS — safe to proceed to application smoke tests.' : 'VERDICT: FAIL — do NOT switch DATABASE_URL. Investigate the failures above.');
process.exit(allOk ? 0 : 1);
