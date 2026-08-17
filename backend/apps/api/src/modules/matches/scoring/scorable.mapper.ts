/**
 * Adapts a feed row (the loose `FeedProfileRow` shape the repository returns)
 * into the strict `ScorableProfile` the compatibility engine expects.
 *
 * It lives apart from CompatibilityService so that service stays a pure
 * function of plain objects — unit-testable without a Prisma row in sight —
 * while all the "this column might be a Decimal, a string, or absent" handling
 * sits in one place here.
 */
import type { FeedProfileRow } from '../repositories/feed.repository';
import type { PreferenceFilters } from '../filters/partner-preference-where.builder';
import type { ScorableProfile } from './compatibility.service';

function str(v: unknown): string | null {
  return typeof v === 'string' && v.trim().length > 0 ? v : null;
}

function num(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  // Prisma Decimal and bigint arrive as objects/strings.
  if (v !== null && v !== undefined) {
    const n = Number(v as never);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

function date(v: unknown): Date | null {
  if (v instanceof Date) return v;
  if (typeof v === 'string') {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function record(v: unknown): Record<string, unknown> {
  return v && typeof v === 'object' && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : {};
}

/** The candidate's own saved preference, if the select included it. */
export function preferenceOf(row: FeedProfileRow): PreferenceFilters | null {
  const user = record(row.user);
  const pref = user.partnerPreference;
  if (!pref || typeof pref !== 'object') return null;
  return pref as PreferenceFilters;
}

export function toScorable(row: FeedProfileRow): ScorableProfile {
  const user = record(row.user);
  return {
    userId: String(row.userId ?? ''),
    dob: date(row.dob),
    heightCm: num(row.heightCm),
    religion: str(row.religion),
    caste: str(row.caste),
    community: str(row.community),
    motherTongue: str(row.motherTongue),
    highestEducation: str(row.highestEducation),
    profession: str(row.profession),
    currentCity: str(row.currentCity),
    currentState: str(row.currentState),
    maritalStatus: str(row.maritalStatus),
    dietaryHabits: str(row.dietaryHabits),
    smokingHabits: str(row.smokingHabits),
    drinkingHabits: str(row.drinkingHabits),
    profileCompletePct: num(row.profileCompletePct),
    trustScore: num(user.trustScore),
    updatedAt: date(row.updatedAt),
    preference: preferenceOf(row),
  };
}
