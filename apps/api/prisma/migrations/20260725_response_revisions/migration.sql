CREATE TABLE "ResponseRevision" (
  "id" TEXT NOT NULL,
  "responseId" TEXT NOT NULL,
  "message" TEXT NOT NULL,
  "quotedPrice" DOUBLE PRECISION,
  "workSampleUrl" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ResponseRevision_pkey" PRIMARY KEY ("id")
);

WITH ranked AS (
  SELECT
    "id",
    "needId",
    "responderId",
    "message",
    "quotedPrice",
    "workSampleUrl",
    "createdAt",
    FIRST_VALUE("id") OVER (
      PARTITION BY "needId", "responderId"
      ORDER BY "createdAt" DESC, "id" DESC
    ) AS "keptId",
    ROW_NUMBER() OVER (
      PARTITION BY "needId", "responderId"
      ORDER BY "createdAt" DESC, "id" DESC
    ) AS "rank"
  FROM "InterestResponse"
)
INSERT INTO "ResponseRevision" (
  "id",
  "responseId",
  "message",
  "quotedPrice",
  "workSampleUrl",
  "createdAt"
)
SELECT
  'legacy-revision-' || md5("id"),
  "keptId",
  "message",
  "quotedPrice",
  "workSampleUrl",
  "createdAt"
FROM ranked
WHERE "rank" > 1;

WITH ranked AS (
  SELECT
    "id",
    ROW_NUMBER() OVER (
      PARTITION BY "needId", "responderId"
      ORDER BY "createdAt" DESC, "id" DESC
    ) AS "rank"
  FROM "InterestResponse"
)
DELETE FROM "InterestResponse"
WHERE "id" IN (
  SELECT "id" FROM ranked WHERE "rank" > 1
);

CREATE UNIQUE INDEX "InterestResponse_needId_responderId_key"
  ON "InterestResponse"("needId", "responderId");

ALTER TABLE "ResponseRevision"
  ADD CONSTRAINT "ResponseRevision_responseId_fkey"
  FOREIGN KEY ("responseId") REFERENCES "InterestResponse"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
