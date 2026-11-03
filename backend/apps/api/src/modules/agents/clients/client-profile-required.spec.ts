import { CLIENT_PROFILE_REQUIRED_AT_SUBMIT } from './client-profile-required';
import { CLIENT_PROFILE_FIELDS } from './client-profile';

describe('CLIENT_PROFILE_REQUIRED_AT_SUBMIT', () => {
  it('is exactly the starred fields of plan section 7.1 (the phone is the draft’s own)', () => {
    expect([...CLIENT_PROFILE_REQUIRED_AT_SUBMIT]).toEqual([
      'basicDetails.firstName',
      'basicDetails.lastName',
      'basicDetails.gender',
      'basicDetails.dob',
      'basicDetails.maritalStatus',
      'religionDetails.religionCode',
      'locationDetails.stateCode',
      'locationDetails.cityCode',
      'educationDetails.qualification',
    ]);
  });

  it('names only fields the profile has', () => {
    for (const path of CLIENT_PROFILE_REQUIRED_AT_SUBMIT) {
      const [section, field] = path.split('.');
      expect([
        path,
        field in
          (CLIENT_PROFILE_FIELDS as Record<string, Record<string, unknown>>)[
            section
          ],
      ]).toEqual([path, true]);
    }
  });
});
