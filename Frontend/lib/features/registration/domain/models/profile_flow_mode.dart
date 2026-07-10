/// Distinguishes first-time profile creation from editing an existing,
/// already-finalized profile. Both flows reuse the same wizard/review UI —
/// this only changes save destinations and a couple of labels.
enum ProfileFlowMode { create, edit }
