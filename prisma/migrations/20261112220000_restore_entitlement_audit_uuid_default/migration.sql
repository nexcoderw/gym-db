-- Restore the original database-generated UUID default.
-- The previous joined_on migration unintentionally removed it.

ALTER TABLE "organization_feature_entitlement_audit_events"
ALTER COLUMN "id" SET DEFAULT gen_random_uuid();
