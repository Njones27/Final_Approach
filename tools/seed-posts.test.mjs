// Run with: node --test tools/*.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  choosePhotos,
  maxImageBytes,
  parseArguments,
  parseStageFile,
  photoIDFor,
  postPhoto,
  signIn,
  stripMetadata,
} from './seed-posts.mjs';

function segment(marker, payload) {
  const body = Buffer.from(payload, 'latin1');
  return Buffer.concat([Buffer.from([0xff, marker, (body.length + 2) >> 8, (body.length + 2) & 0xff]), body]);
}

const scan = Buffer.from([0xff, 0xda, 0x00, 0x02, 0x11, 0x22, 0xff, 0xd9]);
const jpeg = (...segments) => Buffer.concat([Buffer.from([0xff, 0xd8]), ...segments, scan]);

const stage = { apiHost: 'api.example', authHost: 'auth.example', clientID: 'client' };

function reply(status, body) {
  return { ok: status >= 200 && status < 300, status, text: async () => JSON.stringify(body) };
}

test('a stage file gives the backend the app is built with', () => {
  const stageFile = '// Beta.\nAPI_HOST = a.example\nAUTH_HOST = b.example\nAUTH_CLIENT_ID = abc123\n';
  assert.deepEqual(parseStageFile(stageFile), { apiHost: 'a.example', authHost: 'b.example', clientID: 'abc123' });
  assert.throws(() => parseStageFile('API_HOST = a.example\n'));
});

test('the command line defaults to beta and refuses what it does not know', () => {
  const options = parseArguments(['--account', ' test-one ', '--folder', '/photos', '--only', 'F22-, pax']);
  assert.equal(options.stage, 'beta');
  assert.equal(options.account, 'test-one');
  assert.deepEqual(options.only, ['f22-', 'pax']);
  assert.throws(() => parseArguments(['--folder', '/photos']), /--account/);
  assert.throws(() => parseArguments(['--account', 'a', '--folder', '/p', '--stage', 'live']), /beta or prod/);
  assert.throws(() => parseArguments(['--account', 'a', '--folder', '/p', '--limit', '0']), /limit/);
  assert.throws(() => parseArguments(['--account', 'a', '--folder', '/p', '--password', 'x']), /not an option/);
});

test('only JPEGs are chosen, and a Finder copy is left out', () => {
  const names = ['b2.jpg', 'b2 2.jpg', 'f22-one.JPG', 'f22-two 3.jpeg', 'notes.txt', '.hidden.jpg', 'dog.jpg'];
  assert.deepEqual(choosePhotos(names), ['b2.jpg', 'dog.jpg', 'f22-one.JPG', 'f22-two 3.jpeg']);
  assert.deepEqual(choosePhotos(names, { only: ['f22-', 'b2'] }), ['b2.jpg', 'f22-one.JPG', 'f22-two 3.jpeg']);
  assert.deepEqual(choosePhotos(names, { limit: 1 }), ['b2.jpg']);
});

test('a photo id is steady, usable, and differs by account', () => {
  const id = photoIDFor('test-one', 'b2');
  assert.equal(id, photoIDFor('test-one', 'b2'));
  assert.notEqual(id, photoIDFor('test-two', 'b2'));
  assert.match(id, /^[A-Za-z0-9_-]{1,80}$/);
});

test('Exif, XMP, and IPTC are taken out and the rest is kept', () => {
  const profile = segment(0xe2, 'ICC_PROFILE\0color');
  const table = segment(0xdb, 'table');
  const image = jpeg(
    segment(0xe0, 'JFIF\0'),
    segment(0xe1, 'Exif\0\0gps'),
    segment(0xe1, 'http://ns.adobe.com/xap/1.0/\0GPSLatitude'),
    profile,
    segment(0xed, 'Photoshop 3.0\0city'),
    table,
  );
  const clean = stripMetadata(image);
  assert.deepEqual(clean, jpeg(segment(0xe0, 'JFIF\0'), profile, table));
  assert.equal(stripMetadata(Buffer.from('not a picture')), undefined);
  assert.equal(stripMetadata(Buffer.concat([Buffer.from([0xff, 0xd8]), segment(0xe0, 'JFIF\0')])), undefined);
});

test('signing in sends the password flow and returns the access token', async () => {
  let sent;
  const token = await signIn(stage, 'test-one', 'a password', async (url, request) => {
    sent = { url, request };
    return reply(200, { AuthenticationResult: { AccessToken: 'token' } });
  });
  assert.equal(token, 'token');
  assert.equal(sent.url, 'https://auth.example/');
  assert.equal(sent.request.headers['X-Amz-Target'], 'AWSCognitoIdentityProviderService.InitiateAuth');
  assert.deepEqual(JSON.parse(sent.request.body), {
    AuthFlow: 'USER_PASSWORD_AUTH',
    ClientId: 'client',
    AuthParameters: { USERNAME: 'test-one', PASSWORD: 'a password' },
  });
});

test('a refused sign in says so without repeating the password', async () => {
  const refuse = async () => reply(400, { __type: 'com.amazonaws#NotAuthorizedException' });
  await assert.rejects(signIn(stage, 'test-one', 'secret-word', refuse), (error) => {
    assert.match(error.message, /not right/);
    assert.doesNotMatch(error.message, /secret-word/);
    return true;
  });
  const challenge = async () => reply(200, { ChallengeName: 'NEW_PASSWORD_REQUIRED' });
  await assert.rejects(signIn(stage, 'test-one', 'x', challenge), /not ready/);
});

test('a photo is saved, its clean image sent, and then posted', async () => {
  const calls = [];
  const image = jpeg(segment(0xe1, 'Exif\0\0gps'), segment(0xdb, 'table'));
  const clean = stripMetadata(image);
  const fetcher = async (url, request) => {
    calls.push({ url, request });
    if (url === 'https://api.example/photos/seed-1') {
      return reply(200, {
        upload: { url: 'https://bucket.example/put', method: 'PUT', headers: { 'Content-Type': 'image/jpeg', 'Content-Length': '1' } },
      });
    }
    return reply(200, {});
  };
  const outcome = await postPhoto({ stage, token: 'token', photoID: 'seed-1', fileName: 'b2.jpg', image, fetcher });

  assert.equal(outcome, 'posted');
  assert.deepEqual(calls.map((call) => `${call.request.method} ${call.url}`), [
    'PUT https://api.example/photos/seed-1',
    'PUT https://bucket.example/put',
    'PUT https://api.example/posts/seed-1',
  ]);
  assert.deepEqual(JSON.parse(calls[0].request.body), {
    document: { id: 'seed-1', seededFrom: 'b2.jpg' },
    imageBytes: clean.length,
  });
  assert.equal(calls[0].request.headers.Authorization, 'Bearer token');
  assert.deepEqual(calls[1].request.body, clean);
  // The upload link carries its own permission, so the token stays home.
  assert.deepEqual(calls[1].request.headers, { 'Content-Type': 'image/jpeg' });
});

test('a file that cannot be posted is skipped with the reason', async () => {
  const never = async () => assert.fail('nothing should be sent');
  const base = { stage, token: 'token', photoID: 'seed-1', fileName: 'x.jpg' };
  assert.equal(await postPhoto({ ...base, image: Buffer.from('text'), fetcher: never }), 'not a JPEG');
  const huge = Buffer.concat([jpeg(segment(0xdb, 'table')), Buffer.alloc(maxImageBytes)]);
  assert.equal(await postPhoto({ ...base, image: huge, fetcher: never }), 'larger than 8 MB');

  const refused = async (url) =>
    url.includes('/posts/')
      ? reply(409, { message: 'Save the photo and its image before posting it.' })
      : reply(200, { upload: { url: 'https://bucket.example/put', method: 'PUT', headers: { 'Content-Type': 'image/jpeg' } } });
  const image = jpeg(segment(0xdb, 'table'));
  assert.match(await postPhoto({ ...base, image, fetcher: refused }), /^not posted \(Save the photo/);
  const gone = async () => reply(410, { message: 'This account was deleted.' });
  assert.match(await postPhoto({ ...base, image, fetcher: gone }), /^not saved \(This account/);
});
