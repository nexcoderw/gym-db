-- CreateEnum
CREATE TYPE "organization_feature_entitlement_change_source" AS ENUM (
	'initial_migration',
	'organization_provisioning',
	'platform_admin'
);

-- CreateTable
CREATE TABLE "organization_feature_entitlements" (
	"organization_id" UUID NOT NULL,
	"feature_key" VARCHAR(80) NOT NULL,
	"enabled" BOOLEAN NOT NULL DEFAULT false,
	"starts_at" TIMESTAMPTZ(6),
	"expires_at" TIMESTAMPTZ(6),
	"version" INTEGER NOT NULL DEFAULT 1,
	"updated_by_platform_staff_id" UUID,
	"created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
	"updated_at" TIMESTAMPTZ(6) NOT NULL,

	CONSTRAINT "organization_feature_entitlements_pkey"
		PRIMARY KEY ("organization_id", "feature_key"),
	CONSTRAINT organization_feature_entitlements_feature_key_check CHECK (
		"feature_key" IN (
			'organization.dashboard.read',
			'organization.membership-plans.read',
			'organization.membership-plans.manage',
			'organization.members.read',
			'organization.members.create',
			'organization.members.update',
			'organization.members.archive',
			'organization.member-subscriptions.read',
			'organization.member-subscriptions.manage',
			'organization.payments.read',
			'organization.payments.create',
			'organization.payments.void',
			'organization.payments.refund',
			'organization.reminders.read',
			'organization.reminders.send',
			'organization.reports.read',
			'organization.reports.export'
		)
	),
	CONSTRAINT organization_feature_entitlements_version_check CHECK ("version" > 0),
	CONSTRAINT organization_feature_entitlements_window_check CHECK (
		"starts_at" IS NULL OR "expires_at" IS NULL OR "starts_at" < "expires_at"
	)
);

-- CreateTable
CREATE TABLE "organization_feature_entitlement_audit_events" (
	"id" UUID NOT NULL DEFAULT gen_random_uuid(),
	"organization_id" UUID NOT NULL,
	"feature_key" VARCHAR(80) NOT NULL,
	"source" "organization_feature_entitlement_change_source" NOT NULL,
	"previous_enabled" BOOLEAN,
	"resulting_enabled" BOOLEAN NOT NULL,
	"previous_starts_at" TIMESTAMPTZ(6),
	"resulting_starts_at" TIMESTAMPTZ(6),
	"previous_expires_at" TIMESTAMPTZ(6),
	"resulting_expires_at" TIMESTAMPTZ(6),
	"resulting_version" INTEGER NOT NULL,
	"actor_platform_staff_id" UUID,
	"request_id" VARCHAR(128),
	"reason" VARCHAR(500) NOT NULL,
	"occurred_at" TIMESTAMPTZ(6) NOT NULL,
	"recorded_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

	CONSTRAINT "organization_feature_entitlement_audit_events_pkey" PRIMARY KEY ("id"),
	CONSTRAINT organization_feature_entitlement_audits_version_check CHECK ("resulting_version" > 0),
	CONSTRAINT organization_feature_entitlement_audits_reason_check CHECK (
		char_length(btrim("reason")) BETWEEN 10 AND 500
	),
	CONSTRAINT organization_feature_entitlement_audits_request_check CHECK (
		"request_id" IS NULL OR char_length(btrim("request_id")) BETWEEN 1 AND 128
	),
	CONSTRAINT organization_feature_entitlement_audits_source_evidence_check CHECK (
		(
			"source" = 'platform_admin'
			AND "actor_platform_staff_id" IS NOT NULL
			AND "request_id" IS NOT NULL
		)
		OR (
			"source" = 'organization_provisioning'
			AND "request_id" IS NOT NULL
		)
		OR (
			"source" = 'initial_migration'
			AND "actor_platform_staff_id" IS NULL
			AND "request_id" IS NULL
		)
	)
);

-- CreateIndex
CREATE INDEX "organization_feature_entitlements_org_effective_idx"
	ON "organization_feature_entitlements" (
		"organization_id",
		"enabled",
		"starts_at",
		"expires_at"
	);
CREATE INDEX "organization_feature_entitlements_updater_time_idx"
	ON "organization_feature_entitlements" (
		"updated_by_platform_staff_id",
		"updated_at" DESC
	);
CREATE UNIQUE INDEX "organization_feature_entitlement_audits_org_feature_version_key"
	ON "organization_feature_entitlement_audit_events" (
		"organization_id",
		"feature_key",
		"resulting_version"
	);
CREATE INDEX "organization_feature_entitlement_audits_org_time_idx"
	ON "organization_feature_entitlement_audit_events" (
		"organization_id",
		"recorded_at" DESC,
		"id"
	);
CREATE INDEX "organization_feature_entitlement_audits_org_feature_time_idx"
	ON "organization_feature_entitlement_audit_events" (
		"organization_id",
		"feature_key",
		"recorded_at" DESC,
		"id"
	);
CREATE INDEX "organization_feature_entitlement_audits_actor_time_idx"
	ON "organization_feature_entitlement_audit_events" (
		"actor_platform_staff_id",
		"recorded_at" DESC,
		"id"
	);
CREATE INDEX "organization_feature_entitlement_audits_request_idx"
	ON "organization_feature_entitlement_audit_events" ("request_id");

-- AddForeignKey
ALTER TABLE "organization_feature_entitlements"
	ADD CONSTRAINT "organization_feature_entitlements_organization_fkey"
	FOREIGN KEY ("organization_id") REFERENCES "organizations"("id")
	ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE "organization_feature_entitlements"
	ADD CONSTRAINT "organization_feature_entitlements_updater_fkey"
	FOREIGN KEY ("updated_by_platform_staff_id") REFERENCES "platform_staff"("id")
	ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE "organization_feature_entitlement_audit_events"
	ADD CONSTRAINT "organization_feature_entitlement_audits_organization_fkey"
	FOREIGN KEY ("organization_id") REFERENCES "organizations"("id")
	ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE "organization_feature_entitlement_audit_events"
	ADD CONSTRAINT "organization_feature_entitlement_audits_entitlement_fkey"
	FOREIGN KEY ("organization_id", "feature_key")
	REFERENCES "organization_feature_entitlements"("organization_id", "feature_key")
	ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE "organization_feature_entitlement_audit_events"
	ADD CONSTRAINT "organization_feature_entitlement_audits_actor_fkey"
	FOREIGN KEY ("actor_platform_staff_id") REFERENCES "platform_staff"("id")
	ON DELETE RESTRICT ON UPDATE RESTRICT;

-- Prevent entitlement identity changes while allowing reviewed state/version updates.
CREATE FUNCTION organization_feature_entitlement_identity_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
	IF NEW.organization_id <> OLD.organization_id
		OR NEW.feature_key <> OLD.feature_key
		OR NEW.created_at <> OLD.created_at THEN
		RAISE EXCEPTION 'organization entitlement identity is immutable';
	END IF;
	IF NEW.version <> OLD.version + 1 THEN
		RAISE EXCEPTION 'organization entitlement version must advance by one';
	END IF;
	RETURN NEW;
END;
$$;

CREATE TRIGGER organization_feature_entitlement_identity_guard
	BEFORE UPDATE ON "organization_feature_entitlements"
	FOR EACH ROW EXECUTE FUNCTION organization_feature_entitlement_identity_guard();

-- Audit evidence is append-only.
CREATE FUNCTION organization_feature_entitlement_audit_history_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
	RAISE EXCEPTION 'organization entitlement audit history is append-only';
END;
$$;

CREATE TRIGGER organization_feature_entitlement_audit_history_guard
	BEFORE UPDATE OR DELETE ON "organization_feature_entitlement_audit_events"
	FOR EACH ROW EXECUTE FUNCTION organization_feature_entitlement_audit_history_guard();

REVOKE ALL ON FUNCTION organization_feature_entitlement_identity_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION organization_feature_entitlement_audit_history_guard() FROM PUBLIC;

-- Preserve current functionality for organizations that predate entitlement enforcement.
WITH catalog(feature_key) AS (
	VALUES
		('organization.dashboard.read'),
		('organization.membership-plans.read'),
		('organization.membership-plans.manage'),
		('organization.members.read'),
		('organization.members.create'),
		('organization.members.update'),
		('organization.members.archive'),
		('organization.member-subscriptions.read'),
		('organization.member-subscriptions.manage'),
		('organization.payments.read'),
		('organization.payments.create'),
		('organization.payments.void'),
		('organization.payments.refund'),
		('organization.reminders.read'),
		('organization.reminders.send'),
		('organization.reports.read'),
		('organization.reports.export')
)
INSERT INTO "organization_feature_entitlements" (
	"organization_id", "feature_key", "enabled", "version", "updated_at"
)
SELECT organization.id, catalog.feature_key, true, 1, CURRENT_TIMESTAMP
FROM "organizations" AS organization
CROSS JOIN catalog;

INSERT INTO "organization_feature_entitlement_audit_events" (
	"organization_id",
	"feature_key",
	"source",
	"previous_enabled",
	"resulting_enabled",
	"resulting_version",
	"reason",
	"occurred_at"
)
SELECT
	entitlement."organization_id",
	entitlement."feature_key",
	'initial_migration',
	NULL,
	true,
	1,
	'Initial compatibility-preserving organization entitlement rollout',
	CURRENT_TIMESTAMP
FROM "organization_feature_entitlements" AS entitlement;

REVOKE ALL ON TABLE public.organization_feature_entitlements FROM PUBLIC;
REVOKE ALL ON TABLE public.organization_feature_entitlement_audit_events FROM PUBLIC;
