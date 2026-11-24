import { callerOf, json, notFound, notSignedIn, problem, type ApiEvent, type ApiResult } from '../shared/http.ts';
import { listedSpotIDs, type Airport } from './catalog.ts';
import type { SpotPhotoStore } from './store.ts';

export interface SpotsHandlerSettings {
  /** The spots to serve, grouped by airport. */
  readonly airports: readonly Airport[];
  readonly store: SpotPhotoStore;
  /** How many photos one spot's page holds. */
  readonly photosPerSpot: number;
  readonly imageLinkSeconds: number;
}

/**
 * Serves the list of spots, and the graded photos shown at one spot.
 *
 * Every answer is built from named fields, so a field added to a record
 * reaches the app only when it is added here too. A photo is sent as its
 * image, its grade, and the aircraft type and airline its owner chose to
 * show. No name, no registration, no position, and no id of the owner or
 * of the photo is sent.
 */
export function makeSpotsHandler(settings: SpotsHandlerSettings) {
  const spotIDs = listedSpotIDs(settings.airports);
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
    })),
  }));

  async function photos(spotID: string | undefined): Promise<ApiResult> {
    if (spotID === undefined || !spotIDs.has(spotID)) {
      return problem(404, 'This spot is not listed.', 'unknownSpot');
    }
    const shown = await settings.store.photosAt(spotID, settings.photosPerSpot);
    return json(200, {
      photos: await Promise.all(
        shown.map(async (photo) => ({
          id: photo.postID,
          imageURL: await settings.store.imageLink(photo),
          score: photo.score,
          ...(photo.aircraftType === undefined ? {} : { aircraftType: photo.aircraftType }),
          ...(photo.airline === undefined ? {} : { airline: photo.airline }),
        })),
      ),
      imageLinkExpiresInSeconds: settings.imageLinkSeconds,
    });
  }

  return async function handler(event: ApiEvent): Promise<ApiResult> {
    if (!callerOf(event)) return notSignedIn();
    if (event.routeKey === 'GET /spots') return json(200, { airports });
    if (event.routeKey === 'GET /spots/{spotID}/photos') return photos(event.pathParameters?.['spotID']);
    return notFound();
  };
}
