/**
 * Great-circle distance and the bounding box that prefilters it.
 *
 * Pure functions, no Nest/Prisma imports, so the arithmetic that decides
 * "2.3 km away" is unit-testable on its own — see haversine.spec.ts.
 *
 * Why both: Haversine is exact but uncomputable by an index — applying it to
 * every row means a full scan of user_profiles. So a cheap rectangular box
 * (which `@@index([latitude, longitude])` CAN range-scan) narrows the
 * candidates first, and Haversine then trims the box's corners down to a true
 * circle. The box is a superset of the circle, never a subset, so nobody
 * inside the radius is ever missed.
 */

/**
 * Mean Earth radius (IUGG). The Earth is an oblate spheroid, so a sphere-based
 * distance carries up to ~0.5% error — about 500m over a 100km radius. That is
 * far inside the error already introduced by an "Approximate" location fix
 * (1-3km), so a spherical model is the right precision to stop at here;
 * Vincenty on an ellipsoid would be false precision at ten times the cost.
 */
const EARTH_RADIUS_KM = 6371.0088;

/** One degree of latitude, constant everywhere. */
const KM_PER_DEGREE_LATITUDE = 110.574;

/** One degree of longitude AT THE EQUATOR; shrinks by cos(latitude). */
const KM_PER_DEGREE_LONGITUDE_AT_EQUATOR = 111.32;

export interface GeoPoint {
  latitude: number;
  longitude: number;
}

export interface BoundingBox {
  minLatitude: number;
  maxLatitude: number;
  minLongitude: number;
  maxLongitude: number;
}

const toRadians = (degrees: number): number => (degrees * Math.PI) / 180;

/**
 * Great-circle distance between two points, in kilometres.
 *
 * Haversine rather than the spherical law of cosines: the latter loses
 * precision catastrophically at small separations (its `acos` argument
 * approaches 1, where float rounding dominates), and small separations are
 * exactly what this feature reports — "0.4 km away" has to be right.
 */
export function haversineDistanceKm(a: GeoPoint, b: GeoPoint): number {
  const deltaLat = toRadians(b.latitude - a.latitude);
  const deltaLon = toRadians(b.longitude - a.longitude);
  const latA = toRadians(a.latitude);
  const latB = toRadians(b.latitude);

  const h =
    Math.sin(deltaLat / 2) ** 2 +
    Math.cos(latA) * Math.cos(latB) * Math.sin(deltaLon / 2) ** 2;

  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * The smallest lat/long rectangle fully containing the circle of [radiusKm]
 * around [centre] — the prefilter the composite index can actually use.
 *
 * The longitude span divides by cos(latitude) because meridians converge
 * toward the poles: 1° of longitude is ~111km at the equator but ~96km at
 * Delhi (28.6°N). Ignoring that would build a box too NARROW in longitude and
 * silently drop people genuinely inside the radius — a wrong-results bug, not
 * a performance one.
 *
 * Two edge cases are clamped rather than handled exactly, because both are
 * unreachable for this product and a wrong clamp is safer than a wrong box:
 *   - Near the poles cos(latitude) approaches 0 and the longitude span
 *     explodes; it is clamped to the whole 360° range, which stays a valid
 *     superset (Haversine then does the real filtering).
 *   - A box spanning the ±180° antimeridian would need to be split into two
 *     ranges. Here it is clamped to [-180, 180], which is still a superset of
 *     the circle for every radius this endpoint accepts.
 */
export function boundingBoxFor(
  centre: GeoPoint,
  radiusKm: number,
): BoundingBox {
  const latDelta = radiusKm / KM_PER_DEGREE_LATITUDE;

  const cosLat = Math.cos(toRadians(centre.latitude));
  const lonDelta =
    Math.abs(cosLat) < 1e-9
      ? 180
      : radiusKm / (KM_PER_DEGREE_LONGITUDE_AT_EQUATOR * Math.abs(cosLat));

  return {
    minLatitude: Math.max(-90, centre.latitude - latDelta),
    maxLatitude: Math.min(90, centre.latitude + latDelta),
    minLongitude: Math.max(-180, centre.longitude - lonDelta),
    maxLongitude: Math.min(180, centre.longitude + lonDelta),
  };
}

/** Whether a pair of numbers is a usable coordinate — finite and in range. */
export function isValidCoordinate(
  latitude: unknown,
  longitude: unknown,
): latitude is number {
  return (
    typeof latitude === 'number' &&
    typeof longitude === 'number' &&
    Number.isFinite(latitude) &&
    Number.isFinite(longitude) &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180
  );
}

/**
 * Distance rounded to one decimal for display ("2.3 km away").
 *
 * Rounding here rather than in the client is deliberate and is a privacy
 * control, not a formatting nicety: a full-precision distance from three
 * different points trilaterates someone's home to within metres. One decimal
 * quantises that to ~100m of ambiguity. See NearbyProfileDto, which is why no
 * endpoint ever returns another member's raw coordinates.
 */
export function roundDistanceKm(distanceKm: number): number {
  return Math.round(distanceKm * 10) / 10;
}
