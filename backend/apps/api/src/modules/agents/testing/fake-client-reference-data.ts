/**
 * In-memory stand-ins for the two master-data `resolve` methods the client
 * profile uses, with the same refusals (NotFoundException) for an unknown
 * code, a child outside its parent and a child without its parent. A small
 * table of real codes (seed-data). Tests only.
 */
import { NotFoundException } from '@nestjs/common';
import type { LocationService } from '../../reference-data/services/location.service';
import type { ReligionService } from '../../reference-data/services/religion.service';

const COUNTRIES: Record<string, string> = { IN: 'India', SG: 'Singapore' };
const STATES: Record<string, { country: string; label: string }> = {
  'IN-TN': { country: 'IN', label: 'Tamil Nadu' },
  'IN-KL': { country: 'IN', label: 'Kerala' },
};
const CITIES: Record<string, { state: string; label: string }> = {
  'IN-TN-MADURAI': { state: 'IN-TN', label: 'Madurai' },
  'IN-TN-CHENNAI': { state: 'IN-TN', label: 'Chennai' },
  'IN-KL-KOCHI': { state: 'IN-KL', label: 'Kochi' },
};
const RELIGIONS: Record<string, string> = {
  HINDU: 'Hindu',
  CHRISTIAN: 'Christian',
};
const COMMUNITIES: Record<string, { religion: string; label: string }> = {
  'HINDU-VELLALAR': { religion: 'HINDU', label: 'Vellalar' },
  'CHRISTIAN-NADAR': { religion: 'CHRISTIAN', label: 'Nadar' },
};

const up = (v?: string | null) => v?.trim().toUpperCase() || null;

export const fakeLocations: Pick<LocationService, 'resolve'> = {
  resolve(input) {
    const countryCode = up(input.countryCode);
    const stateCode = up(input.stateCode);
    const cityCode = up(input.cityCode);
    if (!countryCode && !stateCode && !cityCode) return Promise.resolve(null);
    const fail = (m: string) => Promise.reject(new NotFoundException(m));
    if (countryCode && !COUNTRIES[countryCode]) return fail('Unknown country.');
    if (stateCode && !STATES[stateCode]) return fail('Unknown state.');
    if (stateCode && countryCode && STATES[stateCode].country !== countryCode) {
      return fail('State not in country.');
    }
    if (cityCode && !CITIES[cityCode]) return fail('Unknown city.');
    if (cityCode && stateCode && CITIES[cityCode].state !== stateCode) {
      return fail('City not in state.');
    }
    if (cityCode && !stateCode) return fail('City needs its state.');
    if (stateCode && !countryCode) return fail('State needs its country.');
    return Promise.resolve({
      countryCode,
      stateCode,
      cityCode,
      countryLabel: countryCode ? COUNTRIES[countryCode] : null,
      stateLabel: stateCode ? STATES[stateCode].label : null,
      cityLabel: cityCode ? CITIES[cityCode].label : null,
    });
  },
};

export const fakeReligions: Pick<ReligionService, 'resolve'> = {
  resolve(input) {
    const religionCode = up(input.religionCode);
    const communityCode = up(input.communityCode);
    if (!religionCode && !communityCode) return Promise.resolve(null);
    const fail = (m: string) => Promise.reject(new NotFoundException(m));
    if (religionCode && !RELIGIONS[religionCode])
      return fail('Unknown religion.');
    if (communityCode && !COMMUNITIES[communityCode]) {
      return fail('Unknown community.');
    }
    if (
      communityCode &&
      religionCode &&
      COMMUNITIES[communityCode].religion !== religionCode
    ) {
      return fail('Community not in religion.');
    }
    if (communityCode && !religionCode)
      return fail('Community needs religion.');
    return Promise.resolve({
      religionCode,
      communityCode,
      religionLabel: religionCode ? RELIGIONS[religionCode] : null,
      communityLabel: communityCode ? COMMUNITIES[communityCode].label : null,
    });
  },
};
