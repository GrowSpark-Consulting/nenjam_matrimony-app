import type {
  EntitlementValue,
  FeatureDescriptor,
  LimitValue,
} from './types';

/** "5 per month", "Unlimited (fair use 300/day)", "Yes", "PRIORITY". */
export function describeValue(
  feature: FeatureDescriptor,
  value: EntitlementValue | undefined,
): string {
  if (value === undefined) return '—';
  if (feature.kind === 'boolean') return value === true ? 'Yes' : 'No';
  if (feature.kind === 'level') return typeof value === 'string' ? value : '—';
  const limit = value as LimitValue;
  if (typeof limit !== 'object' || limit === null) return '—';
  const period =
    feature.kind === 'quota' && feature.period
      ? feature.period === 'SUBSCRIPTION'
        ? limit.perMonths
          ? ` per ${limit.perMonths} months`
          : ' per plan'
        : ` per ${feature.period.toLowerCase()}`
      : '';
  if (limit.limit === null) {
    return limit.fairUse ? `Unlimited (fair use ${limit.fairUse}${period})` : 'Unlimited';
  }
  return `${limit.limit}${period}`;
}

/** A feature whose value differs between two maps (key order ignored). */
export function sameValue(a: unknown, b: unknown): boolean {
  return canonical(a) === canonical(b);
}

function canonical(value: unknown): string {
  return JSON.stringify(value, (_key, v: unknown) =>
    v && typeof v === 'object' && !Array.isArray(v)
      ? Object.fromEntries(
          Object.entries(v as Record<string, unknown>).sort(([x], [y]) =>
            x.localeCompare(y),
          ),
        )
      : v,
  );
}

/** Features grouped by section, in registry order. */
export function bySection(
  features: readonly FeatureDescriptor[],
): Array<[string, FeatureDescriptor[]]> {
  const groups = new Map<string, FeatureDescriptor[]>();
  for (const feature of features) {
    const list = groups.get(feature.section) ?? [];
    list.push(feature);
    groups.set(feature.section, list);
  }
  return [...groups.entries()];
}
