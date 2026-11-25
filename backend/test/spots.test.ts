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
import { makeAwsSpotPhotoStore, placedPhotoOf, spotPhotoOf } from '../src/spots/awsStore.ts';
import { makeSpotsHandler } from '../src/spots/handler.ts';
import type { PlacedPhoto, SpotPhoto, SpotPhotoStore } from '../src/spots/store.ts';
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

  test('a view bearing is a compass direction, and may be left out', () => {
    assert.deepEqual(problemsIn([airport({ spots: [spot({ viewBearing: 0 })] })]), []);
    assert.deepEqual(problemsIn([airport({ spots: [spot({ viewBearing: 359.5 })] })]), []);
    for (const viewBearing of [-1, 360, Number.NaN]) {
      assert.deepEqual(problemsIn([airport({ spots: [spot({ viewBearing })] })]), [
        'Spot xyz-east-fence has a view bearing that is not from 0 up to 360.',
      ]);
    }
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

/**
 * A store of shown photos kept in memory, which remembers what was asked.
 * `photos` is keyed the way the `Spot` index is, and `areas` the way the
 * `Area` index is.
 */
function memoryPhotos(photos: Record<string, SpotPhoto[]> = {}, areas: Record<string, PlacedPhoto[]> = {}) {
  const asked: { shownKey: string; limit: number }[] = [];
  const askedAreas: { areaKeys: readonly string[]; limit: number }[] = [];
  const store: SpotPhotoStore = {
    async photosAt(shownKey, limit) {
      asked.push({ shownKey, limit });
      return (photos[shownKey] ?? []).slice(0, limit);
    },
    async photosIn(areaKeys, limit) {
      askedAreas.push({ areaKeys, limit });
      return areaKeys.flatMap((key) => (areas[key] ?? []).slice(0, limit));
    },
    async imageLink(photo) {
      return `https://images.example.test/${photo.postID}?signed`;
    },
  };
  return { store, asked, askedAreas };
}

const handlerFor = (
  airports: Airport[],
  photos: Record<string, SpotPhoto[]> = {},
  areas: Record<string, PlacedPhoto[]> = {},
) => {
  const memory = memoryPhotos(photos, areas);
  const handler = makeSpotsHandler({
    airports,
    store: memory.store,
    photosPerSpot: 2,
    imageLinkSeconds: 900,
    grid: { placeCellsPerDegree: 1000, areaTilesPerDegree: 2 },
    areaReadLimit: 5,
    placesPerAnswer: 2,
  });
  return { handler, asked: memory.asked, askedAreas: memory.askedAreas };
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

  test('a spot that says which way it looks is sent with its view bearing', async () => {
    const looking = airport({ spots: [spot({ viewBearing: 350 })] });
    const result = await handlerFor([looking]).handler(apiEvent({ routeKey: 'GET /spots' }));
    assert.equal(JSON.parse(result.body ?? '').airports[0].spots[0].viewBearing, 350);
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
    const { handler } = handlerFor([airport()], { 'SPOT#xyz-east-fence': [best, plain] });
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
    const { handler } = handlerFor([airport()], { 'SPOT#xyz-east-fence': [best, plain] });
    const body = (await handler(page('xyz-east-fence'))).body ?? '';
    for (const hidden of ['owner-1', 'owner-2', 'photo-1', 'photo-2', 'ownerID', 'photoID']) {
      assert.ok(!body.includes(hidden), hidden);
    }
  });

  test('a page holds no more photos than the stage allows', async () => {
    const { handler, asked } = handlerFor([airport()], { 'SPOT#xyz-east-fence': [best, plain, third] });
    const photos = bodyOf(await handler(page('xyz-east-fence'))).photos;
    assert.equal(photos.length, 2);
    assert.deepEqual(asked, [{ shownKey: 'SPOT#xyz-east-fence', limit: 2 }]);
  });

  test('the camera settings an owner chose to show come with the photo', async () => {
    const withCamera = { ...plain, camera: { focalLength: 400, aperture: 8, exposureTime: 0.001, iso: 200 } };
    const { handler } = handlerFor([airport()], { 'SPOT#xyz-east-fence': [withCamera] });
    assert.deepEqual(bodyOf(await handler(page('xyz-east-fence'))).photos, [
      {
        id: 'post-plain',
        imageURL: 'https://images.example.test/post-plain?signed',
        score: 64,
        camera: { focalLength: 400, aperture: 8, exposureTime: 0.001, iso: 200 },
      },
    ]);
  });

  test('a spot with no graded photos has an empty page', async () => {
    const { handler } = handlerFor([airport()]);
    assert.deepEqual(bodyOf(await handler(page('xyz-east-fence'))).photos, []);
  });

  test('a spot that is not listed is not found, and nothing is read for it', async () => {
    const { handler, asked } = handlerFor([airport()], { 'SPOT#made-up': [best] });
    const result = await handler(page('made-up'));
    assert.equal(result.statusCode, 404);
    assert.equal(bodyOf(result).code, 'unknownSpot');
    assert.deepEqual(asked, []);
  });

  test('a caller who is not signed in is turned away', async () => {
    const { handler } = handlerFor([airport()], { 'SPOT#xyz-east-fence': [best] });
    const result = await handler(apiEvent({ routeKey: 'GET /spots/{spotID}/photos', spotID: 'xyz-east-fence', claims: null }));
    assert.equal(result.statusCode, 401);
  });
});

describe('the photos shown around a point of the map', () => {
  const photo = (postID: string, score: number, where: PlacedPhoto['where'], more: Partial<SpotPhoto> = {}): PlacedPhoto => ({
    postID,
    ownerID: `owner-of-${postID}`,
    photoID: `photo-of-${postID}`,
    score,
    where,
    ...more,
  });
  const atSpot = { spotID: 'xyz-east-fence' };
  const fence = { placeID: 'n10200e20300' };
  const road = { placeID: 'n10210e20310' };
  const field = { placeID: 'n9900e19800' };
  const around = (query: Record<string, string> | undefined, claims?: null) =>
    apiEvent({ routeKey: 'GET /places', ...(query ? { query } : {}), ...(claims === null ? { claims } : {}) });
  const here = { latitude: '10.2', longitude: '20.2' };
  const bodyOf = (result: { body?: string | undefined }) => JSON.parse(result.body ?? '{}');
  const link = (postID: string) => `https://images.example.test/${postID}?signed`;

  test('each spot and each place comes with its count and its top voted photo', async () => {
    const { handler } = handlerFor([airport()], {}, {
      'AREA#20_40': [
        photo('a', 91, atSpot, { aircraftType: 'Boeing 737-800', airline: 'Southwest' }),
        photo('b', 88, fence, { camera: { focalLength: 400 } }),
        photo('c', 64, atSpot),
        photo('d', 60, fence),
        photo('e', 40, fence),
      ],
      'AREA#19_39': [photo('f', 70, field)],
    });
    const result = await handler(around(here));
    assert.equal(result.statusCode, 200);
    assert.deepEqual(bodyOf(result), {
      spots: [
        {
          spotID: 'xyz-east-fence',
          photoCount: 2,
          bestPhoto: { id: 'a', imageURL: link('a'), score: 91, aircraftType: 'Boeing 737-800', airline: 'Southwest' },
        },
      ],
      places: [
        {
          id: 'n10200e20300',
          latitude: 10.2,
          longitude: 20.3,
          photoCount: 3,
          bestPhoto: { id: 'b', imageURL: link('b'), score: 88, camera: { focalLength: 400 } },
        },
        {
          id: 'n9900e19800',
          latitude: 9.9,
          longitude: 19.8,
          photoCount: 1,
          bestPhoto: { id: 'f', imageURL: link('f'), score: 70 },
        },
      ],
      imageLinkExpiresInSeconds: 900,
    });
  });

  test('the four tiles nearest the point are read, each up to the stage’s limit', async () => {
    const { handler, askedAreas } = handlerFor([airport()]);
    await handler(around(here));
    assert.deepEqual(askedAreas, [
      { areaKeys: ['AREA#19_39', 'AREA#19_40', 'AREA#20_39', 'AREA#20_40'], limit: 5 },
    ]);
  });

  test('the best photo of a place is the one graded highest, wherever it was read from', async () => {
    const { handler } = handlerFor([airport()], {}, {
      'AREA#19_39': [photo('low', 55, fence)],
      'AREA#20_40': [photo('high', 93, fence)],
    });
    const place = bodyOf(await handler(around(here))).places[0];
    assert.equal(place.bestPhoto.id, 'high');
    assert.equal(place.photoCount, 2);
  });

  test('photos with the same grade keep one order', async () => {
    const tied = { 'AREA#20_40': [photo('m', 80, fence), photo('k', 80, road)] };
    const places = bodyOf(await handlerFor([airport()], {}, tied).handler(around(here))).places;
    assert.deepEqual(places.map((place: { id: string }) => place.id), ['n10210e20310', 'n10200e20300']);
  });

  test('an answer holds no more places than the stage allows, best first', async () => {
    const { handler } = handlerFor([airport()], {}, {
      'AREA#20_40': [photo('a', 90, fence), photo('b', 80, road), photo('c', 70, field)],
    });
    const places = bodyOf(await handler(around(here))).places;
    assert.deepEqual(places.map((place: { id: string }) => place.id), ['n10200e20300', 'n10210e20310']);
  });

  test('a photo at a spot that is no longer listed is left out', async () => {
    const { handler } = handlerFor([airport()], {}, { 'AREA#20_40': [photo('a', 90, { spotID: 'delisted' })] });
    const body = bodyOf(await handler(around(here)));
    assert.deepEqual(body.spots, []);
    assert.deepEqual(body.places, []);
  });

  test('the answer names no owner and no photo id', async () => {
    const { handler } = handlerFor([airport()], {}, { 'AREA#20_40': [photo('a', 90, atSpot), photo('b', 80, fence)] });
    const body = (await handler(around(here))).body ?? '';
    for (const hidden of ['owner-of', 'photo-of', 'ownerID', 'photoID']) {
      assert.ok(!body.includes(hidden), hidden);
    }
  });

  test('nothing shown around the point is an empty answer and not a fault', async () => {
    const result = await handlerFor([]).handler(around(here));
    assert.equal(result.statusCode, 200);
    assert.deepEqual(bodyOf(result), { spots: [], places: [], imageLinkExpiresInSeconds: 900 });
  });

  test('a point that is not on the map is refused, and nothing is read', async () => {
    const { handler, askedAreas } = handlerFor([airport()]);
    const bad: (Record<string, string> | undefined)[] = [
      undefined,
      { latitude: '10.2' },
      { latitude: 'north', longitude: '20.2' },
      { latitude: '91', longitude: '20.2' },
      { latitude: '10.2', longitude: '181' },
      { latitude: '1e1', longitude: '20.2' },
      { latitude: '', longitude: '' },
    ];
    for (const query of bad) {
      assert.equal((await handler(around(query))).statusCode, 400, JSON.stringify(query));
    }
    assert.deepEqual(askedAreas, []);
  });

  test('a caller who is not signed in is turned away', async () => {
    const { handler } = handlerFor([airport()]);
    assert.equal((await handler(around(here, null))).statusCode, 401);
  });
});

describe('the photos on a place’s page', () => {
  const shown: SpotPhoto = {
    postID: 'post-1',
    ownerID: 'owner-1',
    photoID: 'photo-1',
    score: 77,
    aircraftType: 'Embraer E175',
    camera: { focalLength: 223, exposureTime: 0.025 },
  };
  const page = (placeID: string) => apiEvent({ routeKey: 'GET /places/{placeID}/photos', placeID });
  const bodyOf = (result: { body?: string | undefined }) => JSON.parse(result.body ?? '{}');

  test('a place’s photos are read under its own key and sent as a spot’s are', async () => {
    const { handler, asked } = handlerFor([], { 'PLACE#n33640w84428': [shown] });
    const result = await handler(page('n33640w84428'));
    assert.equal(result.statusCode, 200);
    assert.deepEqual(bodyOf(result), {
      photos: [
        {
          id: 'post-1',
          imageURL: 'https://images.example.test/post-1?signed',
          score: 77,
          aircraftType: 'Embraer E175',
          camera: { focalLength: 223, exposureTime: 0.025 },
        },
      ],
      imageLinkExpiresInSeconds: 900,
    });
    assert.deepEqual(asked, [{ shownKey: 'PLACE#n33640w84428', limit: 2 }]);
  });

  test('a cell with nothing shown in it has an empty page', async () => {
    const { handler } = handlerFor([]);
    assert.deepEqual(bodyOf(await handler(page('s1e2'))).photos, []);
  });

  test('an id that names no cell is refused, and nothing is read for it', async () => {
    const { handler, asked } = handlerFor([], { 'PLACE#n33640w84428': [shown] });
    for (const id of ['', 'N33640W84428', 'n033640w84428', 'n91000e0', 'n0e181000', 'xyz-east-fence', 'n1e1#x']) {
      assert.equal((await handler(page(id))).statusCode, 400, id);
    }
    assert.deepEqual(asked, []);
  });

  test('a caller who is not signed in is turned away', async () => {
    const { handler } = handlerFor([]);
    const result = await handler(apiEvent({ routeKey: 'GET /places/{placeID}/photos', placeID: 'n1e1', claims: null }));
    assert.equal(result.statusCode, 401);
  });
});

describe('reading shown photos from the table', () => {
  const item = {
    pk: 'USER#owner-1',
    sk: 'POST#photo-1',
    photoID: 'photo-1',
    postID: 'post-best',
    spotKey: 'SPOT#xyz-east-fence',
    areaKey: 'AREA#20_40',
    spotID: 'xyz-east-fence',
    finalScore: 91,
    aircraftType: 'Boeing 737-800',
    airline: 'Southwest',
  };
  const photo = {
    postID: 'post-best',
    ownerID: 'owner-1',
    photoID: 'photo-1',
    score: 91,
    aircraftType: 'Boeing 737-800',
    airline: 'Southwest',
  };
  const storeOn = (dynamo: ReturnType<typeof fakeClient>) =>
    makeAwsSpotPhotoStore({ dynamo, s3: {} as never, tableName: 'records', bucketName: 'images', imageLinkSeconds: 900 });

  test('the index is read for one spot, best first, up to the limit', async () => {
    const dynamo = fakeClient({ QueryCommand: [{ Items: [item] }] });
    const photos = await storeOn(dynamo).photosAt('SPOT#xyz-east-fence', 30);
    assert.deepEqual(dynamo.sent, [
      {
        name: 'QueryCommand',
        input: {
          TableName: 'records',
          IndexName: 'Spot',
          KeyConditionExpression: '#key = :key',
          ExpressionAttributeNames: { '#key': 'spotKey' },
          ExpressionAttributeValues: { ':key': 'SPOT#xyz-east-fence' },
          ScanIndexForward: false,
          Limit: 30,
        },
      },
    ]);
    assert.deepEqual(photos, [photo]);
  });

  test('each tile of the map is read from its own index, best first, up to the limit', async () => {
    const atPlace = { ...item, pk: 'USER#owner-2', postID: 'post-2', spotID: undefined, placeID: 'n10200e20300', finalScore: 70 };
    const dynamo = fakeClient({ QueryCommand: [{ Items: [item] }, { Items: [atPlace] }] });
    const photos = await storeOn(dynamo).photosIn(['AREA#20_40', 'AREA#19_40'], 200);
    assert.deepEqual(
      dynamo.sent.map((command) => command.input),
      ['AREA#20_40', 'AREA#19_40'].map((key) => ({
        TableName: 'records',
        IndexName: 'Area',
        KeyConditionExpression: '#key = :key',
        ExpressionAttributeNames: { '#key': 'areaKey' },
        ExpressionAttributeValues: { ':key': key },
        ScanIndexForward: false,
        Limit: 200,
      })),
    );
    assert.deepEqual(photos, [
      { ...photo, where: { spotID: 'xyz-east-fence' } },
      { ...photo, ownerID: 'owner-2', postID: 'post-2', score: 70, where: { placeID: 'n10200e20300' } },
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

  test('camera settings are read as numbers, and anything else is left out', () => {
    assert.deepEqual(spotPhotoOf({ ...item, focalLength: 400, aperture: '8', iso: 200 })?.camera, {
      focalLength: 400,
      iso: 200,
    });
    assert.equal(spotPhotoOf(item)?.camera, undefined);
  });

  test('a record that says nowhere it is shown is not put on the map', () => {
    assert.equal(placedPhotoOf({ ...item, spotID: undefined }), undefined);
    assert.equal(placedPhotoOf({ ...item, finalScore: undefined }), undefined);
  });
});
