/** Builds small JPEG headers for tests. None of them holds a picture. */

/** One block of a JPEG header, with its marker and its length in front. */
export function segment(marker: number, payload: Uint8Array | string): Uint8Array {
  const body = typeof payload === 'string' ? Buffer.from(payload, 'latin1') : payload;
  const length = body.length + 2;
  return Uint8Array.from([0xff, marker, length >> 8, length & 0xff, ...body]);
}

/** A JPEG header made of the given blocks, up to where the picture data starts. */
export function jpeg(...segments: Uint8Array[]): Uint8Array {
  const startOfScan = segment(0xda, Uint8Array.from([0, 0, 0]));
  return Uint8Array.from([0xff, 0xd8, ...segments.flatMap((part) => [...part]), ...startOfScan]);
}

/**
 * An Exif block whose first directory holds the given tags. Each entry is
 * a tag with a value of zero, which is all the check reads.
 */
export function exif(tags: number[], order: 'little' | 'big' = 'little'): Uint8Array {
  const little = order === 'little';
  const tiff = Buffer.alloc(8 + 2 + tags.length * 12 + 4);
  tiff.write(little ? 'II' : 'MM', 0, 'latin1');
  if (little) {
    tiff.writeUInt16LE(42, 2);
    tiff.writeUInt32LE(8, 4);
    tiff.writeUInt16LE(tags.length, 8);
  } else {
    tiff.writeUInt16BE(42, 2);
    tiff.writeUInt32BE(8, 4);
    tiff.writeUInt16BE(tags.length, 8);
  }
  tags.forEach((tag, index) => {
    if (little) tiff.writeUInt16LE(tag, 10 + index * 12);
    else tiff.writeUInt16BE(tag, 10 + index * 12);
  });
  return segment(0xe1, Buffer.concat([Buffer.from('Exif\0\0', 'latin1'), tiff]));
}

export const jfif = segment(0xe0, 'JFIF\0\u0001\u0001\0\0\u0001\0\u0001\0\0');
export const orientationTag = 0x0112;
export const gpsTag = 0x8825;
