/**
 * `ClientReferenceDataPort` over the member side's own master-data services
 * (`LocationService.resolve`, `ReligionService.resolve`, reference-data
 * module): the same codes, the same parent checks, the same labels a
 * member's profile gets. Their refusal (a Nest NotFoundException, whose
 * message names the code) becomes a field name only, so nothing the agent
 * typed is echoed back.
 */
import { NotFoundException } from '@nestjs/common';
import type { LocationService } from '../../../reference-data/services/location.service';
import type { ReligionService } from '../../../reference-data/services/religion.service';
import type { ClientProfile } from '../../clients/client-profile';
import type { ClientReferenceDataPort } from '../../ports/agent-client-ports';

const str = (v: unknown): string | undefined =>
  typeof v === 'string' && v !== '' ? v : undefined;

/** Drops the keys whose value is undefined. */
const defined = (o: Record<string, unknown>) =>
  Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined));

export class ReferenceDataClientLabels implements ClientReferenceDataPort {
  constructor(
    private readonly locations: Pick<LocationService, 'resolve'>,
    private readonly religions: Pick<ReligionService, 'resolve'>,
  ) {}

  async withLabels(
    profile: ClientProfile,
  ): Promise<
    { ok: true; profile: ClientProfile } | { ok: false; fields: string[] }
  > {
    const out: ClientProfile = structuredClone(profile);
    const fields: string[] = [];

    const religion = out.religionDetails;
    if (religion) {
      const resolved = await refused(
        () =>
          this.religions.resolve({
            religionCode: str(religion.religionCode),
            communityCode: str(religion.communityCode),
          }),
        'details.religionDetails',
        fields,
      );
      if (resolved !== undefined) {
        out.religionDetails = defined({
          ...religion,
          religion: resolved?.religionLabel ?? undefined,
          community: resolved?.communityLabel ?? undefined,
        });
      }
    }

    const location = out.locationDetails;
    if (location) {
      const resolved = await refused(
        () =>
          this.locations.resolve({
            countryCode: str(location.countryCode),
            stateCode: str(location.stateCode),
            cityCode: str(location.cityCode),
          }),
        'details.locationDetails',
        fields,
      );
      if (resolved !== undefined) {
        out.locationDetails = defined({
          ...location,
          country: resolved?.countryLabel ?? undefined,
          state: resolved?.stateLabel ?? undefined,
          city: resolved?.cityLabel ?? undefined,
        });
      }
    }

    return fields.length > 0
      ? { ok: false, fields }
      : { ok: true, profile: out };
  }
}

/** The result, or undefined after recording `field` when the master data refused it. */
async function refused<T>(
  call: () => Promise<T>,
  field: string,
  fields: string[],
): Promise<T | undefined> {
  try {
    return await call();
  } catch (error) {
    if (error instanceof NotFoundException) {
      fields.push(field);
      return undefined;
    }
    throw error;
  }
}
