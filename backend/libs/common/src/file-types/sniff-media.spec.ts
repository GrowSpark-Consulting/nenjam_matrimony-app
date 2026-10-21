import {
  audioMimeMatches,
  sniffAudioKind,
  sniffImageMime,
} from './sniff-media';

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10]);
const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0]);
const webp = Buffer.concat([
  Buffer.from('RIFF'),
  Buffer.from([1, 0, 0, 0]),
  Buffer.from('WEBP'),
]);
const ftyp = (brand: string) =>
  Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftyp' + brand)]);

describe('sniffImageMime', () => {
  it('recognises the accepted formats from their bytes', () => {
    expect(sniffImageMime(jpeg)).toBe('image/jpeg');
    expect(sniffImageMime(png)).toBe('image/png');
    expect(sniffImageMime(webp)).toBe('image/webp');
    expect(sniffImageMime(ftyp('heic'))).toBe('image/heic');
  });

  it('refuses everything else, whatever it claims to be', () => {
    expect(
      sniffImageMime(Buffer.from('<html><script>alert(1)</script>')),
    ).toBeNull();
    expect(sniffImageMime(Buffer.from('GIF89a......'))).toBeNull();
    expect(sniffImageMime(ftyp('M4A '))).toBeNull(); // audio, not an image
    expect(sniffImageMime(Buffer.alloc(0))).toBeNull();
    expect(sniffImageMime(Buffer.from([0xff, 0xd8]))).toBeNull(); // truncated
  });
});

describe('sniffAudioKind', () => {
  it('recognises MP4/M4A and ADTS AAC', () => {
    expect(sniffAudioKind(ftyp('M4A '))).toBe('mp4');
    expect(sniffAudioKind(ftyp('isom'))).toBe('mp4');
    expect(sniffAudioKind(Buffer.from([0xff, 0xf1, 0x50, 0x80]))).toBe('aac');
  });

  it('refuses WebM, text, images and empty input', () => {
    expect(
      sniffAudioKind(Buffer.from([0x1a, 0x45, 0xdf, 0xa3, 0, 0])),
    ).toBeNull();
    expect(sniffAudioKind(Buffer.from('not audio at all'))).toBeNull();
    expect(sniffAudioKind(jpeg)).toBeNull();
    expect(sniffAudioKind(ftyp('heic'))).toBeNull();
    expect(sniffAudioKind(Buffer.alloc(0))).toBeNull();
  });
});

describe('audioMimeMatches', () => {
  it('pairs container with declared type', () => {
    expect(audioMimeMatches('audio/mp4', 'mp4')).toBe(true);
    expect(audioMimeMatches('audio/x-m4a', 'mp4')).toBe(true);
    expect(audioMimeMatches('audio/aac', 'aac')).toBe(true);
    expect(audioMimeMatches('audio/aac', 'mp4')).toBe(false);
    expect(audioMimeMatches('audio/webm', 'mp4')).toBe(false);
  });
});
