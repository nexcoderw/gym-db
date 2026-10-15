-- CreateEnum
CREATE TYPE "organization_owner_invitation_delivery_status" AS ENUM ('queued', 'processing', 'confirmed', 'failed', 'uncertain');

-- AlterEnum
ALTER TYPE "organization_ownership_audit_action" ADD VALUE 'invitation_delivery_queued';

-- CreateTable
CREATE TABLE "organization_owner_invitation_deliveries" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "owner_invitation_id" UUID NOT NULL,
    "requested_by_platform_staff_id" UUID NOT NULL,
    "status" "organization_owner_invitation_delivery_status" NOT NULL DEFAULT 'queued',
    "attempt_count" INTEGER NOT NULL DEFAULT 0,
    "max_attempts" INTEGER NOT NULL DEFAULT 3,
    "next_attempt_at" TIMESTAMPTZ(6),
    "lease_acquired_at" TIMESTAMPTZ(6),
    "lease_expires_at" TIMESTAMPTZ(6),
    "claimed_by" VARCHAR(120),
    "provider_idempotency_key" VARCHAR(128) NOT NULL,
    "provider_message_id" VARCHAR(128),
    "last_error_code" VARCHAR(63),
    "token_digest" VARCHAR(128),
    "token_ciphertext" BYTEA,
    "token_initialization_vector" BYTEA,
    "token_authentication_tag" BYTEA,
    "token_encryption_key_id" VARCHAR(120),
    "token_encryption_version" INTEGER,
    "token_expires_at" TIMESTAMPTZ(6) NOT NULL,
    "confirmed_at" TIMESTAMPTZ(6),
    "failed_at" TIMESTAMPTZ(6),
    "uncertain_at" TIMESTAMPTZ(6),
    "token_erased_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "organization_owner_invitation_deliveries_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "owner_invitation_deliveries_provider_idempotency_key" ON "organization_owner_invitation_deliveries"("provider_idempotency_key");

-- CreateIndex
CREATE UNIQUE INDEX "owner_invitation_deliveries_provider_message_id_key" ON "organization_owner_invitation_deliveries"("provider_message_id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_owner_invitation_deliveries_token_digest_key" ON "organization_owner_invitation_deliveries"("token_digest");

-- CreateIndex
CREATE INDEX "organization_owner_invitation_deliveries_org_status_next_id_idx" ON "organization_owner_invitation_deliveries"("organization_id", "status", "next_attempt_at", "id");

-- CreateIndex
CREATE INDEX "owner_invitation_deliveries_org_actor_created_id_idx" ON "organization_owner_invitation_deliveries"("organization_id", "requested_by_platform_staff_id", "created_at" DESC, "id");

-- CreateIndex
CREATE INDEX "organization_owner_invitation_deliveries_worker_claim_idx" ON "organization_owner_invitation_deliveries"("status", "next_attempt_at", "lease_expires_at", "id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_owner_invitation_deliveries_organization_id_key" ON "organization_owner_invitation_deliveries"("organization_id", "id");

-- CreateIndex
CREATE UNIQUE INDEX "owner_invitation_deliveries_org_invitation_key" ON "organization_owner_invitation_deliveries"("organization_id", "owner_invitation_id");

-- AddForeignKey
ALTER TABLE "organization_owner_invitation_deliveries" ADD CONSTRAINT "organization_owner_invitation_deliveries_organization_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_owner_invitation_deliveries" ADD CONSTRAINT "organization_owner_invitation_deliveries_invitation_fkey" FOREIGN KEY ("organization_id", "owner_invitation_id") REFERENCES "organization_owner_invitations"("organization_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_owner_invitation_deliveries" ADD CONSTRAINT "organization_owner_invitation_deliveries_actor_fkey" FOREIGN KEY ("requested_by_platform_staff_id") REFERENCES "platform_staff"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;
