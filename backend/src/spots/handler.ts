import { callerOf, json, notFound, notSignedIn, problem, type ApiEvent, type ApiResult } from '../shared/http.ts';
import { placeKey, spotKey } from '../shared/keys.ts';
import { listedSpots, type Airport } from './catalog.ts';
import { areaKeysAround, centerOfPlace, pointIn, type PlaceGrid } from './places.ts';
import type { PlacedPhoto, SpotPhoto, SpotPhotoStore } from './store.ts';

export interface SpotsHandlerSettings {
  /** The spots to serve, grouped by airport. */
  readonly airports: readonly Airport[];
  readonly store: SpotPhotoStore;
  /** How many photos one spot's or one place's page holds. */
  readonly photosPerSpot: number;
  readonly imageLinkSeconds: number;
  /** The cells and tiles that shown photos are sorted into. */
  readonly grid: PlaceGrid;
  /** How many shown photos one request reads from each tile of the map. */
  readonly areaReadLimit: number;
  /** How many places one answer holds, best first. */
  readonly placesPerAnswer: number;
}

/** The photos shown at one spot or place, with the best one first. */
interface Group {
  readonly best: PlacedPhoto;
  count: number;
}

/**
 * Serves the list of spots, the photos shown around a point of the map,
 * and the graded photos shown at one spot or place.
 *
 * Every answer is built from named fields, so a field added to a record
 * reaches the app only when it is added here too. A photo is sent as its
 * image, its grade, and the aircraft type, airline, and camera settings
 * its owner chose to show. No name, no registration, and no id of the
 * owner or of the photo is sent. The only position sent is the middle of
 * a place's cell.
 */
export function makeSpotsHandler(settings: SpotsHandlerSettings) {
  const { store, grid } = settings;
  const spots = listedSpots(settings.airports);
  const airports = settings.airports.map((airport) => ({
    code: airport.code,
    city: airport.city,
    latitude: airport.latitude,
    longitude: airport.longitude,
    spots: airport.spots.map((spot) => ({
      id: spot.id,
      name: spot.name,
      summary: spot.summary,
      latitude: spot.latitude,
      longitude: spot.longitude,
      accessNotes: spot.accessNotes,
      localRules: spot.localRules,
      runwayNotes: spot.runwayNotes,
      ...(spot.viewBearing === undefined ? {} : { viewBearing: spot.viewBearing }),
    })),
  }));

  async function sent(photo: SpotPhoto) {
    return {
      id: photo.postID,
      imageURL: await store.imageLink(photo),
      score: photo.score,
      ...(photo.aircraftType === undefined ? {} : { aircraftType: photo.aircraftType }),
      ...(photo.airline === undefined ? {} : { airline: photo.airline }),
      ...(photo.camera === undefined ? {} : { camera: photo.camera }),
    };
  }

  async function page(shownKey: string): Promise<ApiResult> {
    const shown = await store.photosAt(shownKey, settings.photosPerSpot);
    return json(200, {
      photos: await Promise.all(shown.map(sent)),
      imageLinkExpiresInSeconds: settings.imageLinkSeconds,
    });
  }

  function spotPage(spotID: string | undefined): Promise<ApiResult> | ApiResult {
    if (spotID === undefined || !spots.has(spotID)) {
      return problem(404, 'This spot is not listed.', 'unknownSpot');
    }
    return page(spotKey(spotID));
  }

  function placePage(placeID: string | undefined): Promise<ApiResult> | ApiResult {
    // A place is any cell of the map, so one with no photos has an empty
    // page. Only an id that names no cell is turned away.
    if (placeID === undefined || !centerOfPlace(placeID, grid)) {
      return problem(400, 'The place id is not usable.');
    }
    return page(placeKey(placeID));
  }

  /**
   * What is shown around a point of the map. Each listed spot and each
   * place comes with how many photos are shown there and the best one,
   * which is the one the votes graded highest.
   */
  async function around(event: ApiEvent): Promise<ApiResult> {
    const query = event.queryStringParameters ?? {};
    const point = pointIn(numberIn(query['latitude']), numberIn(query['longitude']));
    if (!point) return problem(400, 'Say where to look with a latitude and a longitude on the map.');

    const shown = [...(await store.photosIn(areaKeysAround(point, grid), settings.areaReadLimit))];
    // The best photo comes first, so the first one seen for a spot or a
    // place is its best. Equal grades keep one order, by the post's id.
    shown.sort((a, b) => b.score - a.score || (a.postID < b.postID ? -1 : a.postID > b.postID ? 1 : 0));
    const atSpots = new Map<string, Group>();
    const atPlaces = new Map<string, Group>();
    for (const photo of shown) {
      const { spotID, placeID } = photo.where;
      // A spot that is no longer listed has no pin to hang its photos on.
      if (spotID !== undefined && !spots.has(spotID)) continue;
      const groups = spotID !== undefined ? atSpots : atPlaces;
      const id = spotID ?? placeID;
      if (id === undefined) continue;
      const group = groups.get(id);
      if (group) group.count += 1;
      else groups.set(id, { best: photo, count: 1 });
    }

    const places = [...atPlaces].flatMap(([id, group]) => {
      const center = centerOfPlace(id, grid);
      return center ? [{ id, center, group }] : [];
    });
    return json(200, {
      spots: await Promise.all(
        [...atSpots].map(async ([spotID, group]) => ({
          spotID,
          photoCount: group.count,
          bestPhoto: await sent(group.best),
        })),
      ),
      places: await Promise.all(
        places.slice(0, settings.placesPerAnswer).map(async ({ id, center, group }) => ({
          id,
          latitude: center.latitude,
          longitude: center.longitude,
          photoCount: group.count,
          bestPhoto: await sent(group.best),
        })),
      ),
      imageLinkExpiresInSeconds: settings.imageLinkSeconds,
    });
  }

  return async function handler(event: ApiEvent): Promise<ApiResult> {
    if (!callerOf(event)) return notSignedIn();
    if (event.routeKey === 'GET /spots') return json(200, { airports });
    if (event.routeKey === 'GET /spots/{spotID}/photos') return spotPage(event.pathParameters?.['spotID']);
    if (event.routeKey === 'GET /places') return around(event);
    if (event.routeKey === 'GET /places/{placeID}/photos') return placePage(event.pathParameters?.['placeID']);
    return notFound();
  };
}

/** A number written out in full in a query, or nothing. */
function numberIn(text: string | undefined): number | undefined {
  return text !== undefined && /^-?\d{1,3}(\.\d{1,10})?$/.test(text) ? Number(text) : undefined;
}
