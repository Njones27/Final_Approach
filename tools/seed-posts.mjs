#!/usr/bin/env node
// Posts a folder of JPEGs from a test account, so another account has
// photos to vote on. Nobody is shown their own photos in the Vote screen,
// so a stage with one real user has nothing to vote on until a second
// account posts. See "Photos to vote on" in docs/backend.md.
//
//   node tools/seed-posts.mjs --account test-one --folder ~/Pictures/planes
//
// It needs Node 22 and nothing else. The password is asked for with the
// typing hidden, or read from FA_TEST_PASSWORD. It is never written anywhere.

import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { homedir } from 'node:os';
import { basename, dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/** The largest image the backend takes. It is `maxImageBytes` in the stage settings. */
export const maxImageBytes = 8 * 1024 * 1024;

const usage = `Usage: node tools/seed-posts.mjs --account <name> --folder <path> [options]

  --account <name>   The test account that posts. Not the one you vote with.
  --folder <path>    A folder of JPEGs. Subfolders are not read.
  --stage <stage>    beta (the default) or prod.
  --only <a,b,c>     Post only files whose names start with one of these.
  --limit <count>    Post at most this many.
  --dry-run          List what would be posted and stop.

The password is asked for, or read from FA_TEST_PASSWORD.`;

/** Reads the command line. Throws with a message for the user when it is wrong. */
export function parseArguments(argv) {
  const options = { stage: 'beta', only: [], limit: Infinity, dryRun: false };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = () => {
      index += 1;
      if (argv[index] === undefined) throw new Error(`${flag} needs a value.`);
      return argv[index];
    };
    switch (flag) {
      case '--account':
        options.account = value().trim();
        break;
      case '--folder':
        options.folder = value().replace(/^~(?=\/|$)/, homedir());
        break;
      case '--stage':
        options.stage = value();
        break;
      case '--only':
        options.only = value().split(',').map((prefix) => prefix.trim().toLowerCase()).filter(Boolean);
        break;
      case '--limit':
        options.limit = Number(value());
        break;
      case '--dry-run':
        options.dryRun = true;
        break;
      default:
        throw new Error(`${flag} is not an option.`);
    }
  }
  if (!options.account) throw new Error('Name the test account with --account.');
  if (!options.folder) throw new Error('Name the folder of photos with --folder.');
  if (!['beta', 'prod'].includes(options.stage)) throw new Error('The stage is beta or prod.');
  if (!(Number.isInteger(options.limit) && options.limit > 0) && options.limit !== Infinity) {
    throw new Error('The limit is a whole number above zero.');
  }
  return options;
}

/** Reads a stage's backend from the same file the app is built with. */
export function parseStageFile(text) {
  const values = {};
  for (const line of text.split('\n')) {
    const match = /^\s*([A-Z_]+)\s*=\s*(\S+)\s*$/.exec(line);
    if (match) values[match[1]] = match[2];
  }
  const { API_HOST: apiHost, AUTH_HOST: authHost, AUTH_CLIENT_ID: clientID } = values;
  if (!apiHost || !authHost || !clientID) throw new Error('The stage file does not name its backend.');
  return { apiHost, authHost, clientID };
}

/**
 * Picks the files to post from the names in a folder. A name such as
 * "b2 2.jpg" is the copy the Finder makes of "b2.jpg", so it is left out
 * when the first one is there.
 */
export function choosePhotos(names, { only = [], limit = Infinity } = {}) {
  const jpegs = names.filter((name) => /\.jpe?g$/i.test(name) && !name.startsWith('.'));
  const present = new Set(jpegs.map((name) => name.toLowerCase()));
  return jpegs
    .filter((name) => {
      const copy = /^(.*) \d+(\.jpe?g)$/i.exec(name);
      return !(copy && present.has(`${copy[1]}${copy[2]}`.toLowerCase()));
    })
    .filter((name) => only.length === 0 || only.some((prefix) => name.toLowerCase().startsWith(prefix)))
    .sort((a, b) => a.localeCompare(b))
    .slice(0, limit);
}

/**
 * The id a file is posted under. It comes from the account and the file
 * name, so a second run saves the same photos again and posts nothing twice.
 */
export function photoIDFor(account, fileName) {
  const digest = createHash('sha256').update(`${account}\n${fileName}`).digest('hex');
  return `seed-${digest.slice(0, 32)}`;
}

/**
 * Returns the JPEG with its Exif, XMP, and IPTC blocks taken out, or
 * undefined when the bytes are not a JPEG. Other users see a posted image,
 * and it must not say where it was taken. The app saves its images with no
 * metadata, and the backend refuses a post that carries a place. The color
 * profile is kept, so the picture looks the same.
 */
export function stripMetadata(bytes) {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return undefined;
  const kept = [bytes.subarray(0, 2)];
  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) return undefined;
    const marker = bytes[offset + 1];
    if (marker === 0xff) {
      offset += 1;
      continue;
    }
    // The picture data starts here. Everything from here on is kept as it is.
    if (marker === 0xda) {
      kept.push(bytes.subarray(offset));
      return Buffer.concat(kept);
    }
    if (marker === 0xd9) return undefined;
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      kept.push(bytes.subarray(offset, offset + 2));
      offset += 2;
      continue;
    }
    const length = bytes[offset + 2] * 256 + bytes[offset + 3];
    const end = offset + 2 + length;
    if (length < 2 || end > bytes.length) return undefined;
    // APP1 holds Exif and XMP. APP13 holds IPTC.
    if (marker !== 0xe1 && marker !== 0xed) kept.push(bytes.subarray(offset, end));
    offset = end;
  }
  return undefined;
}

async function answerOf(response) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

/** Signs a test account in and returns the token the API takes. */
export async function signIn(stage, account, password, fetcher = fetch) {
  const response = await fetcher(`https://${stage.authHost}/`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-amz-json-1.1',
      'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth',
    },
    body: JSON.stringify({
      AuthFlow: 'USER_PASSWORD_AUTH',
      ClientId: stage.clientID,
      AuthParameters: { USERNAME: account, PASSWORD: password },
    }),
  });
  const answer = await answerOf(response);
  const token = answer.AuthenticationResult?.AccessToken;
  if (response.ok && token) return token;
  const name = String(answer.__type ?? '').split('#').pop();
  if (name === 'NotAuthorizedException' || name === 'UserNotFoundException') {
    throw new Error('The name or the password is not right for this stage.');
  }
  if (answer.ChallengeName) {
    throw new Error('This account is not ready. Give it a permanent password first.');
  }
  throw new Error(`Signing in failed. ${name || response.status}`);
}

/**
 * Saves one image as a photo of the signed in account and posts it.
 * Returns 'posted', or a short reason it was skipped.
 */
export async function postPhoto({ stage, token, photoID, fileName, image, fetcher = fetch }) {
  const clean = stripMetadata(image);
  if (!clean) return 'not a JPEG';
  if (clean.length > maxImageBytes) return 'larger than 8 MB';

  const api = `https://${stage.apiHost}`;
  const signedIn = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  // The backend keeps the record for its owner and does not read inside
  // it. The app lists a record it cannot read as one to leave alone.
  const document = { id: photoID, seededFrom: fileName };
  const saved = await fetcher(`${api}/photos/${photoID}`, {
    method: 'PUT',
    headers: signedIn,
    body: JSON.stringify({ document, imageBytes: clean.length }),
  });
  const save = await answerOf(saved);
  if (!saved.ok || !save.upload) return `not saved (${save.message ?? saved.status})`;

  const sent = await fetcher(save.upload.url, {
    method: save.upload.method,
    headers: { 'Content-Type': save.upload.headers['Content-Type'] },
    body: clean,
  });
  if (!sent.ok) return `image not sent (${sent.status})`;

  const posted = await fetcher(`${api}/posts/${photoID}`, { method: 'PUT', headers: signedIn });
  if (posted.ok) return 'posted';
  const refusal = await answerOf(posted);
  return `not posted (${refusal.message ?? posted.status})`;
}

/** Asks for the password with the typing hidden. */
function askPassword(prompt) {
  const { stdin, stdout } = process;
  if (!stdin.isTTY) throw new Error('Set FA_TEST_PASSWORD, or run this in a terminal to be asked.');
  return new Promise((done, failed) => {
    let typed = '';
    stdout.write(prompt);
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding('utf8');
    const finish = (settle) => {
      stdin.setRawMode(false);
      stdin.pause();
      stdin.removeListener('data', onData);
      stdout.write('\n');
      settle();
    };
    function onData(chunk) {
      for (const key of chunk) {
        if (key === '\r' || key === '\n') return finish(() => done(typed));
        if (key === '\u0003') return finish(() => failed(new Error('Stopped.')));
        if (key === '\u007f' || key === '\b') typed = typed.slice(0, -1);
        else typed += key;
      }
    }
    stdin.on('data', onData);
  });
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const stage = parseStageFile(
    await readFile(join(repoRoot, 'FinalApproach', 'Config', 'Stages', `${options.stage}.xcconfig`), 'utf8'),
  );
  const names = choosePhotos(await readdir(options.folder), options);
  if (names.length === 0) throw new Error('No JPEGs to post were found in that folder.');

  console.log(`${names.length} photos to post on ${options.stage} as ${options.account}.`);
  if (options.dryRun) {
    for (const name of names) console.log(`  ${name}`);
    return;
  }

  const password = process.env.FA_TEST_PASSWORD || (await askPassword(`Password for ${options.account}: `));
  const token = await signIn(stage, options.account, password);

  let posted = 0;
  for (const fileName of names) {
    const image = await readFile(join(options.folder, fileName));
    const photoID = photoIDFor(options.account, basename(fileName, extname(fileName)));
    const outcome = await postPhoto({ stage, token, photoID, fileName, image });
    if (outcome === 'posted') posted += 1;
    console.log(`  ${outcome === 'posted' ? 'posted ' : 'skipped'}  ${fileName}${outcome === 'posted' ? '' : `  ${outcome}`}`);
  }
  console.log(`${posted} of ${names.length} are in the vote queue for every other account.`);
  if (posted < names.length) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error.message);
    if (/option|--|Name the/.test(error.message)) console.error(`\n${usage}`);
    process.exitCode = 1;
  });
}
