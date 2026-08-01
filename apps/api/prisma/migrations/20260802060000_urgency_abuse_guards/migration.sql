-- AlterTable
ALTER TABLE "Need" ADD COLUMN     "renewalGeneration" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "UrgencyEvaluationLog" (
    "id" TEXT NOT NULL,
    "needId" TEXT NOT NULL,
    "confidence" DOUBLE PRECISION NOT NULL,
    "reasoning" TEXT,
    "usedLlm" BOOLEAN NOT NULL,
    "renewalGeneration" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UrgencyEvaluationLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "UrgencyEvaluationLog_needId_idx" ON "UrgencyEvaluationLog"("needId");

-- AddForeignKey
ALTER TABLE "UrgencyEvaluationLog" ADD CONSTRAINT "UrgencyEvaluationLog_needId_fkey" FOREIGN KEY ("needId") REFERENCES "Need"("id") ON DELETE CASCADE ON UPDATE CASCADE;

