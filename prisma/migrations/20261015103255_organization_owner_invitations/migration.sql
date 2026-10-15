-- CreateEnum
CREATE TYPE "organization_owner_invitation_status" AS ENUM ('pending_delivery', 'sent', 'accepted', 'revoked');

-- CreateEnum
CREATE TYPE "organization_ownership_audit_action" AS ENUM ('invitation_created', 'invitation_revoked');

-- CreateTable
CREATE TABLE "organization_owner_invitations" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "invited_email" CITEXT NOT NULL,
    "invited_display_name" VARCHAR(160) NOT NULL,
    "invited_by_platform_staff_id" UUID NOT NULL,
    "status" "organization_owner_invitation_status" NOT NULL DEFAULT 'pending_delivery',
    "token_digest" VARCHAR(128),
    "expires_at" TIMESTAMPTZ(6),
    "sent_at" TIMESTAMPTZ(6),
    "accepted_at" TIMESTAMPTZ(6),
    "revoked_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "organization_owner_invitations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organization_ownership_audit_events" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "owner_invitation_id" UUID NOT NULL,
    "actor_platform_staff_id" UUID NOT NULL,
    "action" "organization_ownership_audit_action" NOT NULL,
    "request_id" VARCHAR(128) NOT NULL,
    "previous_invitation_status" "organization_owner_invitation_status",
    "resulting_invitation_status" "organization_owner_invitation_status" NOT NULL,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL,
    "recorded_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "organization_ownership_audit_events_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "organization_owner_invitations_token_digest_key" ON "organization_owner_invitations"("token_digest");

-- CreateIndex
CREATE INDEX "organization_owner_invitations_org_status_created_id_idx" ON "organization_owner_invitations"("organization_id", "status", "created_at" DESC, "id");

-- CreateIndex
CREATE INDEX "organization_owner_invitations_org_email_created_id_idx" ON "organization_owner_invitations"("organization_id", "invited_email", "created_at" DESC, "id");

-- CreateIndex
CREATE INDEX "organization_owner_invitations_org_actor_created_id_idx" ON "organization_owner_invitations"("organization_id", "invited_by_platform_staff_id", "created_at" DESC, "id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_owner_invitations_organization_id_key" ON "organization_owner_invitations"("organization_id", "id");

-- CreateIndex
CREATE INDEX "organization_ownership_audit_events_org_invitation_time_idx" ON "organization_ownership_audit_events"("organization_id", "owner_invitation_id", "recorded_at" DESC, "id");

-- CreateIndex
CREATE INDEX "organization_ownership_audit_events_org_actor_time_idx" ON "organization_ownership_audit_events"("organization_id", "actor_platform_staff_id", "recorded_at" DESC, "id");

-- CreateIndex
CREATE INDEX "organization_ownership_audit_events_org_time_idx" ON "organization_ownership_audit_events"("organization_id", "recorded_at" DESC, "id");

-- CreateIndex
CREATE INDEX "organization_ownership_audit_events_request_idx" ON "organization_ownership_audit_events"("request_id");

-- AddForeignKey
ALTER TABLE "organization_owner_invitations" ADD CONSTRAINT "organization_owner_invitations_organization_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_owner_invitations" ADD CONSTRAINT "organization_owner_invitations_actor_fkey" FOREIGN KEY ("invited_by_platform_staff_id") REFERENCES "platform_staff"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_ownership_audit_events" ADD CONSTRAINT "organization_ownership_audit_events_organization_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_ownership_audit_events" ADD CONSTRAINT "organization_ownership_audit_events_invitation_fkey" FOREIGN KEY ("organization_id", "owner_invitation_id") REFERENCES "organization_owner_invitations"("organization_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_ownership_audit_events" ADD CONSTRAINT "organization_ownership_audit_events_actor_fkey" FOREIGN KEY ("actor_platform_staff_id") REFERENCES "platform_staff"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;
