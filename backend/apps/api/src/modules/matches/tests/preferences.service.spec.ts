import { PreferencesService } from '../services/preferences.service';
import type { PreferenceRepository } from '../repositories/preference.repository';
import type { FeedInvalidationService } from '../cache/feed-invalidation.service';

/**
 * "Any" must be able to CLEAR a saved age / height / income limit, and an
 * unset limit must read back as "no limit".
 *
 * Neither was possible. The app sent nothing for "Any", and an omitted field
 * is (correctly) left alone — so the old restriction stayed. And GET filled
 * every unset bound with 18-45 / 140-210, which the app then showed as a real
 * range and wrote back on the next Save.
 */
function build(row: Record<string, unknown> | null = null) {
  const upsert = jest.fn((_userId: string, data: Record<string, unknown>) =>
    Promise.resolve({ ...(row ?? {}), ...data }),
  );
  const repository = {
    findByUserId: jest.fn().mockResolvedValue(row),
    upsert,
  } as unknown as PreferenceRepository;
  const invalidation = {
    invalidate: jest.fn().mockResolvedValue(undefined),
  } as unknown as FeedInvalidationService;
  return { service: new PreferencesService(repository, invalidation), upsert };
}

describe('PreferencesService', () => {
  describe('GET', () => {
    it('reports no limit, not 18-45 / 140-210, for a member who never set one', async () => {
      const { service } = build(null);
      await expect(service.get('me')).resolves.toMatchObject({
        minAge: null,
        maxAge: null,
        minHeightCm: null,
        maxHeightCm: null,
        minIncomeLakhs: null,
      });
    });

    it('reports a cleared bound as null', async () => {
      const { service } = build({
        minAge: 26,
        maxAge: null,
        minHeightCm: null,
        maxHeightCm: 180,
      });
      await expect(service.get('me')).resolves.toMatchObject({
        minAge: 26,
        maxAge: null,
        minHeightCm: null,
        maxHeightCm: 180,
      });
    });
  });

  describe('PUT', () => {
    it('clears a range when the app sends null ("Any")', async () => {
      const { service, upsert } = build({ minAge: 26, maxAge: 30 });

      const saved = await service.update('me', { minAge: null, maxAge: null });

      expect(upsert).toHaveBeenCalledWith('me', { minAge: null, maxAge: null });
      expect(saved).toMatchObject({ minAge: null, maxAge: null });
    });

    it('clears height and minimum income the same way', async () => {
      const { service, upsert } = build({
        minHeightCm: 160,
        maxHeightCm: 180,
        minIncomeLakhs: 10,
      });

      await service.update('me', {
        minHeightCm: null,
        maxHeightCm: null,
        minIncomeLakhs: null,
      });

      expect(upsert).toHaveBeenCalledWith('me', {
        minHeightCm: null,
        maxHeightCm: null,
        minIncomeLakhs: null,
      });
    });

    it('leaves an OMITTED field alone — only an explicit null clears', async () => {
      const { service, upsert } = build({ minAge: 26, maxAge: 30 });

      await service.update('me', { preferredReligions: ['Hindu'] });

      const data = upsert.mock.calls[0][1];
      expect(data).toEqual({ preferredReligions: ['Hindu'] });
      expect('minAge' in data).toBe(false);
    });
  });
});
