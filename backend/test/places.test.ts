import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { areaKeyAt, areaKeysAround, centerOfPlace, placeIDAt, pointIn, type PlaceGrid } from '../src/spots/places.ts';
import { kilometersBetween } from '../src/spots/catalog.ts';
import { stages } from '../lib/stages.ts';

const grid: PlaceGrid = { placeCellsPerDegree: 1000, areaTilesPerDegree: 2 };

describe('a position a caller sent', () => {
  test('a latitude and a longitude on the map are a point', () => {
    assert.deepEqual(pointIn(33.64, -84.43), { latitude: 33.64, longitude: -84.43 });
    assert.deepEqual(pointIn(-90, 180), { latitude: -90, longitude: 180 });
  });

  test('anything else is not', () => {
    const bad: [unknown, unknown][] = [
      [91, 0],
      [-90.1, 0],
      [0, 180.1],
      [0, -181],
      [Number.NaN, 0],
      [0, Number.POSITIVE_INFINITY],
      ['33.64', -84.43],
      [undefined, undefined],
      [null, 0],
    ];
    for (const [latitude, longitude] of bad) {
      assert.equal(pointIn(latitude, longitude), undefined, `${String(latitude)}, ${String(longitude)}`);
    }
  });
});

describe('the cell a shown photo is kept by', () => {
  test('a position is named by its cell, with a letter for each side of zero', () => {
    assert.equal(placeIDAt({ latitude: 33.64037, longitude: -84.42761 }, grid), 'n33640w84428');
    assert.equal(placeIDAt({ latitude: -33.94612, longitude: 151.17722 }, grid), 's33946e151177');
    assert.equal(placeIDAt({ latitude: 51.4703, longitude: -0.4543 }, grid), 'n51470w454');
  });

  test('every position in a cell has the same id, and the next cell has another', () => {
    const id = placeIDAt({ latitude: 33.64, longitude: -84.428 }, grid);
    assert.equal(placeIDAt({ latitude: 33.64049, longitude: -84.42751 }, grid), id);
    assert.equal(placeIDAt({ latitude: 33.63951, longitude: -84.42849 }, grid), id);
    assert.notEqual(placeIDAt({ latitude: 33.64051, longitude: -84.428 }, grid), id);
    assert.notEqual(placeIDAt({ latitude: 33.64, longitude: -84.42749 }, grid), id);
  });

  test('zero has one id on each axis', () => {
    assert.equal(placeIDAt({ latitude: 0.0001, longitude: -0.0001 }, grid), 'n0e0');
    assert.equal(placeIDAt({ latitude: -0.0001, longitude: 0.0001 }, grid), 'n0e0');
  });

  test('the two sides of the date line are one cell', () => {
    assert.equal(placeIDAt({ latitude: 0, longitude: 180 }, grid), placeIDAt({ latitude: 0, longitude: -180 }, grid));
  });

  test('an id reads back to the middle of its cell, which is all that is known of the position', () => {
    assert.deepEqual(centerOfPlace('n33640w84428', grid), { latitude: 33.64, longitude: -84.428 });
    assert.deepEqual(centerOfPlace('s33946e151177', grid), { latitude: -33.946, longitude: 151.177 });
    assert.deepEqual(centerOfPlace('n0e0', grid), { latitude: 0, longitude: 0 });
    for (const point of [
      { latitude: 33.64037, longitude: -84.42761 },
      { latitude: -77.5, longitude: 179.9996 },
      { latitude: 89.9999, longitude: -179.9999 },
    ]) {
      const id = placeIDAt(point, grid);
      const center = centerOfPlace(id, grid);
      assert.ok(center, id);
      assert.equal(placeIDAt(center, grid), id);
    }
  });

  test('an id that names no cell, or names one a second way, reads back to nothing', () => {
    const bad = ['', 'n1', 'e1n1', 'N1E1', 'n01e1', 'n1e01', 's0e0', 'n0w0', 'n90001e0', 'n0e180000', 'n1.5e2', 'n1e2 ', 'n-1e2', 7, undefined];
    for (const id of bad) assert.equal(centerOfPlace(id, grid), undefined, String(id));
  });

  test('a cell of the grid that ships is about a hundred meters across', () => {
    for (const stage of Object.values(stages)) {
      const cell = 1 / stage.placeCellsPerDegree;
      const tall = kilometersBetween({ latitude: 33, longitude: -84 }, { latitude: 33 + cell, longitude: -84 });
      const wide = kilometersBetween({ latitude: 33, longitude: -84 }, { latitude: 33, longitude: -84 + cell });
      assert.ok(tall > 0.05 && tall < 0.15, String(tall));
      assert.ok(wide > 0.05 && wide < 0.15, String(wide));
    }
  });
});

describe('the tiles the map is read by', () => {
  test('a position is filed under the tile it falls in', () => {
    assert.equal(areaKeyAt({ latitude: 33.64, longitude: -84.43 }, grid), 'AREA#67_-169');
    assert.equal(areaKeyAt({ latitude: 10.01, longitude: 20.01 }, grid), 'AREA#20_40');
    assert.equal(areaKeyAt({ latitude: -0.1, longitude: 0.1 }, grid), 'AREA#-1_0');
  });

  test('the four tiles nearest a position are read, so its own tile is always one of them', () => {
    assert.deepEqual(areaKeysAround({ latitude: 10.2, longitude: 20.2 }, grid), [
      'AREA#19_39',
      'AREA#19_40',
      'AREA#20_39',
      'AREA#20_40',
    ]);
    for (const point of [
      { latitude: 33.64, longitude: -84.43 },
      { latitude: -33.9, longitude: 151.2 },
      { latitude: 0, longitude: 0 },
      { latitude: 64.99, longitude: -179.99 },
    ]) {
      assert.ok(areaKeysAround(point, grid).includes(areaKeyAt(point, grid)), JSON.stringify(point));
    }
  });

  test('anything within a quarter of a degree is in one of the four tiles', () => {
    const center = { latitude: 33.64, longitude: -84.43 };
    const keys = areaKeysAround(center, grid);
    for (const [north, east] of [[0.249, 0.249], [-0.249, 0.249], [0.249, -0.249], [-0.249, -0.249], [0, 0.249], [-0.249, 0]] as const) {
      const near = { latitude: center.latitude + north, longitude: center.longitude + east };
      assert.ok(keys.includes(areaKeyAt(near, grid)), JSON.stringify(near));
    }
  });

  test('the tiles join up across the date line', () => {
    const west = areaKeysAround({ latitude: 0.3, longitude: 179.9 }, grid);
    assert.ok(west.includes(areaKeyAt({ latitude: 0.3, longitude: -179.9 }, grid)), west.join(' '));
  });
});
