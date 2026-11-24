import { callerOf, json, notFound, notSignedIn, type ApiEvent, type ApiResult } from '../shared/http.ts';
import type { Airport } from './catalog.ts';

export interface SpotsHandlerSettings {
  /** The spots to serve, grouped by airport. */
  readonly airports: readonly Airport[];
}

/**
 * Serves the list of spots.
 *
 * The answer is built from named fields, so a field added to a listing
 * reaches the app only when it is added here too. It says nothing about
 * any user or any photo.
 */
export function makeSpotsHandler(settings: SpotsHandlerSettings) {
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

  return async function handler(event: ApiEvent): Promise<ApiResult> {
    if (!callerOf(event)) return notSignedIn();
    if (event.routeKey !== 'GET /spots') return notFound();
    return json(200, { airports });
  };
}
