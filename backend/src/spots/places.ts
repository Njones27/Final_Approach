import { areaKey } from '../shared/keys.ts';

/** A position on the ground, in degrees. */
export interface Point {
  readonly latitude: number;
  readonly longitude: number;
}

/**
 * The two grids that shown photos are sorted into.
 *
 * A place is one small cell. A photo shown away from the listed spots is
 * kept by its cell and never by where it was taken, so nobody can read an
 * exact position back. An area is one large tile, which is how the map
 * finds every shown photo around a point.
 *
 * Both are whole numbers of cells in one degree, so a cell's edges are
 * exact. Neither may change once it ships, because photos name their
 * place and their area by it.
 */
export interface PlaceGrid {
  /** Cells in one degree. 1,000 makes a cell about 110 meters tall. */
  readonly placeCellsPerDegree: number;
  /** Tiles in one degree. 2 makes a tile about 55 kilometers tall. */
  readonly areaTilesPerDegree: number;
}

/** A position that is on the map, read from something a caller sent. */
export function pointIn(latitude: unknown, longitude: unknown): Point | undefined {
  if (typeof latitude !== 'number' || typeof longitude !== 'number') return undefined;
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) return undefined;
  if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) return undefined;
  return { latitude, longitude };
}

/** Brings a count of cells east of Greenwich back inside one turn of the globe. */
function wrapped(index: number, perDegree: number): number {
  const turn = 360 * perDegree;
  const half = turn / 2;
  return ((((index + half) % turn) + turn) % turn) - half;
}

/** Zero has no sign in an id, so the two zeros are one. */
const plain = (index: number): number => (index === 0 ? 0 : index);

/**
 * The id of the cell a position falls in, such as `n33640w84428`. The id
 * holds the cell and nothing finer, and it is safe in a path.
 */
export function placeIDAt(point: Point, grid: PlaceGrid): string {
  const per = grid.placeCellsPerDegree;
  const latitude = plain(Math.round(point.latitude * per));
  const longitude = plain(wrapped(Math.round(point.longitude * per), per));
  return `${latitude < 0 ? 's' : 'n'}${Math.abs(latitude)}${longitude < 0 ? 'w' : 'e'}${Math.abs(longitude)}`;
}

/** The middle of a place's cell, or nothing for an id that names no cell. */
export function centerOfPlace(placeID: unknown, grid: PlaceGrid): Point | undefined {
  if (typeof placeID !== 'string') return undefined;
  const match = /^([ns])(0|[1-9]\d{0,7})([ew])(0|[1-9]\d{0,7})$/.exec(placeID);
  if (!match) return undefined;
  const per = grid.placeCellsPerDegree;
  const latitude = (match[1] === 's' ? -1 : 1) * Number(match[2]);
  const longitude = (match[3] === 'w' ? -1 : 1) * Number(match[4]);
  const center = pointIn(plain(latitude) / per, plain(longitude) / per);
  // One cell has one id, so a second spelling of it is turned away.
  return center && placeIDAt(center, grid) === placeID ? center : undefined;
}

function areaKeyOf(latitudeIndex: number, longitudeIndex: number, grid: PlaceGrid): string {
  return areaKey(plain(latitudeIndex), plain(wrapped(longitudeIndex, grid.areaTilesPerDegree)));
}

/** The key of the tile a position falls in. */
export function areaKeyAt(point: Point, grid: PlaceGrid): string {
  const per = grid.areaTilesPerDegree;
  return areaKeyOf(Math.floor(point.latitude * per), Math.floor(point.longitude * per), grid);
}

/**
 * The keys of the four tiles nearest a position. Together they reach at
 * least half a tile from it in every direction, so a position at the edge
 * of its own tile still sees what is just across the line.
 */
export function areaKeysAround(point: Point, grid: PlaceGrid): string[] {
  const per = grid.areaTilesPerDegree;
  const south = Math.floor(point.latitude * per - 0.5);
  const west = Math.floor(point.longitude * per - 0.5);
  const keys = [
    areaKeyOf(south, west, grid),
    areaKeyOf(south, west + 1, grid),
    areaKeyOf(south + 1, west, grid),
    areaKeyOf(south + 1, west + 1, grid),
  ];
  return [...new Set(keys)];
}
