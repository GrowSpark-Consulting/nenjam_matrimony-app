import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  fakeLocations,
  fakeReligions,
} from '../../testing/fake-client-reference-data';
import { ReferenceDataClientLabels } from './reference-data-client-labels';

const labels = new ReferenceDataClientLabels(fakeLocations, fakeReligions);

describe('ReferenceDataClientLabels', () => {
  it('fills in the labels from the codes, keeping every other field', async () => {
    await expect(
      labels.withLabels({
        basicDetails: { firstName: 'Priya' },
        religionDetails: {
          religionCode: 'HINDU',
          communityCode: 'HINDU-VELLALAR',
          subCaste: 'Pillai',
        },
        locationDetails: {
          countryCode: 'IN',
          stateCode: 'IN-TN',
          cityCode: 'IN-TN-MADURAI',
          nativePlace: 'Tirunelveli',
        },
      }),
    ).resolves.toEqual({
      ok: true,
      profile: {
        basicDetails: { firstName: 'Priya' },
        religionDetails: {
          religionCode: 'HINDU',
          communityCode: 'HINDU-VELLALAR',
          subCaste: 'Pillai',
          religion: 'Hindu',
          community: 'Vellalar',
        },
        locationDetails: {
          countryCode: 'IN',
          stateCode: 'IN-TN',
          cityCode: 'IN-TN-MADURAI',
          nativePlace: 'Tirunelveli',
          country: 'India',
          state: 'Tamil Nadu',
          city: 'Madurai',
        },
      },
    });
  });

  it('a label handed in is replaced by the master data’s, never kept', async () => {
    const result = await labels.withLabels({
      religionDetails: { religionCode: 'HINDU', religion: 'Not this' },
      locationDetails: { countryCode: 'IN', country: 'Not this either' },
    });
    expect(result).toEqual({
      ok: true,
      profile: {
        religionDetails: { religionCode: 'HINDU', religion: 'Hindu' },
        locationDetails: { countryCode: 'IN', country: 'India' },
      },
    });
  });

  it('a section without codes gets no label (none is ever taken from the caller)', async () => {
    await expect(
      labels.withLabels({ locationDetails: { nativePlace: 'Tirunelveli' } }),
    ).resolves.toEqual({
      ok: true,
      profile: { locationDetails: { nativePlace: 'Tirunelveli' } },
    });
  });

  it('refuses an unknown code, a child outside its parent and a child without its parent, naming the section only', async () => {
    for (const [profile, field] of [
      [
        { religionDetails: { religionCode: 'ZORO' } },
        'details.religionDetails',
      ],
      [
        {
          religionDetails: {
            religionCode: 'CHRISTIAN',
            communityCode: 'HINDU-VELLALAR',
          },
        },
        'details.religionDetails',
      ],
      [
        { religionDetails: { communityCode: 'HINDU-VELLALAR' } },
        'details.religionDetails',
      ],
      [
        {
          locationDetails: {
            countryCode: 'IN',
            stateCode: 'IN-KL',
            cityCode: 'IN-TN-MADURAI',
          },
        },
        'details.locationDetails',
      ],
      [{ locationDetails: { stateCode: 'IN-TN' } }, 'details.locationDetails'],
    ] as const) {
      const result = await labels.withLabels(profile);
      expect(result).toEqual({ ok: false, fields: [field] });
      expect(JSON.stringify(result)).not.toMatch(/HINDU|IN-/);
    }
  });

  it('reports both sections when both are wrong', async () => {
    await expect(
      labels.withLabels({
        religionDetails: { religionCode: 'ZORO' },
        locationDetails: { countryCode: 'XX' },
      }),
    ).resolves.toEqual({
      ok: false,
      fields: ['details.religionDetails', 'details.locationDetails'],
    });
  });

  it('any other failure (the database is down) passes through', async () => {
    const boom = new Error('connection refused');
    const broken = new ReferenceDataClientLabels(
      { resolve: () => Promise.reject(boom) },
      fakeReligions,
    );
    await expect(
      broken.withLabels({ locationDetails: { countryCode: 'IN' } }),
    ).rejects.toBe(boom);
  });

  it('the real services refuse with NotFoundException, as the fakes do', () => {
    const dir = join(__dirname, '../../../reference-data/services');
    for (const file of ['location.service.ts', 'religion.service.ts']) {
      expect(readFileSync(join(dir, file), 'utf8')).toContain(
        'throw new NotFoundException(',
      );
    }
  });
});
