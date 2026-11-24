import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { parsePhotoUpload } from '../src/photos/document.ts';

const limits = { maxDocumentBytes: 200, maxImageBytes: 1000 };
const body = (value: unknown) => JSON.stringify(value);

function refusal(text: string | undefined, photoID = 'p1'): string {
  const result = parsePhotoUpload(text, photoID, limits);
  assert.equal(result.ok, false);
  return result.ok ? '' : result.message;
}

describe('reading a photo to save', () => {
  test('a document alone is accepted', () => {
    const result = parsePhotoUpload(body({ document: { id: 'p1', aircraftType: 'B-2' } }), 'p1', limits);
    assert.deepEqual(result, {
      ok: true,
      value: { documentJSON: '{"id":"p1","aircraftType":"B-2"}' },
    });
  });

  test('a document with an image size is accepted', () => {
    const result = parsePhotoUpload(body({ document: { id: 'p1' }, imageBytes: 1000 }), 'p1', limits);
    assert.deepEqual(result, { ok: true, value: { documentJSON: '{"id":"p1"}', imageBytes: 1000 } });
  });

  test('a missing or broken body is refused', () => {
    assert.match(refusal(undefined), /no body/);
    assert.match(refusal(''), /no body/);
    assert.match(refusal('{'), /not JSON/);
    assert.match(refusal('[]'), /must be an object/);
    assert.match(refusal(body({})), /needs a document/);
    assert.match(refusal(body({ document: [] })), /needs a document/);
  });

  test('a document filed under another id is refused', () => {
    assert.match(refusal(body({ document: { id: 'p2' } })), /does not match/);
    assert.match(refusal(body({ document: {} })), /does not match/);
  });

  test('an unusable id is refused before the body is read', () => {
    assert.match(refusal(body({ document: { id: '../x' } }), '../x'), /not usable/);
  });

  test('a document over the limit is refused', () => {
    const large = { id: 'p1', note: 'x'.repeat(200) };
    assert.match(refusal(body({ document: large })), /too large/);
    assert.match(refusal(body({ document: { id: 'p1' }, padding: 'x'.repeat(5000) })), /too large/);
  });

  test('the limit counts bytes, not characters', () => {
    const accents = { id: 'p1', note: 'é'.repeat(95) };
    assert.match(refusal(body({ document: accents })), /too large/);
  });

  test('an image size that is not a whole number above zero is refused', () => {
    for (const imageBytes of [0, -1, 1.5, '1000', true]) {
      assert.match(refusal(body({ document: { id: 'p1' }, imageBytes })), /whole number/);
    }
  });

  test('an image over the limit is refused', () => {
    assert.match(refusal(body({ document: { id: 'p1' }, imageBytes: 1001 })), /image is too large/);
  });
});
