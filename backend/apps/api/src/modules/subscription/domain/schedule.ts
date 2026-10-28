/**
 * When a newly bought (or granted) plan runs — the one rule, shared by
 * activation and by the purchase options GET /membership/me shows, so what a
 * member is told before paying is exactly what activation then does.
 *
 *  - UPGRADE (a higher tier than anything the member holds): starts now,
 *    overlapping the lower plan, which resumes if it outlives the upgrade.
 *  - RENEWAL (same tier) / DOWNGRADE (lower tier): queued to start when the
 *    member's last same-or-higher plan ends.
 *  - NEW (no paid plan at all): starts now.
 *
 * Nothing already bought is shortened; there is no proration.
 */

export type PurchaseKind = 'NEW' | 'UPGRADE' | 'RENEWAL' | 'DOWNGRADE';

/** A paid plan the member holds: ACTIVE and not yet ended (in force now or
 *  queued to start later). */
export interface HeldPlan {
  endDate: Date;
  tier: number;
}

export interface PlanWindow {
  kind: PurchaseKind;
  startDate: Date;
  endDate: Date;
  /** True when it starts later than [now] (queued). */
  scheduled: boolean;
}

export function windowFor(
  held: HeldPlan[],
  tier: number,
  termMs: number,
  now: Date,
): PlanWindow {
  const highestHeld = held.reduce<number | null>(
    (max, plan) => (max === null || plan.tier > max ? plan.tier : max),
    null,
  );
  const kind: PurchaseKind =
    highestHeld === null
      ? 'NEW'
      : tier > highestHeld
        ? 'UPGRADE'
        : tier === highestHeld
          ? 'RENEWAL'
          : 'DOWNGRADE';

  const queueBehind = held
    .filter((plan) => plan.tier >= tier)
    .reduce<Date | null>(
      (latest, plan) =>
        !latest || plan.endDate > latest ? plan.endDate : latest,
      null,
    );
  const startDate = queueBehind && queueBehind > now ? queueBehind : now;
  return {
    kind,
    startDate,
    endDate: new Date(startDate.getTime() + termMs),
    scheduled: startDate.getTime() > now.getTime(),
  };
}
