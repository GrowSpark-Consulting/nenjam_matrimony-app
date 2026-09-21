import { ProfileRepository } from '../repositories/profile.repository';
import type { PrismaService } from '@app/database';

/**
 * The statement createPartnerPreferenceIfMissing issues. The behaviour it
 * relies on — Postgres skipping a conflicting insert without touching the
 * existing row — is proven against a real database in
 * partner-preference-ownership.integration.spec.ts.
 */
describe('ProfileRepository.createPartnerPreferenceIfMissing', () => {
  function build(count: number) {
    const partnerPreference = {
      createMany: jest.fn().mockResolvedValue({ count }),
      create: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
      upsert: jest.fn(),
    };
    const repository = new ProfileRepository({
      partnerPreference,
    } as unknown as PrismaService);
    return { repository, partnerPreference };
  }

  const DATA = { minAge: 26, maxAge: 30, preferredReligions: ['Hindu'] };

  it('is a single insert that skips an existing row', async () => {
    const { repository, partnerPreference } = build(1);

    await repository.createPartnerPreferenceIfMissing('user-1', DATA);

    expect(partnerPreference.createMany).toHaveBeenCalledTimes(1);
    expect(partnerPreference.createMany).toHaveBeenCalledWith({
      data: [{ ...DATA, userId: 'user-1' }],
      skipDuplicates: true,
    });
  });

  it('never updates, upserts or read-then-creates', async () => {
    const { repository, partnerPreference } = build(0);

    await repository.createPartnerPreferenceIfMissing('user-1', DATA);

    expect(partnerPreference.update).not.toHaveBeenCalled();
    expect(partnerPreference.updateMany).not.toHaveBeenCalled();
    expect(partnerPreference.upsert).not.toHaveBeenCalled();
    expect(partnerPreference.create).not.toHaveBeenCalled();
  });

  it('reports whether it created the row', async () => {
    await expect(
      build(1).repository.createPartnerPreferenceIfMissing('user-1', DATA),
    ).resolves.toBe(true);
    await expect(
      build(0).repository.createPartnerPreferenceIfMissing('user-1', DATA),
    ).resolves.toBe(false);
  });
});
