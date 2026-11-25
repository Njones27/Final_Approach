/**
 * How a photo was taken, as its owner chose to show it beside the photo.
 * Every part may be left out.
 */
export interface CameraSettings {
  /** In millimeters. */
  readonly focalLength?: number;
  /** The f-number. */
  readonly aperture?: number;
  /** How long the shutter was open, in seconds. */
  readonly exposureTime?: number;
  readonly iso?: number;
}

/** The parts of a camera setting, in the order they are kept and sent. */
export const cameraFields = ['focalLength', 'aperture', 'exposureTime', 'iso'] as const;

/** The smallest and largest each part may be. Anything outside is not a real setting. */
export type CameraLimits = Readonly<Record<(typeof cameraFields)[number], readonly [number, number]>>;

export const cameraLimits: CameraLimits = {
  focalLength: [1, 5000],
  aperture: [0.5, 128],
  exposureTime: [1 / 1_000_000, 3600],
  iso: [1, 10_000_000],
};

/**
 * The camera settings in something a caller sent. Nothing sent is no
 * settings, and a part that is not a number inside its limits makes the
 * whole of it unusable.
 */
export function cameraIn(value: unknown, limits: CameraLimits): CameraSettings | undefined | 'unusable' {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'object' || Array.isArray(value)) return 'unusable';
  const sent = value as Record<string, unknown>;
  const camera: Record<string, number> = {};
  for (const field of cameraFields) {
    const part = sent[field];
    if (part === undefined || part === null) continue;
    const [least, most] = limits[field];
    if (typeof part !== 'number' || !Number.isFinite(part) || part < least || part > most) return 'unusable';
    camera[field] = part;
  }
  return Object.keys(camera).length > 0 ? camera : undefined;
}

/** The camera settings kept on a record, or nothing when it holds none. */
export function cameraOf(item: Record<string, unknown>): CameraSettings | undefined {
  const camera: Record<string, number> = {};
  for (const field of cameraFields) {
    const part = item[field];
    if (typeof part === 'number') camera[field] = part;
  }
  return Object.keys(camera).length > 0 ? camera : undefined;
}
