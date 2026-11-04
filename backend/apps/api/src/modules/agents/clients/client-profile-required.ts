/**
 * THE list of fields an agent-added client's profile must have before the
 * agent can SUBMIT it (plan section 7.1, the starred fields). Drafts can be
 * saved without them; submit refuses with CLIENT_PROFILE_INCOMPLETE naming
 * the ones missing.
 *
 * This is the only place the list lives. Making a field optional is one
 * line here plus its test (client-profile-required.spec.ts); nothing else
 * reads a field's "required" status. The client's mobile number is required
 * too, but it is the draft's own phone (always present), not a profile field.
 *
 * Paths are `section.field` in the member wizard's own names (draft_data).
 * Religion and location are stored as master-data codes, so "religion" is
 * its code and "city and state" are their codes.
 */
export const CLIENT_PROFILE_REQUIRED_AT_SUBMIT = [
  // Full name
  'basicDetails.firstName',
  'basicDetails.lastName',
  'basicDetails.gender',
  'basicDetails.dob',
  'basicDetails.maritalStatus',
  'religionDetails.religionCode',
  // Current city and state
  'locationDetails.stateCode',
  'locationDetails.cityCode',
  // Highest education
  'educationDetails.qualification',
] as const;

export type ClientProfileRequiredField =
  (typeof CLIENT_PROFILE_REQUIRED_AT_SUBMIT)[number];
