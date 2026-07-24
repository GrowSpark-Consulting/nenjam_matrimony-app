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

export class ProfileCompletionEntity {
  percentage!: number;
  completedSections!: string[];
  missingSections!: string[];
  breakdown!: ProfileCompletionModuleEntity[];
  verificationBreakdown!: VerificationSubStatusEntity[];
}
