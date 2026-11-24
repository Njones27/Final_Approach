import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { checkImageForLocation } from '../src/posts/imageCheck.ts';
import { exif, gpsTag, jfif, jpeg, orientationTag, segment } from './jpeg.ts';

describe('an image with no place written in it', () => {
  test('a plain JPEG is clean', () => {
    assert.equal(checkImageForLocation(jpeg(jfif)), 'clean');
  });

  test('an Exif block that only says which way is up is clean', () => {
    assert.equal(checkImageForLocation(jpeg(jfif, exif([orientationTag]))), 'clean');
    assert.equal(checkImageForLocation(jpeg(exif([orientationTag, 0x8769], 'big'))), 'clean');
  });

  test('an XMP block that names no position is clean', () => {
    const xmp = segment(0xe1, 'http://ns.adobe.com/xap/1.0/\0<x:xmpmeta><tiff:Orientation>1</tiff:Orientation></x:xmpmeta>');
    assert.equal(checkImageForLocation(jpeg(jfif, xmp)), 'clean');
  });

  test('other blocks are passed over, and so are padded and bare markers', () => {
    const colorProfile = segment(0xe2, 'ICC_PROFILE\0' + 'x'.repeat(300));
    const padded = Uint8Array.from([0xff, 0xff, ...segment(0xdb, 'q'.repeat(64))]);
    const bare = Uint8Array.from([0xff, 0xd0]);
    assert.equal(checkImageForLocation(jpeg(jfif, colorProfile, padded, bare)), 'clean');
  });
});

describe('an image that says where it was taken', () => {
  test('an Exif block with a GPS directory carries a location, in either byte order', () => {
    assert.equal(checkImageForLocation(jpeg(jfif, exif([orientationTag, gpsTag]))), 'carriesLocation');
    assert.equal(checkImageForLocation(jpeg(exif([gpsTag], 'big'))), 'carriesLocation');
  });

  test('the GPS directory is found behind other blocks', () => {
    const colorProfile = segment(0xe2, 'ICC_PROFILE\0' + 'x'.repeat(300));
    assert.equal(checkImageForLocation(jpeg(jfif, colorProfile, exif([gpsTag]))), 'carriesLocation');
  });

  test('an XMP block that names a position carries a location', () => {
    const xmp = segment(0xe1, 'http://ns.adobe.com/xap/1.0/\0<rdf:Description exif:GPSLatitude="33,56.5N"/>');
    assert.equal(checkImageForLocation(jpeg(jfif, xmp)), 'carriesLocation');
    const extended = segment(0xe1, 'http://ns.adobe.com/xmp/extension/\0<exif:GPSLongitude>118,24.5W</exif:GPSLongitude>');
    assert.equal(checkImageForLocation(jpeg(extended)), 'carriesLocation');
  });

  test('an IPTC block can name a city, so it carries a location', () => {
    assert.equal(checkImageForLocation(jpeg(jfif, segment(0xed, 'Photoshop 3.0\x008BIM'))), 'carriesLocation');
  });

  test('an Exif block that cannot be read is not vouched for', () => {
    const cut = segment(0xe1, 'Exif\0\0II');
    const wrongOrder = segment(0xe1, 'Exif\0\0XX*\0\u0008\0\0\0\0\0');
    const wrongMagic = segment(0xe1, 'Exif\0\0II+\0\u0008\0\0\0\0\0');
    const directoryOutside = segment(0xe1, 'Exif\0\0II*\0ÿ\0\0\0\0\0');
    const entriesOutside = segment(0xe1, 'Exif\0\0II*\0\u0008\0\0\0\u0009\0');
    for (const block of [cut, wrongOrder, wrongMagic, directoryOutside, entriesOutside]) {
      assert.equal(checkImageForLocation(jpeg(block)), 'carriesLocation');
    }
  });
});

describe('bytes that are not a JPEG header', () => {
  test('nothing, a PNG, and text are not JPEGs', () => {
    assert.equal(checkImageForLocation(new Uint8Array()), 'notJPEG');
    assert.equal(checkImageForLocation(Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a])), 'notJPEG');
    assert.equal(checkImageForLocation(Buffer.from('<html></html>')), 'notJPEG');
  });

  test('a header that stops before the picture data is not a whole JPEG', () => {
    const whole = jpeg(jfif, exif([orientationTag]));
    // The last seven bytes start the picture data, so this cuts into the block before them.
    assert.equal(checkImageForLocation(whole.subarray(0, whole.length - 9)), 'notJPEG');
    assert.equal(checkImageForLocation(whole.subarray(0, 10)), 'notJPEG');
    assert.equal(checkImageForLocation(Uint8Array.from([0xff, 0xd8, 0xff, 0xd9])), 'notJPEG');
  });

  test('a block with a length that cannot be right is not a JPEG', () => {
    assert.equal(checkImageForLocation(Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x01, 0xff, 0xda])), 'notJPEG');
    assert.equal(checkImageForLocation(Uint8Array.from([0xff, 0xd8, 0x00, 0xe0, 0x00, 0x02, 0xff, 0xda])), 'notJPEG');
  });

  test('the check reads a view into a larger buffer from its own start', () => {
    const whole = jpeg(exif([gpsTag]));
    const padded = new Uint8Array(whole.length + 16);
    padded.set(whole, 16);
    assert.equal(checkImageForLocation(padded.subarray(16)), 'carriesLocation');
  });
});
