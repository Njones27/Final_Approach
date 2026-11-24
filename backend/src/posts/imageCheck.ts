/**
 * What a look inside an image found.
 *
 * `clean` means no place is written in the file. `carriesLocation` means
 * one is, or that a block which could hold one cannot be read. `notJPEG`
 * means the bytes are not a whole JPEG header.
 */
export type ImageCheck = 'clean' | 'carriesLocation' | 'notJPEG';

const startOfImage = 0xd8;
const endOfImage = 0xd9;
const startOfScan = 0xda;
const app1 = 0xe1;
const app13 = 0xed;
/** The tag in the first Exif directory that points at the GPS directory. */
const gpsDirectoryTag = 0x8825;

const exifHeader = 'Exif\0\0';
const xmpHeader = 'http://ns.adobe.com/x';
const iptcHeader = 'Photoshop 3.0';
const xmpPlaceNames = ['GPSLatitude', 'GPSLongitude', 'GPSAltitude', 'GPSDestLatitude'];

function text(bytes: Uint8Array): string {
  return Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString('latin1');
}

/**
 * Whether an Exif block points at a GPS directory. A block that cannot be
 * read counts as pointing at one, because nothing can vouch for it.
 */
function exifHasGPS(tiff: Uint8Array): boolean {
  if (tiff.length < 8) return true;
  const view = new DataView(tiff.buffer, tiff.byteOffset, tiff.byteLength);
  const order = view.getUint16(0);
  if (order !== 0x4949 && order !== 0x4d4d) return true;
  const little = order === 0x4949;
  if (view.getUint16(2, little) !== 42) return true;

  const directory = view.getUint32(4, little);
  if (directory + 2 > tiff.length) return true;
  const entries = view.getUint16(directory, little);
  // Each entry is twelve bytes and starts with its tag.
  if (directory + 2 + entries * 12 > tiff.length) return true;
  for (let index = 0; index < entries; index += 1) {
    if (view.getUint16(directory + 2 + index * 12, little) === gpsDirectoryTag) return true;
  }
  return false;
}

/**
 * Looks through the header of a JPEG for a written place.
 *
 * A post is shown to other users, and a post marked undisclosed must show
 * its location to nobody. The app saves its images with no metadata, and
 * this check makes the backend hold that line too. It reads the blocks in
 * front of the picture data. An Exif block with a GPS directory, an XMP
 * block that names a GPS position, and an IPTC block, which can name a
 * city, each count as a location.
 */
export function checkImageForLocation(bytes: Uint8Array): ImageCheck {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== startOfImage) return 'notJPEG';

  let offset = 2;
  while (offset + 2 <= bytes.length) {
    if (bytes[offset] !== 0xff) return 'notJPEG';
    const marker = bytes[offset + 1];
    if (marker === undefined) return 'notJPEG';
    // A marker may be padded with extra 0xFF bytes.
    if (marker === 0xff) {
      offset += 1;
      continue;
    }
    // The picture data starts here, and every block this check reads comes before it.
    if (marker === startOfScan) return 'clean';
    if (marker === endOfImage) return 'notJPEG';
    // These markers stand alone, with no length after them.
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      offset += 2;
      continue;
    }

    const high = bytes[offset + 2];
    const low = bytes[offset + 3];
    if (high === undefined || low === undefined) return 'notJPEG';
    // The length counts its own two bytes.
    const length = high * 256 + low;
    const end = offset + 2 + length;
    if (length < 2 || end > bytes.length) return 'notJPEG';
    const payload = bytes.subarray(offset + 4, end);

    if (marker === app1) {
      const start = text(payload.subarray(0, 32));
      if (start.startsWith(exifHeader)) {
        if (exifHasGPS(payload.subarray(exifHeader.length))) return 'carriesLocation';
      } else if (start.startsWith(xmpHeader)) {
        const packet = text(payload);
        if (xmpPlaceNames.some((name) => packet.includes(name))) return 'carriesLocation';
      }
    } else if (marker === app13 && text(payload.subarray(0, 32)).startsWith(iptcHeader)) {
      return 'carriesLocation';
    }
    offset = end;
  }
  // The bytes ran out before the picture data began.
  return 'notJPEG';
}
