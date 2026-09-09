/**
 * The "Complete Your Profile" recommendation cards, and the only place their
 * keys, order and score relationship are decided.
 *
 * These are NOT a second scoring model. The percentage stays exactly where it
 * has always been — ProfileCompletionService's four weighted slices
 * (registration 60, family 10, horoscope 5, verification 25). A card is just a
 * suggestion built on top of a completion signal, which is why `psychology`
 * can appear here with `affectsScore: false` and no weight at all: it is
 * offered, it is never counted, and adding it moved no member's percentage.
 *
 * Home and Edit Profile both render this same list from the same response, so
 * finishing a section on one screen removes the card from the other on the
 * next refresh without either screen owning a rule of its own.
 */

/** Stable card ids, shared verbatim with the Flutter client. */
export const RECOMMENDATION_CARD_KEYS = [
  'registration',
  'photo',
  'about_family',
  'horoscope',
  'verification',
  'psychology',
] as const;

export type RecommendationCardKey = (typeof RECOMMENDATION_CARD_KEYS)[number];

const KEY_SET = new Set<string>(RECOMMENDATION_CARD_KEYS);

/**
 * Whether [key] is a card this build knows.
 *
 * The dismissal endpoint validates against this so a typo can never write a
 * row that hides nothing and is invisible to the member forever.
 */
export function isRecommendationCardKey(
  key: string,
): key is RecommendationCardKey {
  return KEY_SET.has(key);
}

export interface RecommendationCardDefinition {
  key: RecommendationCardKey;
  /**
   * Wizard step the client opens for this card, in the same 0-indexed
   * `ProfileDraft` step numbering `wizardStep` already uses on the completion
   * modules — so the client keeps one route table (`profileSectionRoute`)
   * rather than growing a second one for cards.
   */
  wizardStep: number;
  /**
   * Whether finishing this card moves the percentage. False only for
   * `psychology`, which is offered as optional until its scoring is approved.
   */
  affectsScore: boolean;
  /**
   * True for the two cards that stand in for an unfinished registration.
   * They are shown *instead of* the section cards, never alongside them —
   * a member who has not finished signing up should be asked for that and
   * nothing else.
   */
  registrationGroup: boolean;
}

/** In display order — the order Home and Edit Profile lay the cards out in. */
export const RECOMMENDATION_CARDS: readonly RecommendationCardDefinition[] = [
  {
    key: 'registration',
    wizardStep: 0,
    affectsScore: true,
    registrationGroup: true,
  },
  // Step 11 is the photos step, matching PROFILE_PHOTO_ITEM.wizardStep.
  { key: 'photo', wizardStep: 11, affectsScore: true, registrationGroup: true },
  {
    key: 'about_family',
    wizardStep: 7,
    affectsScore: true,
    registrationGroup: false,
  },
  {
    key: 'horoscope',
    wizardStep: 8,
    affectsScore: true,
    registrationGroup: false,
  },
  {
    key: 'verification',
    wizardStep: 12,
    affectsScore: true,
    registrationGroup: false,
  },
  {
    key: 'psychology',
    wizardStep: 9,
    affectsScore: false,
    registrationGroup: false,
  },
];
