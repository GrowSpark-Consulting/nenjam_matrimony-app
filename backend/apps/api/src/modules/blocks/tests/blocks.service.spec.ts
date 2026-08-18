import { BadRequestException, NotFoundException } from '@nestjs/common';
import { BlocksService } from '../services/blocks.service';

function blockRow(
  over: Partial<{
    id: string;
    blockerId: string;
    blockedUserId: string;
    createdAt: Date;
  }> = {},
) {
  return {
    id: 'b-1',
    blockerId: 'me',
    blockedUserId: 'target-1',
    createdAt: new Date('2026-07-20T10:15:00.000Z'),
    ...over,
  };
}

function build() {
  const repo = {
    isTargetAvailable: jest.fn().mockResolvedValue(true),
    block: jest.fn().mockResolvedValue({ id: 'b-1' }),
    unblock: jest.fn().mockResolvedValue(undefined),
    listBlocked: jest.fn().mockResolvedValue([[], 0]),
    findFeedProfilesByUserIds: jest.fn().mockResolvedValue([]),
  };
  const profileMapper = { toDtoList: jest.fn().mockResolvedValue([]) };
  // Blocking invalidates BOTH members' feeds; these tests assert the block
  // itself, so the signalling is stubbed and asserted separately.
  const feedInvalidation = {
    invalidate: jest.fn().mockResolvedValue(undefined),
    invalidatePair: jest.fn().mockResolvedValue(undefined),
  };
  const service = new BlocksService(
    feedInvalidation as never,
    repo as never,
    profileMapper as never,
  );
  return { service, repo, profileMapper, feedInvalidation };
}

const PAGE = { skip: 0, take: 20, pageNumber: 1 } as never;

describe('BlocksService.block', () => {
  it('rejects blocking yourself', async () => {
    const { service } = build();
    await expect(service.block('me', 'me')).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('404s when the target is unavailable', async () => {
    const { service, repo } = build();
    repo.isTargetAvailable.mockResolvedValue(false);
    await expect(service.block('me', 'target')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('creates the block row for a valid target', async () => {
    const { service, repo } = build();
    await service.block('me', 'target');
    expect(repo.block).toHaveBeenCalledWith('me', 'target');
  });
});

describe('BlocksService.unblock', () => {
  it('removes the block row', async () => {
    const { service, repo } = build();
    await service.unblock('me', 'target');
    expect(repo.unblock).toHaveBeenCalledWith('me', 'target');
  });

  it('is idempotent — unblocking a member who was never blocked does not throw', async () => {
    // repo.unblock is a Prisma deleteMany under the hood: 0 rows affected is
    // not an error, so the repository mock resolving undefined here is the
    // faithful "already unblocked" case.
    const { service, repo } = build();
    await expect(
      service.unblock('me', 'never-blocked'),
    ).resolves.toBeUndefined();
    expect(repo.unblock).toHaveBeenCalledWith('me', 'never-blocked');
  });

  it('does not validate the target first — unblock must succeed even for a', async () => {
    // now-deleted/never-existed account, since there's nothing harmful about
    // removing a block row that may or may not exist (unlike block(), which
    // must 404 rather than create a dangling reference to a bad target).
    const { service, repo } = build();
    repo.isTargetAvailable.mockResolvedValue(false);
    await expect(service.unblock('me', 'ghost')).resolves.toBeUndefined();
    expect(repo.isTargetAvailable).not.toHaveBeenCalled();
  });
});

describe('BlocksService.listBlocked', () => {
  it('returns an empty page when nothing is blocked', async () => {
    const { service, repo, profileMapper } = build();
    const page = await service.listBlocked('me', PAGE);
    expect(page).toEqual({
      items: [],
      page: 1,
      limit: 20,
      total: 0,
      hasMore: false,
    });
    expect(profileMapper.toDtoList).not.toHaveBeenCalled();
  });

  it('joins each block row to its target profile card and the blocked timestamp', async () => {
    const { service, repo, profileMapper } = build();
    repo.listBlocked.mockResolvedValue([
      [blockRow({ blockedUserId: 'target-1' })],
      1,
    ]);
    profileMapper.toDtoList.mockResolvedValue([
      { id: 'target-1', name: 'Target One' },
    ]);

    const page = await service.listBlocked('me', PAGE);

    expect(repo.findFeedProfilesByUserIds).toHaveBeenCalledWith(['target-1']);
    expect(page.items).toEqual([
      {
        id: 'target-1',
        blockedAt: '2026-07-20T10:15:00.000Z',
        profile: { id: 'target-1', name: 'Target One' },
      },
    ]);
    expect(page).toMatchObject({
      page: 1,
      limit: 20,
      total: 1,
      hasMore: false,
    });
  });

  it('skips a blocked target with no finalized profile', async () => {
    const { service, repo, profileMapper } = build();
    repo.listBlocked.mockResolvedValue([
      [blockRow({ blockedUserId: 'no-profile' })],
      1,
    ]);
    profileMapper.toDtoList.mockResolvedValue([]);

    const page = await service.listBlocked('me', PAGE);
    expect(page.items).toEqual([]);
  });
});
