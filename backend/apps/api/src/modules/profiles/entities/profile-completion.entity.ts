// Computed by ProfileService from the finalized profile — distinct from
// ProfileDraftService's completionPercentage, which tracks in-progress
// wizard draftData before finalize() has ever run.
export class ProfileCompletionEntity {
  percentage!: number;
  completedSections!: string[];
  missingSections!: string[];
}
