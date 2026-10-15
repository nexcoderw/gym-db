-- Repair environments where the original organization-integrity migration was recorded before its
-- constraint SQL was present. Existing named checks are retained and validated; missing checks are
-- added with their reviewed definitions. PostgreSQL validates new checks against all existing rows.
BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

DO $$
DECLARE
  constraint_kind text;
  constraint_validated boolean;
BEGIN
  IF to_regclass('public.organizations') IS NULL THEN
    RAISE EXCEPTION 'public.organizations is required before repairing integrity constraints';
  END IF;

  SELECT contype, convalidated
  INTO constraint_kind, constraint_validated
  FROM pg_catalog.pg_constraint
  WHERE conrelid = 'public.organizations'::regclass
    AND conname = 'organizations_name_nonblank_check';

  IF NOT FOUND THEN
    ALTER TABLE public.organizations
      ADD CONSTRAINT organizations_name_nonblank_check CHECK (
        char_length(btrim(name,
          U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
        )) > 0
      );
  ELSIF constraint_kind <> 'c' THEN
    RAISE EXCEPTION 'organizations_name_nonblank_check exists but is not a CHECK constraint';
  ELSIF NOT constraint_validated THEN
    ALTER TABLE public.organizations
      VALIDATE CONSTRAINT organizations_name_nonblank_check;
  END IF;

  SELECT contype, convalidated
  INTO constraint_kind, constraint_validated
  FROM pg_catalog.pg_constraint
  WHERE conrelid = 'public.organizations'::regclass
    AND conname = 'organizations_slug_format_check';

  IF NOT FOUND THEN
    ALTER TABLE public.organizations
      ADD CONSTRAINT organizations_slug_format_check CHECK (
        char_length(slug) BETWEEN 3 AND 63
        AND slug COLLATE "C" ~ '^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
      );
  ELSIF constraint_kind <> 'c' THEN
    RAISE EXCEPTION 'organizations_slug_format_check exists but is not a CHECK constraint';
  ELSIF NOT constraint_validated THEN
    ALTER TABLE public.organizations
      VALIDATE CONSTRAINT organizations_slug_format_check;
  END IF;

  SELECT contype, convalidated
  INTO constraint_kind, constraint_validated
  FROM pg_catalog.pg_constraint
  WHERE conrelid = 'public.organizations'::regclass
    AND conname = 'organizations_slug_reserved_check';

  IF NOT FOUND THEN
    ALTER TABLE public.organizations
      ADD CONSTRAINT organizations_slug_reserved_check CHECK (
        slug NOT IN (
          'admin', 'api', 'app', 'www', 'auth', 'login', 'member', 'members',
          'portal', 'dashboard', 'billing', 'support', 'status', 'static',
          'assets', 'cdn', 'mail', 'dev', 'staging', 'test', 'localhost',
          'account', 'accounts', 'oauth', 'console', 'internal', 'health',
          'metrics', 'production', 'development', 'bootstrap'
        )
      );
  ELSIF constraint_kind <> 'c' THEN
    RAISE EXCEPTION 'organizations_slug_reserved_check exists but is not a CHECK constraint';
  ELSIF NOT constraint_validated THEN
    ALTER TABLE public.organizations
      VALIDATE CONSTRAINT organizations_slug_reserved_check;
  END IF;
END
$$;

REVOKE ALL ON TABLE public.organizations FROM PUBLIC;

COMMIT;
