import {
  BadRequestException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import type { MembershipEnforcementMode } from '@app/config';
import { PhotoService } from '../services/photo.service';
import { PhotoEntity } from '../entities/photo.entity';
import {
  inForce,
  membershipWithPlans,
} from '../../entitlements/tests/catalog-fixtures';

// The photo cap (profile.photos: Free 5 / Gold 15 / Platinum 20) under
// enforce, and the legacy cap of 6 everywhere else.

const FILE = {
  originalname: 'x.jpg',
  mimetype: 'image/jpeg',
  size: 10,
  buffer: Buffer.from('img'),
};

function build(
  mode: MembershipEnforcementMode,
  held: number,
  members = {},
  heldAtInsert = held,
) {
  const photo = Object.assign(new PhotoEntity(), { id: 'p1', s3Key: 'k' });
  const repo = {
    countForUser: jest.fn().mockResolvedValue(held),
    create: jest.fn().mockResolvedValue(photo),
    // Runs the cap check with a tx whose count is what the DB holds at
    // insert time — which a concurrent upload may have changed.
    createWithinCap: jest.fn(
      async (
        _u: string,
        _d: unknown,
        check: (tx: unknown) => Promise<void>,
      ) => {
        await check({
          profilePhoto: { count: jest.fn().mockResolvedValue(heldAtInsert) },
        });
        return photo;
      },
    ),
  };
  const s3 = {
    uploadObject: jest.fn().mockResolvedValue(undefined),
    deleteObject: jest.fn().mockResolvedValue(undefined),
    getObjectUrl: jest.fn(() => 'https://bucket/k'),
    getPresignedGetUrl: jest.fn().mockResolvedValue('https://signed'),
  };
  const service = new PhotoService(
    repo as never,
    s3 as never,
    { recalculateCompletionIfMaterialized: jest.fn() } as never,
    membershipWithPlans(mode, members).service,
  );
  return { service, repo, s3 };
}

describe('PhotoService.upload — membership photo cap', () => {
  it('keeps the legacy cap of 6 when limits are not enforced', async () => {
    const atFive = build('off', 5);
    await atFive.service.upload('u', FILE); // 6th photo: allowed, as today
    const atSix = build('off', 6);
    await expect(atSix.service.upload('u', FILE)).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('refuses a Free member’s 6th photo under enforce, before uploading anything', async () => {
    const { service, s3 } = build('enforce', 5);
    const error = await service.upload('u', FILE).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ForbiddenException);
    expect((error as ForbiddenException).getResponse()).toMatchObject({
      feature: 'profile.photos',
      limit: 5,
      plan: 'FREE',
    });
    expect(s3.uploadObject).not.toHaveBeenCalled();
  });

  it('lets a Platinum member go to 20, past the old cap of 6', async () => {
    const { service, repo } = build('enforce', 19, {
      u: [inForce('PLATINUM')],
    });
    await service.upload('u', FILE);
    expect(repo.createWithinCap).toHaveBeenCalled();
  });

  it('re-checks at insert time and removes the uploaded object when a concurrent upload won', async () => {
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    // Pre-check saw 4 (room for one); by insert time another upload made it 5.
    const { service, s3 } = build('enforce', 4, {}, 5);
    await expect(service.upload('u', FILE)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(s3.uploadObject).toHaveBeenCalledTimes(1);
    expect(s3.deleteObject).toHaveBeenCalledTimes(1);
  });

  it('never removes photos a member already has over their plan’s cap', async () => {
    // Nothing in the photo path deletes on a cap; a Free member holding 6
    // (from before) simply can't add a 7th.
    const { service, s3 } = build('enforce', 6);
    await expect(service.upload('u', FILE)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(s3.deleteObject).not.toHaveBeenCalled();
  });
});
