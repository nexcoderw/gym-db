-- CreateEnum
CREATE TYPE "organization_audit_action" AS ENUM ('create', 'update', 'activate', 'suspend');

-- CreateEnum
CREATE TYPE "platform_authorization_audit_action" AS ENUM ('provision_organization_manager');

-- CreateEnum
CREATE TYPE "platform_authorization_audit_outcome" AS ENUM ('granted', 'already_granted');

-- CreateTable
CREATE TABLE "organization_audit_events" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "actor_platform_staff_id" UUID NOT NULL,
    "request_id" VARCHAR(128) NOT NULL,
    "action" "organization_audit_action" NOT NULL,
    "previous_status" "organization_status",
    "resulting_status" "organization_status" NOT NULL,
    "changed_fields" VARCHAR(32)[],
    "previous_name" VARCHAR(160),
    "resulting_name" VARCHAR(160),
    "occurred_at" TIMESTAMPTZ(6) NOT NULL,
    "recorded_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "organization_audit_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "platform_authorization_audit_events" (
    "id" UUID NOT NULL,
    "action" "platform_authorization_audit_action" NOT NULL,
    "target_platform_staff_id" UUID NOT NULL,
    "target_platform_role_id" UUID NOT NULL,
    "approved_permission_keys" VARCHAR(80)[],
    "granted_permission_keys" VARCHAR(80)[],
    "operator_session_role" VARCHAR(63) NOT NULL DEFAULT SESSION_USER,
    "operator_database_role" VARCHAR(63) NOT NULL DEFAULT CURRENT_USER,
    "database_name" VARCHAR(63) NOT NULL DEFAULT CURRENT_DATABASE(),
    "approval_reference" VARCHAR(120) NOT NULL,
    "correlation_id" UUID NOT NULL,
    "outcome" "platform_authorization_audit_outcome" NOT NULL,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL,
    "recorded_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "platform_authorization_audit_events_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "organization_audit_events_organization_time_idx" ON "organization_audit_events"("organization_id", "recorded_at" DESC, "id");

-- CreateIndex
CREATE INDEX "organization_audit_events_actor_time_idx" ON "organization_audit_events"("actor_platform_staff_id", "recorded_at" DESC, "id");

-- CreateIndex
CREATE INDEX "organization_audit_events_recorded_time_idx" ON "organization_audit_events"("recorded_at", "id");

-- CreateIndex
CREATE INDEX "organization_audit_events_request_idx" ON "organization_audit_events"("request_id");

-- CreateIndex
CREATE INDEX "platform_authorization_audit_events_staff_time_idx" ON "platform_authorization_audit_events"("target_platform_staff_id", "recorded_at" DESC, "id");

-- CreateIndex
CREATE INDEX "platform_authorization_audit_events_role_time_idx" ON "platform_authorization_audit_events"("target_platform_role_id", "recorded_at" DESC, "id");

-- CreateIndex
CREATE INDEX "platform_authorization_audit_events_recorded_time_idx" ON "platform_authorization_audit_events"("recorded_at", "id");

-- CreateIndex
CREATE INDEX "platform_authorization_audit_events_correlation_idx" ON "platform_authorization_audit_events"("correlation_id");

-- AddForeignKey
ALTER TABLE "organization_audit_events" ADD CONSTRAINT "organization_audit_events_organization_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_audit_events" ADD CONSTRAINT "organization_audit_events_actor_fkey" FOREIGN KEY ("actor_platform_staff_id") REFERENCES "platform_staff"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "platform_authorization_audit_events" ADD CONSTRAINT "platform_authorization_audit_events_staff_fkey" FOREIGN KEY ("target_platform_staff_id") REFERENCES "platform_staff"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "platform_authorization_audit_events" ADD CONSTRAINT "platform_authorization_audit_events_role_fkey" FOREIGN KEY ("target_platform_role_id") REFERENCES "platform_roles"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;
