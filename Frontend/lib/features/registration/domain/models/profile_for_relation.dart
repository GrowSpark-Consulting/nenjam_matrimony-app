/// Who a registration profile is being created for.
///
/// The catalogue of choices — and the exact string each one persists as —
/// is domain data, not presentation. [BasicDetails.profileCreatedFor] stores
/// [storageValue] verbatim, the backend stores it as a free-form string, and
/// [PostAuthDestination] reads it back to decide whether the question has
/// been answered at all. So the values must stay stable even when the
/// on-screen wording changes: screens map these to localized labels, and
/// nothing outside this enum may invent its own string.
enum ProfileForRelation {
  myself('Myself'),
  son('Son'),
  daughter('Daughter'),
  brother('Brother'),
  sister('Sister'),
  friend('Friend'),
  relative('Relative');

  const ProfileForRelation(this.storageValue);

  /// The value written to the draft and sent to the backend.
  final String storageValue;

  /// The option a previously stored draft value refers to.
  ///
  /// Null for an empty value (the question has never been answered — see
  /// [BasicDetails.profileCreatedFor]) and for a value this build no longer
  /// offers, so a stale draft resumes on "nothing selected" rather than
  /// silently keeping a choice the user can no longer see.
  static ProfileForRelation? fromStorage(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    for (final relation in values) {
      if (relation.storageValue == trimmed) return relation;
    }
    return null;
  }
}
