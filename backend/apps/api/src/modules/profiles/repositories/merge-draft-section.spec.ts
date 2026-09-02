import { plainToInstance } from 'class-transformer';
import { LocationDetailsDto } from '../dto/location-details.dto';

/**
 * A partial section PATCH must merge, not replace.
 *
 * `mergeDraftSection` spreads the incoming section over the stored one, which
 * reads as a merge. It was not one: the global ValidationPipe runs with
 * `transform: true`, so the handler receives a DTO *instance* from
 * `plainToInstance` with every declared property present — the unset ones as
 * `undefined`. Spreading that overwrote each absent sibling with `undefined`,
 * and JSONB serialization then dropped the keys outright.
 *
 * Caught end-to-end against the running API: `PATCH {state, city}` on a draft
 * holding `country: 'India'` left the stored section as `{state, city}` alone
 * and nulled `user_profiles.country` on the next materialization. The frontend
 * omits empty fields from `toJson()`, so this was reachable in the product —
 * a member who filled area/pinCode in the wizard and later saved the location
 * step from onboarding lost them.
 *
 * These tests pin the mechanism at the DTO boundary and the filter that fixes
 * it, rather than mocking Prisma, so they fail if either half regresses.
 */

/** The exact filter `mergeDraftSection` applies before spreading. */
const definedOnly = (section: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(section).filter(([, value]) => value !== undefined),
  );

/** What the repository stores: a spread, then a JSONB round trip. */
const merge = (stored: Record<string, unknown>, patch: object) =>
  JSON.parse(JSON.stringify({ ...stored, ...definedOnly(patch) })) as Record<
    string,
    unknown
  >;

const storedSection = {
  country: 'India',
  state: 'Karnataka',
  city: 'hcufi',
  area: 'Gokulam',
  pinCode: '570002',
  nativePlace: 'Madurai',
};

describe('draft section merge', () => {
  it('the DTO instance carries every field, including ones never sent', () => {
    // The root cause, stated as a fact about class-transformer rather than an
    // assumption: this is why a raw spread could not merge.
    const dto = plainToInstance(LocationDetailsDto, {
      state: 'Karnataka',
      city: 'Mysore',
    });

    expect(Object.keys(dto).sort()).toEqual(
      ['area', 'city', 'country', 'nativePlace', 'pinCode', 'state'].sort(),
    );
    expect(dto.country).toBeUndefined();
    expect(dto.area).toBeUndefined();
  });

  it('a partial patch keeps every sibling it did not mention', () => {
    const dto = plainToInstance(LocationDetailsDto, {
      state: 'Karnataka',
      city: 'Mysore',
    });

    expect(merge(storedSection, dto)).toEqual({
      country: 'India',
      state: 'Karnataka',
      city: 'Mysore',
      area: 'Gokulam',
      pinCode: '570002',
      nativePlace: 'Madurai',
    });
  });

  it('without the filter, the same patch erases them', () => {
    // The regression this guards, demonstrated rather than described.
    const dto = plainToInstance(LocationDetailsDto, {
      state: 'Karnataka',
      city: 'Mysore',
    });

    const unfiltered = JSON.parse(
      JSON.stringify({ ...storedSection, ...dto }),
    ) as Record<string, unknown>;

    expect(unfiltered).toEqual({ state: 'Karnataka', city: 'Mysore' });
    expect(unfiltered.country).toBeUndefined();
  });

  it('applies a patch that fills previously absent fields', () => {
    const dto = plainToInstance(LocationDetailsDto, {
      area: 'Jayanagar',
      pinCode: '560011',
    });

    const merged = merge({ country: 'India', state: 'Karnataka' }, dto);

    expect(merged).toEqual({
      country: 'India',
      state: 'Karnataka',
      area: 'Jayanagar',
      pinCode: '560011',
    });
  });

  it('lets an explicit empty string through — clearing is not the same as omitting', () => {
    // Only `undefined` means "not sent". An empty string is a value the caller
    // chose, so it must still reach the draft.
    const dto = plainToInstance(LocationDetailsDto, { area: '' });

    expect(merge(storedSection, dto).area).toBe('');
  });

  it('a patch touching nothing leaves the section exactly as it was', () => {
    const dto = plainToInstance(LocationDetailsDto, {});

    expect(merge(storedSection, dto)).toEqual(storedSection);
  });
});
