-- Add lat/lng to Profile so location picker can persist coordinates.
-- Also ensure Need has the same columns for feed distance filtering.
ALTER TABLE "Profile" ADD COLUMN IF NOT EXISTS "lat" DOUBLE PRECISION;
ALTER TABLE "Profile" ADD COLUMN IF NOT EXISTS "lng" DOUBLE PRECISION;

ALTER TABLE "Need" ADD COLUMN IF NOT EXISTS "lat" DOUBLE PRECISION;
ALTER TABLE "Need" ADD COLUMN IF NOT EXISTS "lng" DOUBLE PRECISION;
