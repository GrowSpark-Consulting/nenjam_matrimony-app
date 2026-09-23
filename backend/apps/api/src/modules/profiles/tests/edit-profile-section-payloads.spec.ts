import { readFileSync } from 'fs';
import { join } from 'path';
import { RequestMethod, ValidationPipe } from '@nestjs/common';
import { METHOD_METADATA, PATH_METADATA } from '@nestjs/common/constants';
import { ProfileDraftController } from '../controllers/profile-draft.controller';
import { BasicDetailsDto } from '../dto/basic-details.dto';
import { ReligionDetailsDto } from '../dto/religion-details.dto';
import { LocationDetailsDto } from '../dto/location-details.dto';
import { EducationDetailsDto } from '../dto/education-details.dto';
import { PhysicalDetailsDto } from '../dto/physical-details.dto';
import { LifestyleDetailsDto } from '../dto/lifestyle-details.dto';
import { FamilyDetailsDto } from '../dto/family-details.dto';
import { HoroscopeDetailsDto } from '../dto/horoscope-details.dto';

/**
 * Edit Profile's section saves, as the Flutter client actually sends them.
 *
 * `fixtures/edit-profile-section-payloads.json` is RECORDED from the real
 * Flutter `RegistrationRepository` (see the client's
 * `edit_profile_wire_contract_test.dart`, which fails if the client ever
 * sends anything else). This spec proves the server side of that contract:
 *
 *  - each recorded path + method is a real route on ProfileDraftController —
 *    read from Nest's own routing metadata, so no `/v1`, no typo, no verb
 *    mismatch can hide;
 *  - each recorded body passes the exact global ValidationPipe `main.ts`
 *    installs (`whitelist`, `transform`, `forbidNonWhitelisted`) against the
 *    real DTO — so the edit is accepted, not 400ed — and comes out the other
 *    side with every field intact (nothing the member already had is stripped
 *    before it reaches the merge).
 *
 * The merge into Postgres and the read-back are covered by
 * `edit-profile-sections.integration.spec.ts`.
 */

type RecordedRequest = {
  method: string;
  path: string;
  query: Record<string, string> | null;
  body: Record<string, unknown>;
};

const fixture = JSON.parse(
  readFileSync(
    join(__dirname, 'fixtures', 'edit-profile-section-payloads.json'),
    'utf8',
  ),
) as Record<string, RecordedRequest>;

const dtoFor: Record<string, new () => object> = {
  basicDetails: BasicDetailsDto,
  religionDetails: ReligionDetailsDto,
  locationDetails: LocationDetailsDto,
  educationDetails: EducationDetailsDto,
  physicalDetails: PhysicalDetailsDto,
  lifestyleDetails: LifestyleDetailsDto,
  familyDetails: FamilyDetailsDto,
  horoscopeDetails: HoroscopeDetailsDto,
};

/** Exactly the pipe `main.ts` installs globally. */
const pipe = new ValidationPipe({
  whitelist: true,
  transform: true,
  forbidNonWhitelisted: true,
});

/** Every PATCH route ProfileDraftController serves, as full paths. */
function draftPatchRoutes(): Set<string> {
  const base = Reflect.getMetadata(
    PATH_METADATA,
    ProfileDraftController,
  ) as string;
  const proto = ProfileDraftController.prototype as unknown as Record<
    string,
    unknown
  >;
  const routes = new Set<string>();
  for (const name of Object.getOwnPropertyNames(proto)) {
    const handler = proto[name];
    if (typeof handler !== 'function') continue;
    const path = Reflect.getMetadata(PATH_METADATA, handler) as
      string | undefined;
    const method = Reflect.getMetadata(METHOD_METADATA, handler) as
      RequestMethod | undefined;
    if (path === undefined || method !== RequestMethod.PATCH) continue;
    routes.add(`/${base}/${path}`);
  }
  return routes;
}

describe('Edit Profile section saves — the recorded client requests', () => {
  it('covers every section the client edits', () => {
    expect(Object.keys(fixture).sort()).toEqual(Object.keys(dtoFor).sort());
  });

  describe.each(Object.entries(fixture))('%s', (section, request) => {
    it('is a real PATCH route on ProfileDraftController (no prefix)', () => {
      expect(request.method).toBe('PATCH');
      expect(request.path.startsWith('/v1')).toBe(false);
      expect(draftPatchRoutes()).toContain(request.path);
    });

    it('does not ask the server to skip materialising the profile', () => {
      expect(request.query).toBeNull();
    });

    it('passes the global ValidationPipe with every field intact', async () => {
      const validated = (await pipe.transform(request.body, {
        type: 'body',
        metatype: dtoFor[section],
      })) as Record<string, unknown>;

      // Only what was sent survives into the merge (absent DTO properties are
      // undefined, and mergeDraftSection drops undefined keys) — and all of
      // it does.
      const sent = Object.fromEntries(
        Object.entries(validated).filter(([, v]) => v !== undefined),
      );
      expect(JSON.parse(JSON.stringify(sent))).toEqual(request.body);
    });
  });

  it('rejects a body carrying a field the DTO does not declare', async () => {
    await expect(
      pipe.transform(
        { ...fixture.physicalDetails.body, bodyType: 'Athletic' },
        { type: 'body', metatype: PhysicalDetailsDto },
      ),
    ).rejects.toThrow();
  });
});
