import { InternalServerErrorException } from '@nestjs/common';
import { GetObjectCommand, S3Client } from '@aws-sdk/client-s3';
import type { AppConfigService } from '@app/config';
import { S3Service, detectObjectFormat } from './s3.service';

// Covers only the read-only getObjectBytes() added for face verification.
// `send` is replaced before any call, so no request ever leaves the process.
const JPEG = [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10];
const PNG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00];
const PDF = [0x25, 0x50, 0x44, 0x46, 0x2d, 0x31];
const WEBP = [
  0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
];

function makeService(configured = true): S3Service {
  const storage = configured
    ? {
        region: 'ap-south-1',
        accessKeyId: 'AKIAFAKE',
        secretAccessKey: 'fake',
        bucket: 'test-bucket',
      }
    : {};
  return new S3Service({ storage } as unknown as AppConfigService);
}

function body(bytes: number[]) {
  return {
    transformToByteArray: jest.fn(() => Promise.resolve(new Uint8Array(bytes))),
    destroy: jest.fn(),
  };
}

describe('S3Service.getObjectBytes', () => {
  let send: jest.SpyInstance;

  beforeEach(() => {
    send = jest.spyOn(S3Client.prototype, 'send');
  });

  afterEach(() => jest.restoreAllMocks());

  it('throws the standard "not configured" 500 without calling S3', async () => {
    await expect(makeService(false).getObjectBytes('k')).rejects.toBeInstanceOf(
      InternalServerErrorException,
    );
    expect(send).not.toHaveBeenCalled();
  });

  it('reads a JPEG with a single GetObject on the configured bucket', async () => {
    send.mockResolvedValueOnce({
      ContentLength: JPEG.length,
      Body: body(JPEG),
    });

    const result = await makeService().getObjectBytes('profile-photos/u/a.jpg');

    expect(result).toEqual({
      ok: true,
      bytes: new Uint8Array(JPEG),
      format: 'jpeg',
      contentLength: JPEG.length,
    });
    const command = (send.mock.calls as unknown[][])[0][0] as GetObjectCommand;
    expect(command).toBeInstanceOf(GetObjectCommand);
    expect(command.input).toEqual({
      Bucket: 'test-bucket',
      Key: 'profile-photos/u/a.jpg',
    });
  });

  it('rejects an object over the limit from ContentLength, before reading the body', async () => {
    const stream = body(JPEG);
    send.mockResolvedValueOnce({
      ContentLength: 5 * 1024 * 1024 + 1,
      Body: stream,
    });

    await expect(makeService().getObjectBytes('k')).resolves.toEqual({
      ok: false,
      reason: 'TOO_LARGE',
    });
    expect(stream.transformToByteArray).not.toHaveBeenCalled();
    expect(stream.destroy).toHaveBeenCalled();
  });

  it('treats a missing ContentLength as too large rather than reading blind', async () => {
    const stream = body(JPEG);
    send.mockResolvedValueOnce({ Body: stream });
    await expect(makeService().getObjectBytes('k')).resolves.toEqual({
      ok: false,
      reason: 'TOO_LARGE',
    });
    expect(stream.transformToByteArray).not.toHaveBeenCalled();
  });

  it('honours a caller-supplied maxBytes', async () => {
    send.mockResolvedValueOnce({ ContentLength: 10, Body: body(JPEG) });
    await expect(
      makeService().getObjectBytes('k', { maxBytes: 9 }),
    ).resolves.toEqual({
      ok: false,
      reason: 'TOO_LARGE',
    });
  });

  it('rejects an empty object', async () => {
    send.mockResolvedValueOnce({ ContentLength: 0, Body: body([]) });
    await expect(makeService().getObjectBytes('k')).resolves.toEqual({
      ok: false,
      reason: 'EMPTY',
    });
  });

  it('rejects WebP by its bytes even if it was stored as image/jpeg', async () => {
    send.mockResolvedValueOnce({
      ContentLength: WEBP.length,
      ContentType: 'image/jpeg',
      Body: body(WEBP),
    });
    await expect(makeService().getObjectBytes('k')).resolves.toEqual({
      ok: false,
      reason: 'UNSUPPORTED_FORMAT',
    });
  });

  it('accepts PNG and PDF by default, but only what the caller allows', async () => {
    send.mockResolvedValueOnce({ ContentLength: PNG.length, Body: body(PNG) });
    await expect(makeService().getObjectBytes('k')).resolves.toMatchObject({
      ok: true,
      format: 'png',
    });

    send.mockResolvedValueOnce({ ContentLength: PDF.length, Body: body(PDF) });
    await expect(makeService().getObjectBytes('k')).resolves.toMatchObject({
      ok: true,
      format: 'pdf',
    });

    send.mockResolvedValueOnce({ ContentLength: PDF.length, Body: body(PDF) });
    await expect(
      makeService().getObjectBytes('k', { allowedFormats: ['jpeg', 'png'] }),
    ).resolves.toEqual({ ok: false, reason: 'UNSUPPORTED_FORMAT' });
  });

  it('reports a missing object as NOT_FOUND', async () => {
    send.mockRejectedValueOnce(
      Object.assign(new Error('nope'), { name: 'NoSuchKey' }),
    );
    await expect(makeService().getObjectBytes('k')).resolves.toEqual({
      ok: false,
      reason: 'NOT_FOUND',
    });
  });

  it('turns any other storage failure into a 500', async () => {
    send.mockRejectedValueOnce(
      Object.assign(new Error('denied'), { name: 'AccessDenied' }),
    );
    await expect(makeService().getObjectBytes('k')).rejects.toBeInstanceOf(
      InternalServerErrorException,
    );
  });
});

describe('detectObjectFormat', () => {
  it('identifies formats from magic bytes', () => {
    expect(detectObjectFormat(new Uint8Array(JPEG))).toBe('jpeg');
    expect(detectObjectFormat(new Uint8Array(PNG))).toBe('png');
    expect(detectObjectFormat(new Uint8Array(PDF))).toBe('pdf');
    expect(detectObjectFormat(new Uint8Array(WEBP))).toBeNull();
    expect(detectObjectFormat(new Uint8Array([0xff]))).toBeNull();
    expect(detectObjectFormat(new Uint8Array([]))).toBeNull();
  });
});
