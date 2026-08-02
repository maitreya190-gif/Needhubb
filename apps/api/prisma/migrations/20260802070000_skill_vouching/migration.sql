-- CreateTable
CREATE TABLE "Vouch" (
    "id" TEXT NOT NULL,
    "voucherId" TEXT NOT NULL,
    "voucheeId" TEXT NOT NULL,
    "skillId" TEXT NOT NULL,
    "testimonial" TEXT,
    "verified" BOOLEAN NOT NULL DEFAULT false,
    "credibilityWeight" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "suspicious" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Vouch_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Vouch_voucheeId_skillId_idx" ON "Vouch"("voucheeId", "skillId");

-- CreateIndex
CREATE UNIQUE INDEX "Vouch_voucherId_voucheeId_skillId_key" ON "Vouch"("voucherId", "voucheeId", "skillId");

-- AddForeignKey
ALTER TABLE "Vouch" ADD CONSTRAINT "Vouch_voucherId_fkey" FOREIGN KEY ("voucherId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Vouch" ADD CONSTRAINT "Vouch_voucheeId_fkey" FOREIGN KEY ("voucheeId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Vouch" ADD CONSTRAINT "Vouch_skillId_fkey" FOREIGN KEY ("skillId") REFERENCES "Skill"("id") ON DELETE CASCADE ON UPDATE CASCADE;

