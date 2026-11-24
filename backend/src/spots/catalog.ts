/** A place to photograph aircraft from. */
export interface Spot {
  /** Lowercase letters, digits, and hyphens. It never changes, because photos name their spot by it. */
  readonly id: string;
  readonly name: string;
  /** One or two sentences on what the spot is good for. */
  readonly summary: string;
  readonly latitude: number;
  readonly longitude: number;
  /** How to get there and where to stand, on ground the public may use. */
  readonly accessNotes: string;
  /** What the airport or the local police ask of photographers here. */
  readonly localRules: string;
  /** Which runways the spot sees, and from which side. */
  readonly runwayNotes: string;
}

/** An airport and the spots around it. */
export interface Airport {
  /** The IATA code, such as "ATL". */
  readonly code: string;
  readonly city: string;
  readonly latitude: number;
  readonly longitude: number;
  readonly spots: readonly Spot[];
}

/**
 * The spots the app shows, chosen by hand.
 *
 * A spot is added here only once someone has checked it. It must be on
 * ground the public may use, and its notes must say what the airport asks
 * of photographers. A listing never sends anyone into a restricted area.
 * A deploy of the backend changes the list, with no release of the app.
 *
 * The list is empty until the owner supplies the first real spots. The
 * spots in the app's sample data are made up and do not belong here.
 */
export const catalog: readonly Airport[] = [];

/** The id of every spot in a list. */
export function listedSpotIDs(airports: readonly Airport[]): ReadonlySet<string> {
  return new Set(airports.flatMap((airport) => airport.spots.map((spot) => spot.id)));
}

/** What a listing must keep to. */
export interface CatalogLimits {
  /** A spot farther than this from its airport is a mistake in the pin. */
  readonly maxKmFromAirport: number;
  /** The longest a name may be. */
  readonly maxNameLength: number;
  /** The longest a summary or a note may be. */
  readonly maxNoteLength: number;
}

export const catalogLimits: CatalogLimits = { maxKmFromAirport: 25, maxNameLength: 60, maxNoteLength: 600 };

export function isUsableSpotID(id: unknown): id is string {
  return typeof id === 'string' && /^[a-z0-9]+(-[a-z0-9]+)*$/.test(id) && id.length <= 60;
}

const isLatitude = (value: number) => Number.isFinite(value) && value >= -90 && value <= 90;
const isLongitude = (value: number) => Number.isFinite(value) && value >= -180 && value <= 180;

/** The distance between two points on the ground, in kilometers. */
export function kilometersBetween(
  a: { latitude: number; longitude: number },
  b: { latitude: number; longitude: number },
): number {
  const radians = (degrees: number) => (degrees * Math.PI) / 180;
  const dLat = radians(b.latitude - a.latitude);
  const dLon = radians(b.longitude - a.longitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) * Math.sin(dLon / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Everything wrong with a list of spots, in words. An empty answer means
 * the list can be served. The tests run this on the list above, so a bad
 * listing stops a pull request and never reaches the app.
 */
export function problemsIn(airports: readonly Airport[], limits: CatalogLimits = catalogLimits): string[] {
  const problems: string[] = [];
  const codes = new Set<string>();
  const spotIDs = new Set<string>();
  const text = (owner: string, field: string, value: string, longest: number, mayBeEmpty: boolean) => {
    if (typeof value !== 'string' || (!mayBeEmpty && value.trim() === '')) {
      problems.push(`${owner} has no ${field}.`);
    } else if (value.length > longest) {
      problems.push(`${owner} has a ${field} longer than ${longest} characters.`);
    } else if (value !== value.trim()) {
      problems.push(`${owner} has a ${field} with space at an end.`);
    }
  };

  for (const airport of airports) {
    const owner = `Airport ${airport.code}`;
    if (!/^[A-Z]{3}$/.test(airport.code)) problems.push(`${owner} does not have a three letter code.`);
    if (codes.has(airport.code)) problems.push(`${owner} is listed twice.`);
    codes.add(airport.code);
    text(owner, 'city', airport.city, limits.maxNameLength, false);
    const airportPinIsUsable = isLatitude(airport.latitude) && isLongitude(airport.longitude);
    if (!airportPinIsUsable) problems.push(`${owner} has a pin that is not on the map.`);
    if (airport.spots.length === 0) problems.push(`${owner} has no spots.`);

    for (const spot of airport.spots) {
      const name = `Spot ${spot.id}`;
      if (!isUsableSpotID(spot.id)) problems.push(`${name} has an id that is not usable.`);
      if (spotIDs.has(spot.id)) problems.push(`${name} is listed twice.`);
      spotIDs.add(spot.id);
      text(name, 'name', spot.name, limits.maxNameLength, false);
      text(name, 'summary', spot.summary, limits.maxNoteLength, false);
      text(name, 'access note', spot.accessNotes, limits.maxNoteLength, false);
      // A spot must say what is asked of photographers there, even if it is nothing.
      text(name, 'local rule', spot.localRules, limits.maxNoteLength, false);
      text(name, 'runway note', spot.runwayNotes, limits.maxNoteLength, true);
      if (!isLatitude(spot.latitude) || !isLongitude(spot.longitude)) {
        problems.push(`${name} has a pin that is not on the map.`);
      } else if (airportPinIsUsable && kilometersBetween(airport, spot) > limits.maxKmFromAirport) {
        problems.push(`${name} is more than ${limits.maxKmFromAirport} km from its airport.`);
      }
    }
  }
  return problems;
}
