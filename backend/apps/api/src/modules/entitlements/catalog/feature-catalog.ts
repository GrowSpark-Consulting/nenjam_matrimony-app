/**
 * The membership feature registry: every feature a plan can grant, by a
 * stable id, with what KIND of value configures it and how it is metered.
 *
 * This file defines what features MEAN. It holds no plan values — what Free,
 * Gold and Platinum actually grant lives in the database
 * (`subscription_plan_versions.entitlements`), is validated against this
 * registry on every load and every publish, and changes without a deploy.
 * Adding a feature is one entry here plus the code that enforces it; it never
 * needs a new column.
 *
 * Value shapes, by kind:
 *  - `boolean` — `true` / `false`.
 *  - `level`   — one of the feature's `levels`, ordered lowest to highest.
 *  - `cap`     — `{ limit }`: the most a member may hold at once (photos,
 *                shortlist). `limit: null` = unlimited.
 *  - `quota`   — `{ limit }` consumed per `period` (IST day / IST month / the
 *                subscription's own term). `limit: null` = unlimited, and an
 *                unlimited quota may carry a `fairUse` hard cap. A
 *                SUBSCRIPTION-period quota may scale with the plan length:
 *                `{ limit: 60, perMonths: 3 }` is 60 per 3 months bought.
 *
 * Never configurable, and therefore deliberately absent: blocking,
 * reporting, hiding a profile, photo privacy, contact privacy and number
 * masking, and government-ID verification itself. Safety is never paywalled
 * (see NEVER_GATED_SAFETY_CAPABILITIES). Features marked
 * `requiredOnEveryPlan` must be granted by every plan, Free included — the
 * validator refuses a version that turns one off.
 */

export type FeatureKind = 'boolean' | 'level' | 'cap' | 'quota';

/** Usage-period boundaries, all on the Indian (IST, UTC+05:30) calendar. */
export type QuotaPeriod = 'DAY' | 'MONTH' | 'SUBSCRIPTION';

export type FeatureSection =
  | 'PROFILE'
  | 'VERIFICATION'
  | 'DISCOVERY'
  | 'INTERESTS'
  | 'COMMUNICATION'
  | 'CONTACT'
  | 'HOROSCOPE'
  | 'VISIBILITY'
  | 'INSIGHTS'
  | 'PRIVACY'
  | 'SUPPORT';

interface FeatureBase {
  section: FeatureSection;
  /** Sentence-case name, used in denial messages: "Starting a conversation". */
  label: string;
  /** Plural noun for counted features, used in limit messages: "interests". */
  noun?: string;
  /** Must be granted (true / non-zero) by every plan — see file doc. */
  requiredOnEveryPlan?: boolean;
}

export type FeatureDefinition =
  | (FeatureBase & { kind: 'boolean' })
  | (FeatureBase & { kind: 'level'; levels: readonly string[] })
  | (FeatureBase & { kind: 'cap' })
  | (FeatureBase & {
      kind: 'quota';
      period: QuotaPeriod;
      /** Charged once per distinct item (profile, contact) per period. */
      perItem?: boolean;
    });

export const FEATURES = {
  // ── Profile ──────────────────────────────────────────────────────────────
  'profile.photos': {
    kind: 'cap',
    section: 'PROFILE',
    label: 'Photo uploads',
    noun: 'photos',
  },
  'profile.video_intro': {
    kind: 'boolean',
    section: 'PROFILE',
    label: 'A profile video',
  },
  'profile.horoscope_upload': {
    kind: 'boolean',
    section: 'PROFILE',
    label: 'Uploading your jathagam',
  },
  'profile.family_managed': {
    kind: 'boolean',
    section: 'PROFILE',
    label: 'A family-managed profile',
  },
  'profile.badge': {
    kind: 'level',
    section: 'PROFILE',
    label: 'A paid-member badge',
    levels: ['NONE', 'GOLD', 'PLATINUM'],
  },
  'profile.makeover_sessions': {
    kind: 'quota',
    section: 'PROFILE',
    label: 'Profile makeover sessions',
    noun: 'profile makeover sessions',
    period: 'MONTH',
  },
  'profile.full_details': {
    kind: 'boolean',
    section: 'CONTACT',
    label: "Seeing members' full name, college and employer",
  },

  // ── Verification & trust ────────────────────────────────────────────────
  // ID verification itself is free for everyone; plans only change how fast
  // the review is.
  'verification.id_review': {
    kind: 'level',
    section: 'VERIFICATION',
    label: 'ID verification review',
    levels: ['STANDARD', 'PRIORITY'],
  },
  // Product correction to the PDF: verified-only browsing is free on every
  // plan, so it can never be configured off.
  'search.verified_only': {
    kind: 'boolean',
    section: 'VERIFICATION',
    label: 'Browsing verified profiles only',
    requiredOnEveryPlan: true,
  },

  // ── Discovery & search ──────────────────────────────────────────────────
  'discovery.daily_recommendations': {
    kind: 'quota',
    section: 'DISCOVERY',
    label: 'Daily match recommendations',
    noun: 'match recommendations',
    period: 'DAY',
  },
  'discovery.profile_views': {
    kind: 'quota',
    section: 'DISCOVERY',
    label: 'Profile browsing',
    noun: 'profiles',
    period: 'DAY',
    perItem: true,
  },
  'discovery.mutual_matches': {
    kind: 'boolean',
    section: 'DISCOVERY',
    label: 'The mutual-matches view',
  },
  'search.basic_filters': {
    kind: 'boolean',
    section: 'DISCOVERY',
    label: 'Basic search filters',
    requiredOnEveryPlan: true,
  },
  'search.community_filters': {
    kind: 'boolean',
    section: 'DISCOVERY',
    label: 'Community, sub-caste, raasi and natchathiram filters',
  },
  'search.power_filters': {
    kind: 'boolean',
    section: 'DISCOVERY',
    label: 'Power filters',
  },
  'search.nri_filters': {
    kind: 'boolean',
    section: 'DISCOVERY',
    label: 'NRI and country filters',
  },
  'search.saved_searches': {
    kind: 'cap',
    section: 'DISCOVERY',
    label: 'Saved searches',
    noun: 'saved searches',
  },

  // ── Interests & shortlist ───────────────────────────────────────────────
  'interests.send': {
    kind: 'quota',
    section: 'INTERESTS',
    label: 'Sending interests',
    noun: 'interests',
    period: 'MONTH',
  },
  'interests.respond': {
    kind: 'boolean',
    section: 'INTERESTS',
    label: 'Accepting or declining interests',
    requiredOnEveryPlan: true,
  },
  'interests.personal_note': {
    kind: 'boolean',
    section: 'INTERESTS',
    label: 'Adding a personal note to an interest',
  },
  'shortlist.profiles': {
    kind: 'cap',
    section: 'INTERESTS',
    label: 'Shortlisting',
    noun: 'shortlisted profiles',
  },

  // ── Communication ───────────────────────────────────────────────────────
  'chat.initiate': {
    kind: 'boolean',
    section: 'COMMUNICATION',
    label: 'Starting a conversation',
  },
  // Replying when someone messaged you first — free on every plan.
  'chat.reply': {
    kind: 'boolean',
    section: 'COMMUNICATION',
    label: 'Replying to messages',
    requiredOnEveryPlan: true,
  },
  'chat.read_receipts': {
    kind: 'boolean',
    section: 'COMMUNICATION',
    label: 'Read receipts',
  },
  // Lets members WITHOUT chat.initiate start a conversation with this member.
  'chat.accept_from_free_members': {
    kind: 'boolean',
    section: 'COMMUNICATION',
    label: 'Letting free members contact you',
  },
  'calls.voice': {
    kind: 'boolean',
    section: 'COMMUNICATION',
    label: 'In-app voice calls',
  },
  'calls.video': {
    kind: 'boolean',
    section: 'COMMUNICATION',
    label: 'In-app video calls',
  },

  // ── Contact & profile depth ─────────────────────────────────────────────
  // A per-plan pool, not monthly (PDF design principle).
  'contacts.unlocks': {
    kind: 'quota',
    section: 'CONTACT',
    label: 'Viewing contact numbers',
    noun: 'contact numbers',
    period: 'SUBSCRIPTION',
    perItem: true,
  },
  'photos.private_access': {
    kind: 'boolean',
    section: 'CONTACT',
    label: 'Seeing private photos after acceptance',
  },
  'contacts.whatsapp_share': {
    kind: 'boolean',
    section: 'CONTACT',
    label: 'WhatsApp sharing after mutual acceptance',
  },

  // ── Horoscope ───────────────────────────────────────────────────────────
  'horoscope.basic_score': {
    kind: 'boolean',
    section: 'HOROSCOPE',
    label: 'The basic porutham score',
  },
  'horoscope.full_jathagam': {
    kind: 'boolean',
    section: 'HOROSCOPE',
    label: "Viewing others' full jathagam",
  },
  'horoscope.detailed_report': {
    kind: 'boolean',
    section: 'HOROSCOPE',
    label: 'The detailed 10-porutham report',
  },
  'horoscope.astrologer_minutes': {
    kind: 'quota',
    section: 'HOROSCOPE',
    label: 'Astrologer consultation',
    noun: 'consultation minutes',
    period: 'MONTH',
  },

  // ── Visibility ──────────────────────────────────────────────────────────
  'visibility.search_priority': {
    kind: 'level',
    section: 'VISIBILITY',
    label: 'Search ranking priority',
    levels: ['STANDARD', 'PRIORITY', 'HIGHEST'],
  },
  'visibility.boost_days': {
    kind: 'quota',
    section: 'VISIBILITY',
    label: 'Profile boosts',
    noun: 'boost days',
    period: 'MONTH',
  },
  'visibility.featured': {
    kind: 'boolean',
    section: 'VISIBILITY',
    label: 'Featured listing',
  },

  // ── Insights ────────────────────────────────────────────────────────────
  'insights.profile_viewers': {
    kind: 'level',
    section: 'INSIGHTS',
    label: 'Seeing who viewed your profile',
    levels: ['PREVIEW', 'FULL', 'FULL_WITH_TRENDS'],
  },
  // How many viewers the PREVIEW level shows.
  'insights.profile_viewers_visible': {
    kind: 'cap',
    section: 'INSIGHTS',
    label: 'Profile viewers shown',
    noun: 'profile viewers',
  },
  'insights.shortlisted_by': {
    kind: 'level',
    section: 'INSIGHTS',
    label: 'Seeing who shortlisted you',
    levels: ['COUNT', 'FULL'],
  },
  'insights.performance_stats': {
    kind: 'level',
    section: 'INSIGHTS',
    label: 'Profile performance stats',
    levels: ['NONE', 'BASIC', 'DETAILED'],
  },

  // ── Privacy (paid extras only — the safety controls are never here) ──────
  'privacy.incognito': {
    kind: 'boolean',
    section: 'PRIVACY',
    label: 'Incognito browsing',
  },

  // ── Support ─────────────────────────────────────────────────────────────
  'support.tier': {
    kind: 'level',
    section: 'SUPPORT',
    label: 'Customer support',
    levels: ['STANDARD', 'PRIORITY', 'DEDICATED'],
  },
} as const satisfies Record<string, FeatureDefinition>;

export type FeatureKey = keyof typeof FEATURES;

type KeysOfKind<K extends FeatureKind> = {
  [F in FeatureKey]: (typeof FEATURES)[F]['kind'] extends K ? F : never;
}[FeatureKey];

export type BooleanFeatureKey = KeysOfKind<'boolean'>;
export type LevelFeatureKey = KeysOfKind<'level'>;
export type CapFeatureKey = KeysOfKind<'cap'>;
export type QuotaFeatureKey = KeysOfKind<'quota'>;

export const FEATURE_KEYS = Object.keys(FEATURES) as FeatureKey[];

/** The capabilities the PDF lists under "never paywalled". None of them is a
 *  catalogue feature, and a test keeps it that way. */
/**
 * Hard caps that existed before membership plans, which still apply whenever
 * plan limits are NOT enforced (MEMBERSHIP_ENFORCEMENT_MODE off/shadow), so
 * those modes behave exactly as before. One definition, used by the feature
 * that enforces it and by GET /membership/me (`effectiveCaps`), so the app is
 * never left to guess which number applies.
 */
export const LEGACY_CAP_LIMITS: Partial<Record<CapFeatureKey, number>> = {
  'profile.photos': 6,
};

export const NEVER_GATED_SAFETY_CAPABILITIES = [
  'block',
  'report',
  'hide_profile',
  'photo_privacy',
  'contact_privacy',
  'number_masking',
  'id_verification',
] as const;

/** A cap or quota value. `limit: null` is unlimited. */
export interface LimitValue {
  limit: number | null;
  /** SUBSCRIPTION quotas only: `limit` per this many months of plan. */
  perMonths?: number;
  /** Unlimited (`limit: null`) quotas only: a hard fair-use cap per period. */
  fairUse?: number;
}

export type EntitlementValue = boolean | string | LimitValue;

/** Every feature, fully populated (missing keys take their safe default). */
export type EntitlementMap = {
  [F in FeatureKey]: (typeof FEATURES)[F]['kind'] extends 'boolean'
    ? boolean
    : (typeof FEATURES)[F]['kind'] extends 'level'
      ? string
      : LimitValue;
};

export function definitionOf(feature: FeatureKey): FeatureDefinition {
  return FEATURES[feature];
}

/**
 * The value a feature takes when a stored version doesn't mention it — a
 * version published before the feature existed, or a corrupted row. Always
 * the most restrictive value, except for features every plan must grant, so
 * adding a paid feature never grants it to anyone retroactively and a broken
 * row can never take away a free right.
 */
export function defaultValueOf(feature: FeatureKey): EntitlementValue {
  const def: FeatureDefinition = FEATURES[feature];
  switch (def.kind) {
    case 'boolean':
      return def.requiredOnEveryPlan === true;
    case 'level':
      return def.levels[0];
    case 'cap':
    case 'quota':
      return { limit: def.requiredOnEveryPlan ? null : 0 };
  }
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isNonNegativeInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0;
}

/** Problems with one feature's value, or [] when it is valid. */
function valueProblems(feature: FeatureKey, value: unknown): string[] {
  const def: FeatureDefinition = FEATURES[feature];
  switch (def.kind) {
    case 'boolean':
      if (typeof value !== 'boolean')
        return [`${feature} must be true or false`];
      if (def.requiredOnEveryPlan && value !== true) {
        return [`${feature} must be enabled on every plan`];
      }
      return [];
    case 'level':
      return typeof value === 'string' && def.levels.includes(value)
        ? []
        : [`${feature} must be one of ${def.levels.join(', ')}`];
    case 'cap':
    case 'quota': {
      if (!isPlainObject(value)) return [`${feature} must be { limit }`];
      const problems: string[] = [];
      const allowed = new Set(
        def.kind === 'quota'
          ? [
              'limit',
              'fairUse',
              ...(def.period === 'SUBSCRIPTION' ? ['perMonths'] : []),
            ]
          : ['limit'],
      );
      for (const key of Object.keys(value)) {
        if (!allowed.has(key))
          problems.push(`${feature}.${key} is not allowed`);
      }
      const { limit, perMonths, fairUse } = value;
      if (limit !== null && !isNonNegativeInteger(limit)) {
        problems.push(
          `${feature}.limit must be a whole number >= 0, or null for unlimited`,
        );
      }
      if (
        perMonths !== undefined &&
        (!isNonNegativeInteger(perMonths) || perMonths === 0)
      ) {
        problems.push(`${feature}.perMonths must be a whole number >= 1`);
      }
      if (fairUse !== undefined) {
        if (limit !== null) {
          problems.push(
            `${feature}.fairUse only applies when limit is null (unlimited)`,
          );
        } else if (!isNonNegativeInteger(fairUse) || fairUse === 0) {
          problems.push(`${feature}.fairUse must be a whole number >= 1`);
        }
      }
      if (def.requiredOnEveryPlan && limit === 0) {
        problems.push(`${feature} must be granted on every plan`);
      }
      return problems;
    }
  }
}

export interface ParsedEntitlements {
  map: EntitlementMap;
  /** Every problem found; empty for a clean version. */
  problems: string[];
}

/**
 * Reads a stored version leniently: unknown keys are ignored, and a missing
 * or invalid value falls back to [defaultValueOf]. Problems are returned for
 * logging, never thrown — a bad row must degrade one feature, not the app.
 */
export function parseEntitlements(raw: unknown): ParsedEntitlements {
  const problems: string[] = [];
  const source = isPlainObject(raw) ? raw : {};
  if (!isPlainObject(raw)) problems.push('entitlements is not an object');

  const map = {} as Record<FeatureKey, EntitlementValue>;
  for (const feature of FEATURE_KEYS) {
    if (!(feature in source)) {
      problems.push(`${feature} is missing`);
      map[feature] = defaultValueOf(feature);
      continue;
    }
    const issues = valueProblems(feature, source[feature]);
    if (issues.length > 0) {
      problems.push(...issues);
      map[feature] = defaultValueOf(feature);
    } else {
      map[feature] = source[feature] as EntitlementValue;
    }
  }
  for (const key of Object.keys(source)) {
    if (!(key in FEATURES)) problems.push(`${key} is not a known feature`);
  }
  return { map: map as EntitlementMap, problems };
}

/**
 * Strict validation for publishing a new version: every known feature must be
 * present and valid, and nothing unknown may be present. Returns the problems
 * (empty = publishable).
 */
export function validateEntitlementsForPublish(raw: unknown): string[] {
  const { problems } = parseEntitlements(raw);
  return problems;
}

/** Plan length in months, for SUBSCRIPTION-period `perMonths` scaling. */
export interface LimitContext {
  subscriptionMonths?: number | null;
}

export interface EffectiveLimit {
  /** The cap to enforce this period; null = genuinely unlimited. */
  limit: number | null;
  /** True when [limit] comes from a fair-use cap on an "unlimited" value. */
  fairUse: boolean;
}

/**
 * What a cap/quota value means for one member right now. `perMonths` scales
 * by whole blocks of the plan length (6 months at 60 per 3 = 120); without a
 * plan length (a Free member) one block applies.
 */
export function effectiveLimit(
  value: LimitValue,
  context: LimitContext = {},
): EffectiveLimit {
  if (value.limit === null) {
    return value.fairUse !== undefined
      ? { limit: value.fairUse, fairUse: true }
      : { limit: null, fairUse: false };
  }
  if (value.perMonths !== undefined && context.subscriptionMonths) {
    const blocks = Math.max(
      1,
      Math.ceil(context.subscriptionMonths / value.perMonths),
    );
    return { limit: value.limit * blocks, fairUse: false };
  }
  return { limit: value.limit, fairUse: false };
}

/** Comparable "how generous" for a limit value: unlimited beats any number;
 *  scaled values compare per month. */
function generosity(value: LimitValue): number {
  if (value.limit === null) return Number.POSITIVE_INFINITY;
  return value.perMonths ? value.limit / value.perMonths : value.limit;
}

/**
 * The features [next] grants LESS of than [previous] — empty when [next] is
 * at least as generous everywhere. This is the gate for applying a new
 * version to people who already bought the old one: an improvement may be
 * applied to them; a reduction may only apply to new purchases.
 */
export function reductionsBetween(
  previous: EntitlementMap,
  next: EntitlementMap,
): FeatureKey[] {
  const reduced: FeatureKey[] = [];
  for (const feature of FEATURE_KEYS) {
    const def: FeatureDefinition = FEATURES[feature];
    const before = previous[feature];
    const after = next[feature];
    switch (def.kind) {
      case 'boolean':
        if (before === true && after !== true) reduced.push(feature);
        break;
      case 'level':
        if (
          def.levels.indexOf(after as string) <
          def.levels.indexOf(before as string)
        ) {
          reduced.push(feature);
        }
        break;
      case 'cap':
      case 'quota': {
        const b = before as LimitValue;
        const a = after as LimitValue;
        if (generosity(a) < generosity(b)) {
          reduced.push(feature);
        } else if (
          b.limit === null &&
          a.limit === null &&
          b.fairUse === undefined &&
          a.fairUse !== undefined
        ) {
          // Unlimited -> unlimited-with-a-fair-use-cap is still a reduction.
          reduced.push(feature);
        } else if (
          a.fairUse !== undefined &&
          b.fairUse !== undefined &&
          a.fairUse < b.fairUse
        ) {
          reduced.push(feature);
        }
        break;
      }
    }
  }
  return reduced;
}

/** Whether a membership's value grants the feature at all (boolean true, a
 *  level above the lowest, or a non-zero cap/quota). */
export function grants(feature: FeatureKey, value: EntitlementValue): boolean {
  const def: FeatureDefinition = FEATURES[feature];
  switch (def.kind) {
    case 'boolean':
      return value === true;
    case 'level':
      return def.levels.indexOf(value as string) > 0;
    case 'cap':
    case 'quota':
      return (value as LimitValue).limit !== 0;
  }
}
