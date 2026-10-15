-- Repair databases where the original audit migration was recorded before its
-- platform-authorization checks and persistence-clock triggers were present.
-- Applied migrations remain immutable; this forward-only repair is safe when
-- some or all reviewed objects already exist.
BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

DO $repair_checks$
DECLARE
  constraint_kind "char";
  constraint_validated boolean;
BEGIN
  IF to_regclass('public.platform_authorization_audit_events') IS NULL THEN
    RAISE EXCEPTION 'public.platform_authorization_audit_events is required';
  END IF;

  SELECT contype, convalidated
  INTO constraint_kind, constraint_validated
  FROM pg_catalog.pg_constraint
  WHERE conrelid = 'public.platform_authorization_audit_events'::regclass
    AND conname = 'platform_authorization_audit_events_approval_check';

  IF NOT FOUND THEN
    ALTER TABLE public.platform_authorization_audit_events
      ADD CONSTRAINT platform_authorization_audit_events_approval_check CHECK (
        char_length(approval_reference) BETWEEN 2 AND 120
        AND approval_reference COLLATE "C" !~ '[^A-Za-z0-9._:/-]'
      );
  ELSIF constraint_kind <> 'c' THEN
    RAISE EXCEPTION
      'platform_authorization_audit_events_approval_check is not a CHECK constraint';
  ELSIF NOT constraint_validated THEN
    ALTER TABLE public.platform_authorization_audit_events
      VALIDATE CONSTRAINT platform_authorization_audit_events_approval_check;
  END IF;

  SELECT contype, convalidated
  INTO constraint_kind, constraint_validated
  FROM pg_catalog.pg_constraint
  WHERE conrelid = 'public.platform_authorization_audit_events'::regclass
    AND conname = 'platform_authorization_audit_events_permissions_check';

  IF NOT FOUND THEN
    ALTER TABLE public.platform_authorization_audit_events
      ADD CONSTRAINT platform_authorization_audit_events_permissions_check CHECK ((
        approved_permission_keys = ARRAY[
          'platform.organizations.create',
          'platform.organizations.read',
          'platform.organizations.update',
          'platform.organizations.activate',
          'platform.organizations.suspend'
        ]::varchar(80)[]
        AND (
          (outcome = 'granted' AND granted_permission_keys = approved_permission_keys)
          OR (
            outcome = 'already_granted'
            AND granted_permission_keys = ARRAY[]::varchar(80)[]
          )
        )
      ) IS TRUE);
  ELSIF constraint_kind <> 'c' THEN
    RAISE EXCEPTION
      'platform_authorization_audit_events_permissions_check is not a CHECK constraint';
  ELSIF NOT constraint_validated THEN
    ALTER TABLE public.platform_authorization_audit_events
      VALIDATE CONSTRAINT platform_authorization_audit_events_permissions_check;
  END IF;
END
$repair_checks$;

CREATE OR REPLACE FUNCTION public.stamp_organization_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
BEGIN
  NEW.recorded_at := pg_catalog.clock_timestamp();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.stamp_platform_authorization_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
BEGIN
  NEW.recorded_at := pg_catalog.clock_timestamp();
  NEW.operator_session_role := SESSION_USER;
  NEW.operator_database_role := CURRENT_USER;
  NEW.database_name := pg_catalog.current_database();
  RETURN NEW;
END;
$function$;

DO $repair_triggers$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger
    WHERE tgrelid = 'public.organization_audit_events'::regclass
      AND tgname = 'organization_audit_stamp'
      AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER organization_audit_stamp
    BEFORE INSERT ON public.organization_audit_events
    FOR EACH ROW EXECUTE FUNCTION public.stamp_organization_audit();
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger
    WHERE tgrelid = 'public.platform_authorization_audit_events'::regclass
      AND tgname = 'platform_authorization_audit_stamp'
      AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER platform_authorization_audit_stamp
    BEFORE INSERT ON public.platform_authorization_audit_events
    FOR EACH ROW EXECUTE FUNCTION public.stamp_platform_authorization_audit();
  END IF;
END
$repair_triggers$;

ALTER TABLE public.organization_audit_events
  ENABLE TRIGGER organization_audit_stamp;

ALTER TABLE public.platform_authorization_audit_events
  ENABLE TRIGGER platform_authorization_audit_stamp;

REVOKE ALL ON FUNCTION
  public.stamp_organization_audit(),
  public.stamp_platform_authorization_audit()
FROM PUBLIC;

REVOKE ALL ON TABLE
  public.organization_audit_events,
  public.platform_authorization_audit_events
FROM PUBLIC;

REVOKE ALL ON TYPE
  public.organization_audit_action,
  public.platform_authorization_audit_action,
  public.platform_authorization_audit_outcome
FROM PUBLIC;

COMMIT;
