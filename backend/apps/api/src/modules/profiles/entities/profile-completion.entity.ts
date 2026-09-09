// Computed by ProfileCompletionService — the single authoritative profile
// completion score, shared by ProfileService (finalized profile,
// GET /profiles/me) and ProfileDraftService (in-progress wizard draft,
// GET /profiles/draft). Both surface the exact same number, computed the
// exact same way.
export class ProfileCompletionModuleEntity {
  id!: string;
  weight!: number;
  // Points actually earned toward this module's weight. Every module here is
  // currently binary (earned = isComplete ? weight : 0) except
  // 'verification', which earns partial credit per verified flag (see
  // VerificationSubStatusEntity) — exposed so the client never has to
  // recompute `weight * isComplete` (or worse, guess at partial verification
  // progress) itself.
  earned!: number;
  isComplete!: boolean;
  // Wizard step to jump into for "improve this" — 0-indexed, matching the
  // Flutter wizard's step pages. Null for modules with no wizard step
  // (verification lives on its own screen, not a wizard step).
  wizardStep!: number | null;
}

// One of the 5 independent verification flags inside the 'verification'
// module (5% each, 25% total). isVerified reflects only an approved/real
// signal — see ProfileCompletionService.calculate for what backs each id.
export class VerificationSubStatusEntity {
  id!: 'mobile' | 'income' | 'asset' | 'aadhaar' | 'nri';
  weight!: number;
  isVerified!: boolean;
}

// One of the 21 registration answers Edit Profile asks for, in screen order.
// Exposed so the client can say *which* answers are missing rather than only
// that a section is incomplete, and can deep-link to the step that fixes each.
// See profiles/validation/required-fields.ts for the list and what counts as
// an answer.
export class RequiredFieldStatusEntity {
  id!: string;
  section!: string;
  wizardStep!: number;
  isComplete!: boolean;
  // Sub-community is the only one. Listed so it can be rendered in place, but
  // excluded from the score in both directions.
  optional!: boolean;
}

export class ProfileCompletionEntity {
  percentage!: number;
  completedSections!: string[];
  missingSections!: string[];
  breakdown!: ProfileCompletionModuleEntity[];
  verificationBreakdown!: VerificationSubStatusEntity[];
  // Field-level detail behind the 'registration' module: the 21 draft fields
  // in screen order, then the profile photo. Kept populated even when
  // everything is answered, for deep-linking and for spotting a legacy
  // profile's genuine gaps.
  requiredFields!: RequiredFieldStatusEntity[];
  // Whether every counted registration item is answered. The client hides the
  // whole "Registration information" group on this rather than filtering
  // requiredFields itself — a newly registered member must not be asked for
  // what they just gave.
  registrationComplete!: boolean;
}
