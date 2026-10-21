import { BadRequestException } from '@nestjs/common';
import { AttachmentsService } from '../services/attachments.service';

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46]);
const M4A = Buffer.concat([
  Buffer.from([0, 0, 0, 0x18]),
  Buffer.from('ftypM4A '),
]);
const WEBM = Buffer.from([0x1a, 0x45, 0xdf, 0xa3, 1, 0, 0, 0]);

describe('AttachmentsService content checks', () => {
  const uploaded: { key: string; contentType: string }[] = [];
  const s3 = {
    isConfigured: () => true,
    uploadObject: jest.fn((o: { key: string; contentType: string }) => {
      uploaded.push(o);
      return Promise.resolve();
    }),
  };
  const scanner = { assertClean: jest.fn().mockResolvedValue(undefined) };
  const audit = { record: jest.fn().mockResolvedValue(undefined) };
  const service = new AttachmentsService(
    s3 as never,
    scanner as never,
    audit as never,
  );

  beforeEach(() => {
    uploaded.length = 0;
    jest.clearAllMocks();
  });

  const f = (buffer: Buffer, mimetype: string) => ({
    originalname: 'x',
    mimetype,
    size: buffer.length,
    buffer,
  });

  it('stores a genuine image and a genuine m4a voice note', async () => {
    await service.upload('u1', f(JPEG, 'image/jpeg'), 'IMAGE');
    await service.upload('u1', f(M4A, 'audio/mp4'), 'AUDIO');
    expect(uploaded.map((u) => u.contentType)).toEqual([
      'image/jpeg',
      'audio/mp4',
    ]);
    expect(uploaded[0].key).toMatch(/^chat-media\/u1\/[0-9a-f-]+\.jpg$/);
  });

  it('refuses content that is not what it claims, before storing anything', async () => {
    const html = Buffer.from('<script>alert(1)</script>');
    await expect(
      service.upload('u1', f(html, 'image/png'), 'IMAGE'),
    ).rejects.toBeInstanceOf(BadRequestException);
    // WebM bytes relabelled as m4a are not audio this API can serve.
    await expect(
      service.upload('u1', f(WEBM, 'audio/mp4'), 'AUDIO'),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(s3.uploadObject).not.toHaveBeenCalled();
  });

  it('files a mislabelled genuine image under its real type', async () => {
    await service.upload('u1', f(JPEG, 'image/png'), 'IMAGE');
    expect(uploaded[0].contentType).toBe('image/jpeg');
    expect(uploaded[0].key.endsWith('.jpg')).toBe(true);
  });

  it('still rejects a disallowed declared type', async () => {
    await expect(
      service.upload('u1', f(JPEG, 'image/gif'), 'IMAGE'),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
