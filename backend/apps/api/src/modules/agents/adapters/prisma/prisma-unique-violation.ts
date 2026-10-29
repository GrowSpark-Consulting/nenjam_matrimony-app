/**
 * Turns a Postgres unique violation, as Prisma reports it, into the
 * `AgentConflictError` the services already handle.
 *
 * Where the facts are. Checked against the real engine (this project runs
 * Prisma with `@prisma/adapter-pg`): a unique violation is a
 * `PrismaClientKnownRequestError` with `code: 'P2002'`, but its `meta` has NO
 * `target` here. The columns are at
 * `meta.driverAdapterError.cause.constraint.fields` (database column names,
 * for example `["phone_hash"]`) and the constraint or index name is only in
 * `meta.driverAdapterError.cause.originalMessage`
 * (`duplicate key value violates unique constraint "agents_phone_key"`).
 * The classic `meta.target` (an array, or a string for some engines) is read
 * too, so the mapping also works without a driver adapter.
 *
 * A rule matches on the constraint name when one can be read, else on the
 * set of columns. Anything that is not a unique violation, or matches no
 * rule, is returned untouched so a real bug is never hidden as a conflict.
 */
import {
  AgentConflictError,
  type AgentConflictReason,
} from '../../ports/agent-data-ports';

export interface UniqueViolation {
  /** Database column names, empty when the error did not carry them. */
  fields: string[];
  /** The constraint or index name, null when it could not be read. */
  constraint: string | null;
}

export interface UniqueViolationRule {
  /** The constraint or index name in the migration. */
  constraint: string;
  /** The columns it covers, used when the name is not available. */
  fields: readonly string[];
  reason: AgentConflictReason;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const strings = (value: unknown): string[] =>
  Array.isArray(value)
    ? value.filter((v): v is string => typeof v === 'string')
    : typeof value === 'string'
      ? [value]
      : [];

const CONSTRAINT_IN_MESSAGE = /unique constraint "([^"]+)"/;

/** The details of a unique violation, or null when `error` is anything else. */
export function readUniqueViolation(error: unknown): UniqueViolation | null {
  if (!isRecord(error)) return null;
  const meta = isRecord(error.meta) ? error.meta : undefined;

  // The error as the driver adapter reports it: either nested under `meta` of
  // a P2002, or the adapter error itself.
  const adapterError = isRecord(meta?.driverAdapterError)
    ? meta.driverAdapterError
    : error;
  const cause = isRecord(adapterError.cause) ? adapterError.cause : undefined;
  const isDriverUnique = cause?.kind === 'UniqueConstraintViolation';

  if (error.code !== 'P2002' && !isDriverUnique) return null;

  const constraintInfo = isRecord(cause?.constraint)
    ? cause.constraint
    : undefined;
  const fields = [...strings(constraintInfo?.fields), ...strings(meta?.target)];
  const fromMessage =
    typeof cause?.originalMessage === 'string'
      ? CONSTRAINT_IN_MESSAGE.exec(cause.originalMessage)?.[1]
      : undefined;
  const constraint =
    fromMessage ??
    (typeof constraintInfo?.index === 'string' ? constraintInfo.index : null) ??
    null;
  return { fields, constraint };
}

const sameSet = (a: readonly string[], b: readonly string[]) =>
  a.length === b.length && a.every((x) => b.includes(x));

/**
 * The conflict for a unique violation that one of the `rules` describes, or
 * null (not a unique violation, or not one of ours).
 */
export function mapUniqueViolation(
  error: unknown,
  rules: readonly UniqueViolationRule[],
): AgentConflictError | null {
  const violation = readUniqueViolation(error);
  if (violation === null) return null;
  const rule = rules.find((r) =>
    violation.constraint !== null
      ? r.constraint === violation.constraint
      : sameSet(r.fields, violation.fields),
  );
  return rule ? new AgentConflictError(rule.reason) : null;
}

/** Runs `write`; a unique violation described by `rules` becomes an `AgentConflictError`. */
export async function withConflictMapping<T>(
  rules: readonly UniqueViolationRule[],
  write: () => Promise<T>,
): Promise<T> {
  try {
    return await write();
  } catch (error) {
    throw mapUniqueViolation(error, rules) ?? error;
  }
}
