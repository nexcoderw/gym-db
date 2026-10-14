-- Forward expansion: preserve applied history and every existing audit record.
-- CHECK validation scans existing rows and takes a table lock; deploy in a quiet window.
-- Unexpected existing constraints or invalid historical rows must fail, not be silently replaced.
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

ALTER TYPE public.organization_audit_action ADD VALUE 'archive';

-- Compare the action as text so the new enum value is not used before COMMIT.
-- IS TRUE rejects nullable metadata that would otherwise pass CHECK as UNKNOWN.
ALTER TABLE public.organization_audit_events
  ADD CONSTRAINT organization_audit_events_request_check CHECK (
    char_length(request_id) BETWEEN 1 AND 128
    AND request_id COLLATE "C" !~ '[^A-Za-z0-9._:-]'
  ),
  ADD CONSTRAINT organization_audit_events_metadata_check CHECK ((
    CASE action::text
      WHEN 'create' THEN previous_status IS NULL AND resulting_status = 'pending'
        AND changed_fields = ARRAY['name','slug','status']::varchar(32)[]
        AND previous_name IS NULL AND resulting_name IS NOT NULL
      WHEN 'update' THEN previous_status IS NOT NULL AND resulting_status = previous_status
        AND changed_fields = ARRAY['name']::varchar(32)[]
        AND previous_name IS NOT NULL AND resulting_name IS NOT NULL
      WHEN 'activate' THEN previous_status IN ('pending','suspended') AND resulting_status = 'active'
        AND changed_fields = ARRAY['status','activatedAt']::varchar(32)[]
        AND previous_name IS NULL AND resulting_name IS NULL
      WHEN 'suspend' THEN previous_status = 'active' AND resulting_status = 'suspended'
        AND changed_fields = ARRAY['status','suspendedAt']::varchar(32)[]
        AND previous_name IS NULL AND resulting_name IS NULL
      WHEN 'archive' THEN previous_status IN ('pending','active','suspended')
        AND resulting_status = 'archived'
        AND changed_fields = ARRAY['status','archivedAt']::varchar(32)[]
        AND previous_name IS NULL AND resulting_name IS NULL
      ELSE false
    END
  ) IS TRUE),
  ADD CONSTRAINT organization_audit_events_names_check CHECK (
    (previous_name IS NULL OR char_length(btrim(previous_name,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
    )) > 0) AND
    (resulting_name IS NULL OR char_length(btrim(resulting_name,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
    )) > 0)
  );

-- After commit, roll forward on failure; do not remove an enum label by recreating its type.
COMMIT;
