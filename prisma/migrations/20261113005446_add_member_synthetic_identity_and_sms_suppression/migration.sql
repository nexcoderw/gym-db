-- CreateEnum
CREATE TYPE "organization_member_sms_suppression_reason" AS ENUM ('manual');

-- AlterTable
ALTER TABLE "organization_members" ADD COLUMN     "is_synthetic" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "reminder_sms_suppressed_at" TIMESTAMPTZ(6),
ADD COLUMN     "reminder_sms_suppression_reason" "organization_member_sms_suppression_reason",
ADD COLUMN     "synthetic_batch_id" VARCHAR(120);

-- CreateIndex
CREATE INDEX "organization_members_org_synthetic_batch_id_idx" ON "organization_members"("organization_id", "is_synthetic", "synthetic_batch_id", "id");
