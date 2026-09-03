import {
  boundingBoxFor,
  haversineDistanceKm,
  isValidCoordinate,
  roundDistanceKm,
} from './haversine';

// Real coordinates, so a regression shows up as a distance a human can sanity
// check against a map rather than as an abstract float.
const CHENNAI = { latitude: 13.0827, longitude: 80.2707 };
const BENGALURU = { latitude: 12.9716, longitude: 77.5946 };
const MADURAI = { latitude: 9.9252, longitude: 78.1198 };

describe('haversineDistanceKm', () => {
  it('is zero for the same point', () => {
    expect(haversineDistanceKm(CHENNAI, CHENNAI)).toBe(0);
  });

  it('measures one degree of latitude as ~111.19km', () => {
    // 2*pi*R/360 for the mean Earth radius. Latitude degrees are constant
    // everywhere, so this is the one distance with an exact expected value.
    const distance = haversineDistanceKm(
      { latitude: 0, longitude: 0 },
      { latitude: 1, longitude: 0 },
    );
    expect(distance).toBeCloseTo(111.195, 2);
  });

  it('matches the real Chennai-Bengaluru great-circle distance', () => {
    expect(haversineDistanceKm(CHENNAI, BENGALURU)).toBeCloseTo(290, 0);
  });

  it('matches the real Chennai-Madurai great-circle distance', () => {
    expect(haversineDistanceKm(CHENNAI, MADURAI)).toBeCloseTo(422, 0);
  });

  it('is symmetric', () => {
    expect(haversineDistanceKm(CHENNAI, MADURAI)).toBeCloseTo(
      haversineDistanceKm(MADURAI, CHENNAI),
      9,
    );
  });

  it('stays precise at very short separations', () => {
    // ~111m north. The spherical law of cosines loses most of its significant
    // digits here; Haversine is chosen precisely so this stays right, because
    // "0.1 km away" is a distance this feature actually displays.
    const distance = haversineDistanceKm(CHENNAI, {
      latitude: CHENNAI.latitude + 0.001,
      longitude: CHENNAI.longitude,
    });
    expect(distance).toBeCloseTo(0.111, 3);
  });

  it('does not return NaN for antipodal points', () => {
    // sqrt(h) can exceed 1 by a rounding epsilon at exactly 180 degrees, which
    // would make asin return NaN without the clamp in the implementation.
    const distance = haversineDistanceKm(
      { latitude: 0, longitude: 0 },
      { latitude: 0, longitude: 180 },
    );
    expect(Number.isNaN(distance)).toBe(false);
    expect(distance).toBeCloseTo(20015, 0);
  });
});

describe('boundingBoxFor', () => {
  it('spans the right number of latitude degrees', () => {
    const box = boundingBoxFor(CHENNAI, 100);
    expect(box.maxLatitude - box.minLatitude).toBeCloseTo(
      (2 * 100) / 110.574,
      6,
    );
  });

  it('widens the longitude span as latitude increases', () => {
    // Meridians converge toward the poles, so the same radius needs MORE
    // degrees of longitude further north. Getting this backwards would build a
    // box too narrow and silently drop people inside the radius.
    const atChennai = boundingBoxFor(CHENNAI, 100);
    const atDelhi = boundingBoxFor(
      { latitude: 28.6139, longitude: 77.209 },
      100,
    );

    const chennaiSpan = atChennai.maxLongitude - atChennai.minLongitude;
    const delhiSpan = atDelhi.maxLongitude - atDelhi.minLongitude;
    expect(delhiSpan).toBeGreaterThan(chennaiSpan);
  });

  it('fully contains every point on the radius circle', () => {
    // The whole correctness claim of the prefilter: the box must be a superset
    // of the circle. Walks the circle in 15-degree steps and asserts each point
    // is inside the box.
    const radiusKm = 100;
    const box = boundingBoxFor(CHENNAI, radiusKm);
    const latPerKm = 1 / 110.574;
    const lonPerKm =
      1 / (111.32 * Math.cos((CHENNAI.latitude * Math.PI) / 180));

    for (let bearing = 0; bearing < 360; bearing += 15) {
      const radians = (bearing * Math.PI) / 180;
      const point = {
        latitude: CHENNAI.latitude + radiusKm * Math.cos(radians) * latPerKm,
        longitude: CHENNAI.longitude + radiusKm * Math.sin(radians) * lonPerKm,
      };
      expect(point.latitude).toBeGreaterThanOrEqual(box.minLatitude);
      expect(point.latitude).toBeLessThanOrEqual(box.maxLatitude);
      expect(point.longitude).toBeGreaterThanOrEqual(box.minLongitude);
      expect(point.longitude).toBeLessThanOrEqual(box.maxLongitude);
    }
  });

  it('clamps to valid ranges near the poles', () => {
    const box = boundingBoxFor({ latitude: 89.9, longitude: 0 }, 100);
    expect(box.maxLatitude).toBeLessThanOrEqual(90);
    expect(box.minLongitude).toBeGreaterThanOrEqual(-180);
    expect(box.maxLongitude).toBeLessThanOrEqual(180);
  });
});

describe('isValidCoordinate', () => {
  it.each([
    [13.0827, 80.2707],
    [0, 0],
    [-90, -180],
    [90, 180],
  ])('accepts (%p, %p)', (lat, lon) => {
    expect(isValidCoordinate(lat, lon)).toBe(true);
  });

  it.each([
    [91, 0],
    [-91, 0],
    [0, 181],
    [0, -181],
    [Number.NaN, 0],
    [Number.POSITIVE_INFINITY, 0],
    [null, 0],
    ['13.08', '80.27'],
    [undefined, undefined],
  ])('rejects (%p, %p)', (lat, lon) => {
    expect(isValidCoordinate(lat, lon)).toBe(false);
  });
});

describe('roundDistanceKm', () => {
  it.each([
    [2.34, 2.3],
    [2.35, 2.4],
    [0.04, 0],
    [45.0, 45],
    [99.99, 100],
  ])('rounds %p to %p', (input, expected) => {
    expect(roundDistanceKm(input)).toBe(expected);
  });
});
