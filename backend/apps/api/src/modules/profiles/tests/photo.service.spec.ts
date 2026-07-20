import { BadRequestException, NotFoundException } from '@nestjs/common';
import { S3Service } from '@app/storage';
import { PhotoService } from '../services/photo.service';
import { PhotoRepository } from '../repositories/photo.repository';
import { PhotoEntity } from '../entities/photo.entity';
import type { UploadedImageFile } from '../pipes/photo-file.pipe';

function buildPhoto(overrides: Partial<PhotoEntity> = {}): PhotoEntity {
  const p = new PhotoEntity();
  Object.assign(
    p,
    {
      id: '11111111-1111-4111-8111-111111111111',
      userId: 'user-1',
      s3Key: 'profile-photos/user-1/abc.jpg',
      cdnUrl: 'https://bucket.s3.ap-south-1.amazonaws.com/profile-photos/user-1/abc.jpg',
      isPrimary: false,
      order: 0,
      isApproved: false,
    },
    overrides,
  );
  return p;
}

function buildFile(overrides: Partial<UploadedImageFile> = {}): UploadedImageFile {
  return {
    originalname: 'x.jpg',
    mimetype: 'image/jpeg',
    size: 1234,
    buffer: Buffer.from('imgdata'),
    ...overrides,
  };
}

interface RepoMock {
  findAllForUser: jest.Mock;
  findByIdForUser: jest.Mock;
  countForUser: jest.Mock;
  create: jest.Mock;
  updateStorage: jest.Mock;
  deleteById: jest.Mock;
  setPrimary: jest.Mock;
  promoteFirstToPrimary: jest.Mock;
  applyOrder: jest.Mock;
  deleteAllForUser: jest.Mock;
}

interface S3Mock {
  uploadObject: jest.Mock;
  deleteObject: jest.Mock;
  deleteObjects: jest.Mock;
  getPresignedGetUrl: jest.Mock;
  getObjectUrl: jest.Mock;
}

function setup(repoOverrides: Partial<RepoMock> = {}) {
  const repo: RepoMock = {
    findAllForUser: jest.fn().mockResolvedValue([]),
    findByIdForUser: jest.fn().mockResolvedValue(null),
    countForUser: jest.fn().mockResolvedValue(0),
    create: jest.fn(),
    updateStorage: jest.fn(),
    deleteById: jest.fn().mockResolvedValue(undefined),
    setPrimary: jest.fn().mockResolvedValue(undefined),
    promoteFirstToPrimary: jest.fn().mockResolvedValue(undefined),
    applyOrder: jest.fn().mockResolvedValue(undefined),
    deleteAllForUser: jest.fn().mockResolvedValue([]),
    ...repoOverrides,
  };
  const s3: S3Mock = {
    uploadObject: jest.fn().mockResolvedValue(undefined),
    deleteObject: jest.fn().mockResolvedValue(undefined),
    deleteObjects: jest.fn().mockResolvedValue(undefined),
    getPresignedGetUrl: jest.fn().mockResolvedValue('https://signed.example/get'),
    getObjectUrl: jest.fn((k: string) => `https://bucket.s3.ap-south-1.amazonaws.com/${k}`),
  };
  const service = new PhotoService(
    repo as unknown as PhotoRepository,
    s3 as unknown as S3Service,
  );
  return { service, repo, s3 };
}

describe('PhotoService', () => {
  describe('list', () => {
    it('returns each photo with a fresh presigned URL in cdnUrl', async () => {
      const { service, s3 } = setup({
        findAllForUser: jest.fn().mockResolvedValue([buildPhoto()]),
      });
      const result = await service.list('user-1');
      expect(result[0].cdnUrl).toBe('https://signed.example/get');
      expect(s3.getPresignedGetUrl).toHaveBeenCalledWith('profile-photos/user-1/abc.jpg');
    });
  });

  describe('upload', () => {
    it('rejects when the user already has the max number of photos', async () => {
      const { service, s3 } = setup({ countForUser: jest.fn().mockResolvedValue(6) });
      await expect(service.upload('user-1', buildFile())).rejects.toBeInstanceOf(
        BadRequestException,
      );
      expect(s3.uploadObject).not.toHaveBeenCalled();
    });

    it('uploads to S3 then records metadata, first photo becomes primary', async () => {
      const { service, repo, s3 } = setup({
        countForUser: jest.fn().mockResolvedValue(0),
        create: jest.fn().mockResolvedValue(buildPhoto({ isPrimary: true })),
      });
      await service.upload('user-1', buildFile());
      expect(s3.uploadObject).toHaveBeenCalledTimes(1);
      const createArg = repo.create.mock.calls[0][1];
      expect(createArg.isPrimary).toBe(true);
      expect(createArg.order).toBe(0);
      expect(createArg.s3Key).toMatch(/^profile-photos\/user-1\/.*\.jpg$/);
    });

    it('rolls back the S3 object if the DB write fails (no orphan)', async () => {
      const { service, s3 } = setup({
        countForUser: jest.fn().mockResolvedValue(0),
        create: jest.fn().mockRejectedValue(new Error('db down')),
      });
      await expect(service.upload('user-1', buildFile())).rejects.toThrow('db down');
      expect(s3.deleteObject).toHaveBeenCalledTimes(1);
    });
  });

  describe('replace', () => {
    it('404s when the photo is not the user\'s', async () => {
      const { service, s3 } = setup({
        findByIdForUser: jest.fn().mockResolvedValue(null),
      });
      await expect(
        service.replace('user-1', '11111111-1111-4111-8111-111111111111', buildFile()),
      ).rejects.toBeInstanceOf(NotFoundException);
      expect(s3.uploadObject).not.toHaveBeenCalled();
    });

    it('uploads new object, repoints row, deletes the old object', async () => {
      const old = buildPhoto({ s3Key: 'profile-photos/user-1/OLD.jpg' });
      const { service, repo, s3 } = setup({
        findByIdForUser: jest.fn().mockResolvedValue(old),
        updateStorage: jest.fn().mockResolvedValue(buildPhoto()),
      });
      await service.replace('user-1', old.id, buildFile());
      expect(s3.uploadObject).toHaveBeenCalledTimes(1);
      expect(repo.updateStorage).toHaveBeenCalledTimes(1);
      expect(s3.deleteObject).toHaveBeenCalledWith('profile-photos/user-1/OLD.jpg');
    });

    it('rolls back the new object if the DB update fails, keeps the old', async () => {
      const old = buildPhoto({ s3Key: 'profile-photos/user-1/OLD.jpg' });
      const { service, s3 } = setup({
        findByIdForUser: jest.fn().mockResolvedValue(old),
        updateStorage: jest.fn().mockRejectedValue(new Error('db down')),
      });
      await expect(
        service.replace('user-1', old.id, buildFile()),
      ).rejects.toThrow('db down');
      // Deleted the NEW key, never the old one.
      expect(s3.deleteObject).toHaveBeenCalledTimes(1);
      expect(s3.deleteObject).not.toHaveBeenCalledWith('profile-photos/user-1/OLD.jpg');
    });
  });

  describe('remove', () => {
    it('404s when the photo is not the user\'s', async () => {
      const { service } = setup({ findByIdForUser: jest.fn().mockResolvedValue(null) });
      await expect(
        service.remove('user-1', '11111111-1111-4111-8111-111111111111'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('deletes row + object and promotes a new primary when the deleted was primary', async () => {
      const primary = buildPhoto({ isPrimary: true });
      const { service, repo, s3 } = setup({
        findByIdForUser: jest.fn().mockResolvedValue(primary),
        findAllForUser: jest.fn().mockResolvedValue([]),
      });
      await service.remove('user-1', primary.id);
      expect(repo.deleteById).toHaveBeenCalledWith(primary.id);
      expect(s3.deleteObject).toHaveBeenCalledWith(primary.s3Key);
      expect(repo.promoteFirstToPrimary).toHaveBeenCalledWith('user-1');
    });

    it('does not promote when the deleted photo was not primary', async () => {
      const nonPrimary = buildPhoto({ isPrimary: false });
      const { service, repo } = setup({
        findByIdForUser: jest.fn().mockResolvedValue(nonPrimary),
      });
      await service.remove('user-1', nonPrimary.id);
      expect(repo.promoteFirstToPrimary).not.toHaveBeenCalled();
    });
  });

  describe('reorder', () => {
    it('rejects when the id set does not match the user\'s photos exactly', async () => {
      const a = buildPhoto({ id: 'aaaaaaaa-1111-4111-8111-111111111111' });
      const b = buildPhoto({ id: 'bbbbbbbb-1111-4111-8111-111111111111' });
      const { service, repo } = setup({
        findAllForUser: jest.fn().mockResolvedValue([a, b]),
      });
      await expect(service.reorder('user-1', [a.id])).rejects.toBeInstanceOf(
        BadRequestException,
      );
      expect(repo.applyOrder).not.toHaveBeenCalled();
    });

    it('applies the new order when the set matches', async () => {
      const a = buildPhoto({ id: 'aaaaaaaa-1111-4111-8111-111111111111' });
      const b = buildPhoto({ id: 'bbbbbbbb-1111-4111-8111-111111111111' });
      const { service, repo } = setup({
        findAllForUser: jest.fn().mockResolvedValue([a, b]),
      });
      await service.reorder('user-1', [b.id, a.id]);
      expect(repo.applyOrder).toHaveBeenCalledWith([b.id, a.id]);
    });
  });

  describe('setPrimary', () => {
    it('404s when the photo is not the user\'s', async () => {
      const { service } = setup({ findByIdForUser: jest.fn().mockResolvedValue(null) });
      await expect(
        service.setPrimary('user-1', '11111111-1111-4111-8111-111111111111'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('sets the primary via the repository', async () => {
      const p = buildPhoto();
      const { service, repo } = setup({
        findByIdForUser: jest.fn().mockResolvedValue(p),
      });
      await service.setPrimary('user-1', p.id);
      expect(repo.setPrimary).toHaveBeenCalledWith('user-1', p.id);
    });
  });

  describe('deleteAllForUser', () => {
    it('removes rows then bulk-deletes their objects', async () => {
      const { service, repo, s3 } = setup({
        deleteAllForUser: jest.fn().mockResolvedValue(['k1', 'k2']),
      });
      await service.deleteAllForUser('user-1');
      expect(repo.deleteAllForUser).toHaveBeenCalledWith('user-1');
      expect(s3.deleteObjects).toHaveBeenCalledWith(['k1', 'k2']);
    });
  });
});
