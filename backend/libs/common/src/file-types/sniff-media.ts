/**
 * Identifies an upload from its own bytes.
 *
 * A multipart request's `mimetype` is whatever the client chose to write, so
 * trusting it alone lets any file be stored (and later served) under an image
 * or audio content type. These checks read the file's signature instead, and
 * callers require it to agree with the declared type.
 *
 * Deliberately conservative: only the formats the API accepts are recognised,
 * and anything else returns `null` and is rejected.
 */

/** ISO-BMFF brands (bytes 8-11 after "ftyp") that mean an image. */
const HEIC_BRANDS = [
  'heic',
  'heix',
  'hevc',
  'hevx',
  'heim',
  'heis',
  'mif1',
  'msf1',
];

/** ISO-BMFF brands that mean MPEG-4 audio. */
const MP4_AUDIO_BRANDS = [
  'M4A ',
  'M4B ',
  'mp42',
  'isom',
  'iso2',
  'mp41',
  'dash',
];

function ascii(buffer: Buffer, start: number, end: number): string {
  return buffer.subarray(start, end).toString('latin1');
}

function isoBmffBrand(buffer: Buffer): string | null {
  if (buffer.length < 12 || ascii(buffer, 4, 8) !== 'ftyp') return null;
  return ascii(buffer, 8, 12);
}

/** MIME type of a JPEG / PNG / WebP / HEIC image, or null. */
export function sniffImageMime(buffer: Buffer): string | null {
  if (
    buffer.length >= 3 &&
    buffer[0] === 0xff &&
    buffer[1] === 0xd8 &&
    buffer[2] === 0xff
  ) {
    return 'image/jpeg';
  }
  if (
    buffer.length >= 8 &&
    buffer
      .subarray(0, 8)
      .equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
  ) {
    return 'image/png';
  }
  if (
    buffer.length >= 12 &&
    ascii(buffer, 0, 4) === 'RIFF' &&
    ascii(buffer, 8, 12) === 'WEBP'
  ) {
    return 'image/webp';
  }
  const brand = isoBmffBrand(buffer);
  if (brand && HEIC_BRANDS.includes(brand)) return 'image/heic';
  return null;
}

/** Container family of an MPEG-4 / AAC audio file: 'mp4' (MP4/M4A) or 'aac' (ADTS), or null. */
export function sniffAudioKind(buffer: Buffer): 'mp4' | 'aac' | null {
  const brand = isoBmffBrand(buffer);
  if (brand && MP4_AUDIO_BRANDS.includes(brand)) return 'mp4';
  // ADTS frame sync: 12 set bits, layer 00.
  if (buffer.length >= 2 && buffer[0] === 0xff && (buffer[1] & 0xf6) === 0xf0)
    return 'aac';
  return null;
}

/** Whether [declared] is an audio MIME type that [kind] can legitimately carry. */
export function audioMimeMatches(
  declared: string,
  kind: 'mp4' | 'aac',
): boolean {
  return kind === 'mp4'
    ? ['audio/mp4', 'audio/m4a', 'audio/x-m4a'].includes(declared)
    : declared === 'audio/aac';
}
