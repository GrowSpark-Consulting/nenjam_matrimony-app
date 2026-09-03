-- Geolocation columns backing the "Near Me" proximity search.
--
-- Additive only: four NULLable columns on user_profiles plus one index. No
-- existing column, constraint, default or row is touched, so this deploys
-- against a live database without a rewrite and reverses with a plain
-- DROP INDEX + DROP COLUMN.
--
-- Coordinates are DOUBLE PRECISION rather than a PostGIS geography type.
-- PostGIS is not installed on this database, and CREATE EXTENSION requires
-- superuser rights the deploy role does not have — so depending on it would
-- make this migration fail on the very environments it needs to run on. The
-- bounding-box prefilter plus Haversine in NearbyRepository is exact at the
-- radii this feature uses (<= 100km) and needs no extension.
--
-- NULL means "this member has never shared a location", which is the common
-- case: location is opt-in behind an OS permission prompt. There is
-- deliberately no DEFAULT — 0,0 is a real coordinate in the Gulf of Guinea,
-- and defaulting to it would cluster every un-located member within metres of
-- each other and surface them all as "0.0 km away".

-- AlterTable
ALTER TABLE "user_profiles" ADD COLUMN     "latitude" DOUBLE PRECISION,
ADD COLUMN     "location_accuracy_m" INTEGER,
ADD COLUMN     "location_updated_at" TIMESTAMP(3),
ADD COLUMN     "longitude" DOUBLE PRECISION;

-- CreateIndex
-- Latitude leads: one degree of latitude is a constant ~111km, while at Indian
-- latitudes one degree of longitude is ~101km, so an equal-distance bounding
-- box spans fewer degrees north-south than east-west and the leading range
-- scan discards more rows.
CREATE INDEX "user_profiles_latitude_longitude_idx" ON "user_profiles"("latitude", "longitude");
