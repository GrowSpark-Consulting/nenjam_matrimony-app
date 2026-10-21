import { BadRequestException } from '@nestjs/common';
import { PhotoFilePipe, type UploadedImageFile } from './photo-file.pipe';

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0]);

const file = (over: Partial<UploadedImageFile>): UploadedImageFile => ({
  originalname: 'p.jpg',
  mimetype: 'image/jpeg',
  size: JPEG.length,
  buffer: JPEG,
  ...over,
});

describe('PhotoFilePipe', () => {
  const pipe = new PhotoFilePipe();

  it('accepts a real JPEG declared as JPEG', () => {
    const f = file({});
    expect(pipe.transform(f)).toBe(f);
  });

  it('refuses a non-image sent under an image content type', () => {
    const html = Buffer.from('<html><script>alert(1)</script></html>');
    expect(() =>
      pipe.transform(file({ buffer: html, size: html.length })),
    ).toThrow(BadRequestException);
  });

  it('stores a mislabelled but genuine image under its real type', () => {
    const out = pipe.transform(
      file({ mimetype: 'image/jpeg', buffer: PNG, size: PNG.length }),
    );
    expect(out.mimetype).toBe('image/png');
  });

  it('refuses disallowed declared types, empty files and missing files', () => {
    expect(() => pipe.transform(file({ mimetype: 'image/gif' }))).toThrow(
      BadRequestException,
    );
    expect(() =>
      pipe.transform(file({ buffer: Buffer.alloc(0), size: 0 })),
    ).toThrow(BadRequestException);
    expect(() => pipe.transform(undefined)).toThrow(BadRequestException);
  });
});
