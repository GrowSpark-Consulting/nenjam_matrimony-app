import { readFileSync } from 'node:fs';
import { join } from 'node:path';
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

describe('the contract says the same', () => {
  it("agent-api.openapi.yaml's x-required-at-submit is this list, in this order", () => {
    const yaml = readFileSync(
      join(
        __dirname,
        '../../../../../../../docs/agent-program/agent-api.openapi.yaml',
      ),
      'utf8',
    );
    const at = yaml.indexOf('      x-required-at-submit:\n');
    expect(at).toBeGreaterThan(0);
    const listed: string[] = [];
    for (const line of yaml.slice(at).split('\n').slice(1)) {
      const item = /^ {8}- (\S+)$/.exec(line);
      if (!item) break;
      listed.push(item[1]);
    }
    expect(listed).toEqual([...CLIENT_PROFILE_REQUIRED_AT_SUBMIT]);
  });
});
