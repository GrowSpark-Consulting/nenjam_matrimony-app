import { NotFoundException } from '@nestjs/common';
import { SettingsService } from '../services/settings.service';
import { PrivacySettings } from '../repositories/settings.repository';

function build({ premium = true }: { premium?: boolean } = {}) {
  const settingsRepository = {
    findPrivacyByUserId: jest.fn(),
    updatePrivacyByUserId: jest.fn(),
  };
  const entitlementService = {
    hasActivePremiumSubscription: jest.fn().mockResolvedValue(premium),
  };
  const service = new SettingsService(
    settingsRepository as never,
    entitlementService as never,
  );
  return { service, settingsRepository, entitlementService };
}

const DEFAULTS: PrivacySettings = {
  profileVisibleToPremiumOnly: false,
  hidePhotosFromNonConnections: false,
};

const BOTH_ON: PrivacySettings = {
  profileVisibleToPremiumOnly: true,
  hidePhotosFromNonConnections: true,
};

describe('SettingsService.getPrivacySettings', () => {
  it('returns the stored settings (DB-backed defaults)', async () => {
    const { service, settingsRepository } = build();
    settingsRepository.findPrivacyByUserId.mockResolvedValue(DEFAULTS);
    await expect(service.getPrivacySettings('u1')).resolves.toEqual({
      isPremium: true,
      hideMyProfile: false,
      hidePhotosFromNonConnections: false,
      profileVisibleToPremiumOnly: false,
    });
    expect(settingsRepository.findPrivacyByUserId).toHaveBeenCalledWith('u1');
  });

  it('404s when the user does not exist', async () => {
    const { service, settingsRepository } = build();
    settingsRepository.findPrivacyByUserId.mockResolvedValue(null);
    await expect(service.getPrivacySettings('u1')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('premium: reports the stored flags as enforced', async () => {
    const { service, settingsRepository } = build({ premium: true });
    settingsRepository.findPrivacyByUserId.mockResolvedValue(BOTH_ON);
    await expect(service.getPrivacySettings('u1')).resolves.toEqual({
      isPremium: true,
      hideMyProfile: true,
      hidePhotosFromNonConnections: true,
      profileVisibleToPremiumOnly: true,
    });
  });

  it('non-premium: reports both privacy flags as stored (free privacy), isPremium stays false', async () => {
    const { service, settingsRepository } = build({ premium: false });
    settingsRepository.findPrivacyByUserId.mockResolvedValue(BOTH_ON);
    await expect(service.getPrivacySettings('u1')).resolves.toEqual({
      isPremium: false,
      hideMyProfile: true,
      hidePhotosFromNonConnections: true,
      profileVisibleToPremiumOnly: true,
    });
  });

  it("derives premium from the caller's own id, server-side", async () => {
    const { service, settingsRepository, entitlementService } = build();
    settingsRepository.findPrivacyByUserId.mockResolvedValue(DEFAULTS);
    await service.getPrivacySettings('u1');
    expect(
      entitlementService.hasActivePremiumSubscription,
    ).toHaveBeenCalledWith('u1');
  });
});

describe('SettingsService.updatePrivacySettings', () => {
  it('updates a single supplied field, passing only that field to the repo', async () => {
    const { service, settingsRepository } = build();
    settingsRepository.updatePrivacyByUserId.mockResolvedValue({
      profileVisibleToPremiumOnly: true,
      hidePhotosFromNonConnections: false,
    });

    const result = await service.updatePrivacySettings('u1', {
      hideMyProfile: true,
    });

    expect(settingsRepository.updatePrivacyByUserId).toHaveBeenCalledWith(
      'u1',
      {
        profileVisibleToPremiumOnly: true,
      },
    );
    expect(result.hideMyProfile).toBe(true);
  });

  it('still accepts the legacy profileVisibleToPremiumOnly key as hideMyProfile', async () => {
    const { service, settingsRepository } = build();
    settingsRepository.updatePrivacyByUserId.mockResolvedValue({
      profileVisibleToPremiumOnly: true,
      hidePhotosFromNonConnections: false,
    });

    const result = await service.updatePrivacySettings('u1', {
      profileVisibleToPremiumOnly: true,
    });

    expect(settingsRepository.updatePrivacyByUserId).toHaveBeenCalledWith(
      'u1',
      { profileVisibleToPremiumOnly: true },
    );
    expect(result.profileVisibleToPremiumOnly).toBe(true);
  });

  it('prefers hideMyProfile over the legacy key when both are sent', async () => {
    const { service, settingsRepository } = build();
    settingsRepository.updatePrivacyByUserId.mockResolvedValue(DEFAULTS);

    await service.updatePrivacySettings('u1', {
      hideMyProfile: false,
      profileVisibleToPremiumOnly: true,
    });

    expect(settingsRepository.updatePrivacyByUserId).toHaveBeenCalledWith(
      'u1',
      { profileVisibleToPremiumOnly: false },
    );
  });

  it('updates both fields when both are supplied', async () => {
    const { service, settingsRepository } = build();
    settingsRepository.updatePrivacyByUserId.mockResolvedValue(BOTH_ON);

    await service.updatePrivacySettings('u1', {
      hideMyProfile: true,
      hidePhotosFromNonConnections: true,
    });

    expect(settingsRepository.updatePrivacyByUserId).toHaveBeenCalledWith(
      'u1',
      BOTH_ON,
    );
  });

  it('preserves omitted fields — an empty patch does not write and returns current settings', async () => {
    const { service, settingsRepository } = build();
    const current: PrivacySettings = {
      profileVisibleToPremiumOnly: true,
      hidePhotosFromNonConnections: false,
    };
    settingsRepository.findPrivacyByUserId.mockResolvedValue(current);

    const result = await service.updatePrivacySettings('u1', {});

    expect(settingsRepository.updatePrivacyByUserId).not.toHaveBeenCalled();
    expect(settingsRepository.findPrivacyByUserId).toHaveBeenCalledWith('u1');
    expect(result).toEqual({
      isPremium: true,
      hideMyProfile: true,
      hidePhotosFromNonConnections: false,
      profileVisibleToPremiumOnly: true,
    });
  });

  it('never writes a field the caller omitted, even when the other is set', async () => {
    const { service, settingsRepository } = build();
    settingsRepository.updatePrivacyByUserId.mockResolvedValue({
      profileVisibleToPremiumOnly: false,
      hidePhotosFromNonConnections: true,
    });

    await service.updatePrivacySettings('u1', {
      hidePhotosFromNonConnections: true,
    });

    const calls = settingsRepository.updatePrivacyByUserId.mock
      .calls as unknown[][];
    expect(calls[0][1]).toEqual({ hidePhotosFromNonConnections: true });
    expect(calls[0][1]).not.toHaveProperty('profileVisibleToPremiumOnly');
  });

  it('translates a deleted user (Prisma P2025) into a 404', async () => {
    const { service, settingsRepository } = build();
    settingsRepository.updatePrivacyByUserId.mockRejectedValue({
      code: 'P2025',
    });
    await expect(
      service.updatePrivacySettings('u1', {
        hideMyProfile: true,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  describe('premium gating', () => {
    it.each([
      [{ hideMyProfile: true }, { profileVisibleToPremiumOnly: true }],
      [
        { profileVisibleToPremiumOnly: true },
        { profileVisibleToPremiumOnly: true },
      ],
      [
        { hidePhotosFromNonConnections: true },
        { hidePhotosFromNonConnections: true },
      ],
      [
        { hideMyProfile: true, hidePhotosFromNonConnections: true },
        {
          profileVisibleToPremiumOnly: true,
          hidePhotosFromNonConnections: true,
        },
      ],
    ])(
      'non-premium: may switch privacy on (%j) — temporarily free',
      async (dto, written) => {
        const { service, settingsRepository } = build({ premium: false });
        const stored = { ...DEFAULTS, ...written };
        settingsRepository.updatePrivacyByUserId.mockResolvedValue(stored);

        const result = await service.updatePrivacySettings('u1', dto);

        expect(settingsRepository.updatePrivacyByUserId).toHaveBeenCalledWith(
          'u1',
          written,
        );
        expect(result).toEqual({
          isPremium: false,
          hideMyProfile: stored.profileVisibleToPremiumOnly,
          hidePhotosFromNonConnections: stored.hidePhotosFromNonConnections,
          profileVisibleToPremiumOnly: stored.profileVisibleToPremiumOnly,
        });
      },
    );

    it('non-premium: may still switch features off, and sees them reported off', async () => {
      const { service, settingsRepository } = build({ premium: false });
      settingsRepository.updatePrivacyByUserId.mockResolvedValue(DEFAULTS);

      const result = await service.updatePrivacySettings('u1', {
        hideMyProfile: false,
        hidePhotosFromNonConnections: false,
      });

      expect(settingsRepository.updatePrivacyByUserId).toHaveBeenCalledWith(
        'u1',
        DEFAULTS,
      );
      expect(result).toEqual({
        isPremium: false,
        hideMyProfile: false,
        hidePhotosFromNonConnections: false,
        profileVisibleToPremiumOnly: false,
      });
    });

    it('premium: may switch features on', async () => {
      const { service, settingsRepository } = build({ premium: true });
      settingsRepository.updatePrivacyByUserId.mockResolvedValue(BOTH_ON);

      const result = await service.updatePrivacySettings('u1', {
        hideMyProfile: true,
        hidePhotosFromNonConnections: true,
      });

      expect(result).toEqual({
        isPremium: true,
        hideMyProfile: true,
        hidePhotosFromNonConnections: true,
        profileVisibleToPremiumOnly: true,
      });
    });

    it('checks premium only after narrowing the patch — an empty patch never asks', async () => {
      const { service, settingsRepository, entitlementService } = build({
        premium: false,
      });
      settingsRepository.findPrivacyByUserId.mockResolvedValue(DEFAULTS);

      await service.updatePrivacySettings('u1', {});

      // Only the read path's single lookup.
      expect(
        entitlementService.hasActivePremiumSubscription,
      ).toHaveBeenCalledTimes(1);
      expect(settingsRepository.updatePrivacyByUserId).not.toHaveBeenCalled();
    });
  });
});
