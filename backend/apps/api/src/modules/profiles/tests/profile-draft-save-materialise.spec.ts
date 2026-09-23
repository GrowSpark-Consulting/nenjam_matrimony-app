import { NotFoundException } from '@nestjs/common';
import { ProfileDraftController } from '../controllers/profile-draft.controller';
import type { ProfileDraftService } from '../services/profile-draft.service';
import type { ProfileService } from '../services/profile.service';
import { LocationDetailsDto } from '../dto/location-details.dto';

/**
 * A section save is only reported as successful when the profile other
 * members see was actually updated.
 *
 * `PATCH /profiles/draft/<section>` stores the section in the draft and then
 * copies the draft into `user_profiles` (ProfileService.syncMatchableFromDraft).
 * That copy used to swallow its own failures, so the PATCH answered 200 —
 * and Edit Profile said "Profile updated" — while `user_profiles` still held
 * the old values. These pin that a failed copy fails the request, with its
 * own status when it has one.
 */
describe('ProfileDraftController — a failed profile copy fails the save', () => {
  const draft = { data: { locationDetails: { city: 'Ahmedabad' } } };

  function build(sync: jest.Mock) {
    const draftService = {
      updateSection: jest.fn().mockResolvedValue(draft),
    } as unknown as ProfileDraftService;
    const profileService = {
      syncMatchableFromDraft: sync,
    } as unknown as ProfileService;
    return {
      controller: new ProfileDraftController(draftService, profileService),
      draftService,
    };
  }

  const dto = Object.assign(new LocationDetailsDto(), { city: 'Ahmedabad' });

  it('answers with the draft when the copy succeeds', async () => {
    const sync = jest.fn().mockResolvedValue(undefined);
    const { controller } = build(sync);

    await expect(controller.updateLocationDetails('user-1', dto)).resolves.toBe(
      draft,
    );
    expect(sync).toHaveBeenCalledWith('user-1', draft.data);
  });

  it("rejects with the copy's own HTTP error (e.g. a bad location code)", async () => {
    const rejection = new NotFoundException('Unknown city code "XX".');
    const { controller } = build(jest.fn().mockRejectedValue(rejection));

    await expect(controller.updateLocationDetails('user-1', dto)).rejects.toBe(
      rejection,
    );
  });

  it('rejects on an unexpected failure rather than reporting success', async () => {
    const { controller } = build(
      jest.fn().mockRejectedValue(new Error('connection reset')),
    );

    await expect(
      controller.updateLocationDetails('user-1', dto),
    ).rejects.toThrow('connection reset');
  });

  it('a retry of the same save completes once the copy succeeds', async () => {
    const sync = jest
      .fn()
      .mockRejectedValueOnce(new Error('connection reset'))
      .mockResolvedValueOnce(undefined);
    const { controller } = build(sync);

    await expect(
      controller.updateLocationDetails('user-1', dto),
    ).rejects.toThrow('connection reset');
    await expect(controller.updateLocationDetails('user-1', dto)).resolves.toBe(
      draft,
    );
    expect(sync).toHaveBeenCalledTimes(2);
  });

  it('does not attempt the copy when the client asked to skip it', async () => {
    const sync = jest.fn();
    const { controller } = build(sync);

    await controller.updateLocationDetails('user-1', dto, 'true');
    expect(sync).not.toHaveBeenCalled();
  });
});
