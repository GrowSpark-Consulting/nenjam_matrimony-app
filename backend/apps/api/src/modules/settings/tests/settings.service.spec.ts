import { NotFoundException } from '@nestjs/common';
import { SettingsService } from '../services/settings.service';
import { PrivacySettings } from '../repositories/settings.repository';

function build() {
  const settingsRepository = {
    findPrivacyByUserId: jest.fn(),
    updatePrivacyByUserId: jest.fn(),
  };
  const service = new SettingsService(settingsRepository as never);
  return { service, settingsRepository };
}

const DEFAULTS: PrivacySettings = {
  profileVisibleToPremiumOnly: false,
  hidePhotosFromNonConnections: false,
};

describe('SettingsService.getPrivacySettings', () => {
  it('returns the stored settings (DB-backed defaults)', async () => {
    const { service, settingsRepository } = build();
    settingsRepository.findPrivacyByUserId.mockResolvedValue(DEFAULTS);
    await expect(service.getPrivacySettings('u1')).resolves.toEqual(DEFAULTS);
    expect(settingsRepository.findPrivacyByUserId).toHaveBeenCalledWith('u1');
  });

  it('404s when the user does not exist', async () => {
    const { service, settingsRepository } = build();
    settingsRepository.findPrivacyByUserId.mockResolvedValue(null);
    await expect(service.getPrivacySettings('u1')).rejects.toBeInstanceOf(
      NotFoundException,
    );
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
      profileVisibleToPremiumOnly: true,
    });

    expect(settingsRepository.updatePrivacyByUserId).toHaveBeenCalledWith(
      'u1',
      {
        profileVisibleToPremiumOnly: true,
      },
    );
    expect(result.profileVisibleToPremiumOnly).toBe(true);
  });

  it('updates both fields when both are supplied', async () => {
    const { service, settingsRepository } = build();
    const both: PrivacySettings = {
      profileVisibleToPremiumOnly: true,
      hidePhotosFromNonConnections: true,
    };
    settingsRepository.updatePrivacyByUserId.mockResolvedValue(both);

    await service.updatePrivacySettings('u1', both);

    expect(settingsRepository.updatePrivacyByUserId).toHaveBeenCalledWith(
      'u1',
      both,
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
    expect(result).toEqual(current);
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
        profileVisibleToPremiumOnly: true,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});
