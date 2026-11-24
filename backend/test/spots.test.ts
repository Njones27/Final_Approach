import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import {
  catalog,
  catalogLimits,
  isUsableSpotID,
  kilometersBetween,
  problemsIn,
  type Airport,
  type Spot,
} from '../src/spots/catalog.ts';
import { makeAwsSpotPhotoStore, spotPhotoOf } from '../src/spots/awsStore.ts';
import { makeSpotsHandler } from '../src/spots/handler.ts';
import type { SpotPhoto, SpotPhotoStore } from '../src/spots/store.ts';
import { apiEvent, fakeClient } from './support.ts';

const spot = (changes: Partial<Spot> = {}): Spot => ({
  id: 'xyz-east-fence',
  name: 'East fence',
  summary: 'Arrivals pass low over the road.',
  latitude: 10.01,
  longitude: 20.01,
  accessNotes: 'Park on the public road and stay behind the fence.',
  localRules: 'The airport asks photographers not to use ladders.',
  runwayNotes: 'Sees the east end of runway 09 and 27.',
  ...changes,
});

const airport = (changes: Partial<Airport> = {}): Airport => ({
  code: 'XYZ',
  city: 'Testville',
  latitude: 10,
  longitude: 20,
  spots: [spot()],
  ...changes,
});

describe('the list of spots', () => {
  test('the list that ships has nothing wrong with it', () => {
    assert.deepEqual(problemsIn(catalog), []);
  });

  test('a well formed listing has no problems', () => {
    assert.deepEqual(problemsIn([airport()]), []);
  });

  test('a runway note may be left empty, and nothing else may', () => {
    assert.deepEqual(problemsIn([airport({ spots: [spot({ runwayNotes: '' })] })]), []);
    assert.deepEqual(problemsIn([airport({ spots: [spot({ name: ' ' })] })]), ['Spot xyz-east-fence has no name.']);
    assert.deepEqual(problemsIn([airport({ spots: [spot({ summary: '' })] })]), [
      'Spot xyz-east-fence has no summary.',
    ]);
    assert.deepEqual(problemsIn([airport({ spots: [spot({ accessNotes: '' })] })]), [
      'Spot xyz-east-fence has no access note.',
    ]);
    assert.deepEqual(problemsIn([airport({ city: '' })]), ['Airport XYZ has no city.']);
  });

  test('a spot must say what is asked of photographers there', () => {
    assert.deepEqual(problemsIn([airport({ spots: [spot({ localRules: '' })] })]), [
      'Spot xyz-east-fence has no local rule.',
    ]);
  });

  test('an airport is named by a three letter code and listed once', () => {
    assert.deepEqual(problemsIn([airport({ code: 'xyz' })]), ['Airport xyz does not have a three letter code.']);
    assert.deepEqual(problemsIn([airport(), airport({ spots: [spot({ id: 'xyz-west' })] })]), [
      'Airport XYZ is listed twice.',
    ]);
  });

  test('an airport with no spots is not listed', () => {
    assert.deepEqual(problemsIn([airport({ spots: [] })]), ['Airport XYZ has no spots.']);
  });

  test('a spot id is lowercase words joined by hyphens, and is used once', () => {
    for (const id of ['atl-south-approach', 'a', 'spot-27r']) assert.ok(isUsableSpotID(id), id);
    for (const id of ['', 'East', 'a_b', 'a--b', '-a', 'a-', 'a b', 'a/b', 'x'.repeat(61), 7, undefined]) {
      assert.ok(!isUsableSpotID(id), String(id));
    }
    assert.deepEqual(problemsIn([airport({ spots: [spot({ id: 'East Fence' })] })]), [
      'Spot East Fence has an id that is not usable.',
    ]);
    const twice = [airport(), airport({ code: 'ABC' })];
    assert.deepEqual(problemsIn(twice), ['Spot xyz-east-fence is listed twice.']);
  });

  test('a pin must be on the map and near its airport', () => {
    assert.deepEqual(problemsIn([airport({ spots: [spot({ latitude: 91 })] })]), [
      'Spot xyz-east-fence has a pin that is not on the map.',
    ]);
    assert.deepEqual(problemsIn([airport({ spots: [spot({ longitude: Number.NaN })] })]), [
      'Spot xyz-east-fence has a pin that is not on the map.',
    ]);
    assert.deepEqual(problemsIn([airport({ latitude: -91 })]), ['Airport XYZ has a pin that is not on the map.']);
    // A pin with its latitude and longitude swapped lands far away.
    assert.deepEqual(problemsIn([airport({ spots: [spot({ latitude: 20.01, longitude: 10.01 })] })]), [
      `Spot xyz-east-fence is more than ${catalogLimits.maxKmFromAirport} km from its airport.`,
    ]);
  });

  test('a note has a longest length and no space at its ends', () => {
    const long = 'x'.repeat(catalogLimits.maxNoteLength + 1);
    assert.deepEqual(problemsIn([airport({ spots: [spot({ summary: long })] })]), [
      `Spot xyz-east-fence has a summary longer than ${catalogLimits.maxNoteLength} characters.`,
    ]);
    assert.deepEqual(problemsIn([airport({ spots: [spot({ name: 'East fence ' })] })]), [
      'Spot xyz-east-fence has a name with space at an end.',
    ]);
  });

  test('distance is measured over the ground', () => {
    const km = kilometersBetween({ latitude: 0, longitude: 0 }, { latitude: 0, longitude: 1 });
    assert.ok(Math.abs(km - 111.19) < 0.1, String(km));
    assert.equal(kilometersBetween({ latitude: 33.64, longitude: -84.43 }, { latitude: 33.64, longitude: -84.43 }), 0);
  });
});

/** A store of spot photos kept in memory, which remembers what was asked. */
function memoryPhotos(photos: Record<string, SpotPhoto[]> = {}) {
  const asked: { spotID: string; limit: number }[] = [];
  const store: SpotPhotoStore = {
    async photosAt(spotID, limit) {
      asked.push({ spotID, limit });
      return (photos[spotID] ?? []).slice(0, limit);
    },
    async imageLink(photo) {
      return `https://images.example.test/${photo.postID}?signed`;
    },
  };
  return { store, asked };
}

const handlerFor = (airports: Airport[], photos: Record<string, SpotPhoto[]> = {}) => {
  const memory = memoryPhotos(photos);
  const handler = makeSpotsHandler({ airports, store: memory.store, photosPerSpot: 2, imageLinkSeconds: 900 });
  return { handler, asked: memory.asked };
};

describe('the spots route', () => {
  const { handler } = handlerFor([airport()]);

  test('a signed in user gets every airport with its spots', async () => {
    const result = await handler(apiEvent({ routeKey: 'GET /spots' }));
    assert.equal(result.statusCode, 200);
    assert.deepEqual(JSON.parse(result.body ?? ''), {
      airports: [
        {
          code: 'XYZ',
          city: 'Testville',
          latitude: 10,
          longitude: 20,
          spots: [
            {
              id: 'xyz-east-fence',
              name: 'East fence',
              summary: 'Arrivals pass low over the road.',
              latitude: 10.01,
              longitude: 20.01,
              accessNotes: 'Park on the public road and stay behind the fence.',
              localRules: 'The airport asks photographers not to use ladders.',
              runwayNotes: 'Sees the east end of runway 09 and 27.',
            },
          ],
        },
      ],
    });
  });

  test('only the named fields of a listing are sent', async () => {
    const extra = { ...spot(), curatorNote: 'Checked by phone.' } as Spot;
    const result = await handlerFor([airport({ spots: [extra] })]).handler(apiEvent({ routeKey: 'GET /spots' }));
    assert.ok(!(result.body ?? '').includes('curatorNote'));
  });

  test('an empty list is an answer and not a fault', async () => {
    const result = await handlerFor([]).handler(apiEvent({ routeKey: 'GET /spots' }));
    assert.equal(result.statusCode, 200);
    assert.deepEqual(JSON.parse(result.body ?? ''), { airports: [] });
  });

  test('a caller who is not signed in is turned away', async () => {
    const result = await handler(apiEvent({ routeKey: 'GET /spots', claims: null }));
    assert.equal(result.statusCode, 401);
    assert.equal(JSON.parse(result.body ?? '').code, 'notSignedIn');
  });

  test('any other route is not found', async () => {
    const result = await handler(apiEvent({ routeKey: 'PUT /spots' }));
    assert.equal(result.statusCode, 404);
  });
});

describe('the photos on a spot’s page', () => {
  const best: SpotPhoto = {
    postID: 'post-best',
    ownerID: 'owner-1',
    photoID: 'photo-1',
    score: 91,
    aircraftType: 'Boeing 737-800',
    airline: 'Southwest',
  };
  const plain: SpotPhoto = { postID: 'post-plain', ownerID: 'owner-2', photoID: 'photo-2', score: 64 };
  const third: SpotPhoto = { postID: 'post-third', ownerID: 'owner-3', photoID: 'photo-3', score: 40 };
  const page = (spotID: string) => apiEvent({ routeKey: 'GET /spots/{spotID}/photos', spotID });
  const bodyOf = (result: { body?: string | undefined }) => JSON.parse(result.body ?? '{}');

  test('each photo is its image, its grade, and what its owner chose to show', async () => {
    const { handler } = handlerFor([airport()], { 'xyz-east-fence': [best, plain] });
    const result = await handler(page('xyz-east-fence'));
    assert.equal(result.statusCode, 200);
    assert.deepEqual(bodyOf(result), {
      photos: [
        {
          id: 'post-best',
          imageURL: 'https://images.example.test/post-best?signed',
          score: 91,
          aircraftType: 'Boeing 737-800',
          airline: 'Southwest',
        },
        { id: 'post-plain', imageURL: 'https://images.example.test/post-plain?signed', score: 64 },
      ],
      imageLinkExpiresInSeconds: 900,
    });
  });

  test('the answer names no owner and no photo id', async () => {
    const { handler } = handlerFor([airport()], { 'xyz-east-fence': [best, plain] });
    const body = (await handler(page('xyz-east-fence'))).body ?? '';
    for (const hidden of ['owner-1', 'owner-2', 'photo-1', 'photo-2', 'ownerID', 'photoID']) {
      assert.ok(!body.includes(hidden), hidden);
    }
  });

  test('a page holds no more photos than the stage allows', async () => {
    const { handler, asked } = handlerFor([airport()], { 'xyz-east-fence': [best, plain, third] });
    const photos = bodyOf(await handler(page('xyz-east-fence'))).photos;
    assert.equal(photos.length, 2);
    assert.deepEqual(asked, [{ spotID: 'xyz-east-fence', limit: 2 }]);
  });

  test('a spot with no graded photos has an empty page', async () => {
    const { handler } = handlerFor([airport()]);
    assert.deepEqual(bodyOf(await handler(page('xyz-east-fence'))).photos, []);
  });

  test('a spot that is not listed is not found, and nothing is read for it', async () => {
    const { handler, asked } = handlerFor([airport()], { 'made-up': [best] });
    const result = await handler(page('made-up'));
    assert.equal(result.statusCode, 404);
    assert.equal(bodyOf(result).code, 'unknownSpot');
    assert.deepEqual(asked, []);
  });

  test('a caller who is not signed in is turned away', async () => {
    const { handler } = handlerFor([airport()], { 'xyz-east-fence': [best] });
    const result = await handler(apiEvent({ routeKey: 'GET /spots/{spotID}/photos', spotID: 'xyz-east-fence', claims: null }));
    assert.equal(result.statusCode, 401);
  });
});

describe('reading a spot’s photos from the table', () => {
  const item = {
    pk: 'USER#owner-1',
    sk: 'POST#photo-1',
    photoID: 'photo-1',
    postID: 'post-best',
    spotKey: 'SPOT#xyz-east-fence',
    spotID: 'xyz-east-fence',
    finalScore: 91,
    aircraftType: 'Boeing 737-800',
    airline: 'Southwest',
  };

  test('the index is read for one spot, best first, up to the limit', async () => {
    const dynamo = fakeClient({ QueryCommand: [{ Items: [item] }] });
    const store = makeAwsSpotPhotoStore({
      dynamo,
      s3: {} as never,
      tableName: 'records',
      bucketName: 'images',
      imageLinkSeconds: 900,
    });
    const photos = await store.photosAt('xyz-east-fence', 30);
    assert.deepEqual(dynamo.sent, [
      {
        name: 'QueryCommand',
        input: {
          TableName: 'records',
          IndexName: 'Spot',
          KeyConditionExpression: '#spot = :spot',
          ExpressionAttributeNames: { '#spot': 'spotKey' },
          ExpressionAttributeValues: { ':spot': 'SPOT#xyz-east-fence' },
          ScanIndexForward: false,
          Limit: 30,
        },
      },
    ]);
    assert.deepEqual(photos, [
      {
        postID: 'post-best',
        ownerID: 'owner-1',
        photoID: 'photo-1',
        score: 91,
        aircraftType: 'Boeing 737-800',
        airline: 'Southwest',
      },
    ]);
  });

  test('a record that is not a graded post is left out', () => {
    assert.equal(spotPhotoOf({ ...item, finalScore: undefined }), undefined);
    assert.equal(spotPhotoOf({ ...item, pk: 'OTHER#1' }), undefined);
    assert.equal(spotPhotoOf({ ...item, postID: 7 }), undefined);
    assert.deepEqual(spotPhotoOf({ ...item, aircraftType: undefined, airline: 3 }), {
      postID: 'post-best',
      ownerID: 'owner-1',
      photoID: 'photo-1',
      score: 91,
    });
  });
});
