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
import { makeSpotsHandler } from '../src/spots/handler.ts';
import { apiEvent } from './support.ts';

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

describe('the spots route', () => {
  const handler = makeSpotsHandler({ airports: [airport()] });

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
    const result = await makeSpotsHandler({ airports: [airport({ spots: [extra] })] })(
      apiEvent({ routeKey: 'GET /spots' }),
    );
    assert.ok(!(result.body ?? '').includes('curatorNote'));
  });

  test('an empty list is an answer and not a fault', async () => {
    const result = await makeSpotsHandler({ airports: [] })(apiEvent({ routeKey: 'GET /spots' }));
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
