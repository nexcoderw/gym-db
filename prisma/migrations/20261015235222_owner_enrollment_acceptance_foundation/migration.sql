/*
  Warnings:

  - A unique constraint covering the columns `[organization_id,id,user_id]` on the table `organization_memberships` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateEnum
CREATE TYPE "organization_owner_enrollment_purpose" AS ENUM ('new_user_enrollment', 'existing_user_authentication');

-- CreateEnum
CREATE TYPE "organization_owner_enrollment_status" AS ENUM ('pending', 'verified', 'consumed', 'revoked');

-- CreateEnum
CREATE TYPE "organization_owner_acceptance_audit_action" AS ENUM ('owner_invitation_accepted');

-- CreateTable
CREATE TABLE "organization_owner_enrollment_challenges" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "owner_invitation_id" UUID NOT NULL,
    "user_id" UUID,
    "purpose" "organization_owner_enrollment_purpose" NOT NULL,
    "status" "organization_owner_enrollment_status" NOT NULL DEFAULT 'pending',
    "token_digest" VARCHAR(128),
    "failed_attempts" INTEGER NOT NULL DEFAULT 0,
    "max_attempts" INTEGER NOT NULL DEFAULT 5,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "mailbox_verified_at" TIMESTAMPTZ(6),
    "authenticated_at" TIMESTAMPTZ(6),
    "step_up_verified_at" TIMESTAMPTZ(6),
    "verified_at" TIMESTAMPTZ(6),
    "consumed_at" TIMESTAMPTZ(6),
    "revoked_at" TIMESTAMPTZ(6),

    CONSTRAINT "owner_enrollment_challenges_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organization_owner_acceptance_audit_events" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "owner_invitation_id" UUID NOT NULL,
    "enrollment_challenge_id" UUID NOT NULL,
    "actor_user_id" UUID NOT NULL,
    "organization_membership_id" UUID NOT NULL,
    "action" "organization_owner_acceptance_audit_action" NOT NULL DEFAULT 'owner_invitation_accepted',
    "request_id" VARCHAR(128) NOT NULL,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL,
    "recorded_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "owner_acceptance_audit_events_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "owner_enrollment_challenges_token_digest_key" ON "organization_owner_enrollment_challenges"("token_digest");

-- CreateIndex
CREATE INDEX "owner_enrollment_challenges_org_invitation_status_idx" ON "organization_owner_enrollment_challenges"("organization_id", "owner_invitation_id", "status", "expires_at", "id");

-- CreateIndex
CREATE INDEX "owner_enrollment_challenges_org_user_created_idx" ON "organization_owner_enrollment_challenges"("organization_id", "user_id", "created_at" DESC, "id");

-- CreateIndex
CREATE INDEX "owner_enrollment_challenges_expiry_idx" ON "organization_owner_enrollment_challenges"("expires_at", "id");

-- CreateIndex
CREATE UNIQUE INDEX "owner_enrollment_challenges_proof_identity_key" ON "organization_owner_enrollment_challenges"("organization_id", "id", "owner_invitation_id", "user_id");

-- CreateIndex
CREATE INDEX "owner_acceptance_audit_events_org_actor_time_idx" ON "organization_owner_acceptance_audit_events"("organization_id", "actor_user_id", "recorded_at" DESC, "id");

-- CreateIndex
CREATE INDEX "owner_acceptance_audit_events_org_membership_time_idx" ON "organization_owner_acceptance_audit_events"("organization_id", "organization_membership_id", "recorded_at" DESC, "id");

-- CreateIndex
CREATE INDEX "owner_acceptance_audit_events_request_idx" ON "organization_owner_acceptance_audit_events"("request_id");

-- CreateIndex
CREATE UNIQUE INDEX "owner_acceptance_audit_events_org_invitation_key" ON "organization_owner_acceptance_audit_events"("organization_id", "owner_invitation_id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_memberships_org_id_user_key" ON "organization_memberships"("organization_id", "id", "user_id");

-- AddForeignKey
ALTER TABLE "organization_owner_enrollment_challenges" ADD CONSTRAINT "owner_enrollment_challenges_organization_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_owner_enrollment_challenges" ADD CONSTRAINT "owner_enrollment_challenges_invitation_fkey" FOREIGN KEY ("organization_id", "owner_invitation_id") REFERENCES "organization_owner_invitations"("organization_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_owner_enrollment_challenges" ADD CONSTRAINT "owner_enrollment_challenges_user_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_owner_acceptance_audit_events" ADD CONSTRAINT "owner_acceptance_audit_events_organization_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_owner_acceptance_audit_events" ADD CONSTRAINT "owner_acceptance_audit_events_invitation_fkey" FOREIGN KEY ("organization_id", "owner_invitation_id") REFERENCES "organization_owner_invitations"("organization_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_owner_acceptance_audit_events" ADD CONSTRAINT "owner_acceptance_audit_events_user_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_owner_acceptance_audit_events" ADD CONSTRAINT "owner_acceptance_audit_events_membership_fkey" FOREIGN KEY ("organization_id", "organization_membership_id", "actor_user_id") REFERENCES "organization_memberships"("organization_id", "id", "user_id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_owner_acceptance_audit_events" ADD CONSTRAINT "owner_acceptance_audit_events_challenge_fkey" FOREIGN KEY ("organization_id", "enrollment_challenge_id", "owner_invitation_id", "actor_user_id") REFERENCES "organization_owner_enrollment_challenges"("organization_id", "id", "owner_invitation_id", "user_id") ON DELETE RESTRICT ON UPDATE RESTRICT;
