-- AlterEnum
ALTER TYPE "NeedStatus" ADD VALUE 'EXPIRED';

-- AlterTable
ALTER TABLE "Need" ADD COLUMN     "isUrgent" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "urgencyConfidence" DOUBLE PRECISION;

-- CreateTable
CREATE TABLE "UrgencyProfile" (
    "userId" TEXT NOT NULL,
    "reliability" DOUBLE PRECISION NOT NULL DEFAULT 0.5,
    "urgentCount" INTEGER NOT NULL DEFAULT 0,
    "justifiedCount" INTEGER NOT NULL DEFAULT 0,
    "misusedCount" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "UrgencyProfile_pkey" PRIMARY KEY ("userId")
);

-- AddForeignKey
ALTER TABLE "UrgencyProfile" ADD CONSTRAINT "UrgencyProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

