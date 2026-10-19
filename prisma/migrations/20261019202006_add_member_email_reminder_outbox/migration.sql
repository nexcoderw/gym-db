-- Additive migration. Apply to the isolated test database before application tests.
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

-- CreateEnum
CREATE TYPE "organization_member_email_suppression_reason" AS ENUM ('bounce', 'complaint', 'manual');

-- CreateEnum
CREATE TYPE "organization_member_reminder_kind" AS ENUM ('three_days_before', 'expiry_day');

-- CreateEnum
CREATE TYPE "organization_member_reminder_channel" AS ENUM ('email', 'sms');

-- CreateEnum
CREATE TYPE "organization_member_reminder_status" AS ENUM ('queued', 'processing', 'accepted', 'delivered', 'bounced', 'failed', 'uncertain', 'skipped');

-- AlterTable
ALTER TABLE "organization_members" ADD COLUMN     "reminder_email_opted_out_at" TIMESTAMPTZ(6),
ADD COLUMN     "reminder_email_suppressed_at" TIMESTAMPTZ(6),
ADD COLUMN     "reminder_email_suppression_reason" "organization_member_email_suppression_reason";

-- CreateTable
CREATE TABLE "organization_member_reminder_deliveries" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "member_id" UUID NOT NULL,
    "member_subscription_id" UUID NOT NULL,
    "kind" "organization_member_reminder_kind" NOT NULL,
    "channel" "organization_member_reminder_channel" NOT NULL,
    "status" "organization_member_reminder_status" NOT NULL DEFAULT 'queued',
    "due_date" DATE NOT NULL,
    "recipient_email" CITEXT,
    "attempt_count" INTEGER NOT NULL DEFAULT 0,
    "next_attempt_at" TIMESTAMPTZ(6),
    "lease_expires_at" TIMESTAMPTZ(6),
    "provider_idempotency_key" VARCHAR(128) NOT NULL,
    "provider_message_id" VARCHAR(128),
    "last_error_code" VARCHAR(63),
    "accepted_at" TIMESTAMPTZ(6),
    "delivered_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "member_reminder_deliveries_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "member_reminder_deliveries_provider_key" ON "organization_member_reminder_deliveries"("provider_idempotency_key");

-- CreateIndex
CREATE UNIQUE INDEX "member_reminder_deliveries_provider_message_key" ON "organization_member_reminder_deliveries"("provider_message_id");

-- CreateIndex
CREATE INDEX "member_reminder_deliveries_worker_idx" ON "organization_member_reminder_deliveries"("status", "next_attempt_at", "lease_expires_at", "id");

-- CreateIndex
CREATE INDEX "member_reminder_deliveries_org_member_idx" ON "organization_member_reminder_deliveries"("organization_id", "member_id", "created_at" DESC, "id");

-- CreateIndex
CREATE INDEX "member_reminder_deliveries_org_due_idx" ON "organization_member_reminder_deliveries"("organization_id", "due_date", "status", "id");

-- CreateIndex
CREATE UNIQUE INDEX "member_reminder_deliveries_once_per_kind_key" ON "organization_member_reminder_deliveries"("organization_id", "member_subscription_id", "kind", "channel");

-- AddForeignKey
ALTER TABLE "organization_member_reminder_deliveries" ADD CONSTRAINT "member_reminder_deliveries_org_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_member_reminder_deliveries" ADD CONSTRAINT "member_reminder_deliveries_member_fkey" FOREIGN KEY ("organization_id", "member_id") REFERENCES "organization_members"("organization_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_member_reminder_deliveries" ADD CONSTRAINT "member_reminder_deliveries_subscription_fkey" FOREIGN KEY ("organization_id", "member_subscription_id", "member_id") REFERENCES "organization_member_subscriptions"("organization_id", "id", "member_id") ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE public.organization_members
    ADD CONSTRAINT members_reminder_suppression_pair_check
        CHECK ((reminder_email_suppressed_at IS NULL) =
               (reminder_email_suppression_reason IS NULL));

ALTER TABLE public.organization_member_reminder_deliveries
    ADD CONSTRAINT member_reminder_deliveries_attempt_check
        CHECK (attempt_count >= 0),
    ADD CONSTRAINT member_reminder_deliveries_recipient_check
        CHECK (channel <> 'email' OR
               (recipient_email IS NOT NULL AND btrim(recipient_email::text) <> '')),
    ADD CONSTRAINT member_reminder_deliveries_provider_key_check
        CHECK (btrim(provider_idempotency_key) <> ''),
    ADD CONSTRAINT member_reminder_deliveries_timestamp_check
        CHECK (updated_at >= created_at);

REVOKE ALL ON TABLE public.organization_member_reminder_deliveries FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_member_email_suppression_reason FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_member_reminder_kind FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_member_reminder_channel FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_member_reminder_status FROM PUBLIC;

COMMIT;
