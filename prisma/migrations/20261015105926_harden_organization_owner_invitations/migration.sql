BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

-- CreateIndex
CREATE INDEX "organization_ownership_audit_events_org_action_time_idx" ON "organization_ownership_audit_events"("organization_id", "action", "recorded_at" DESC, "id");

-- Enforce the reviewed recipient, delivery-lifecycle and timestamp contracts for every SQL writer.
ALTER TABLE public.organization_owner_invitations
  ADD CONSTRAINT organization_owner_invitations_email_check CHECK (
    char_length(invited_email::text) BETWEEN 3 AND 254
    AND invited_email::text = lower(btrim(invited_email::text))
  ),
  ADD CONSTRAINT organization_owner_invitations_display_name_nonblank_check CHECK (
    char_length(btrim(invited_display_name,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
    )) > 0
  ),
  ADD CONSTRAINT organization_owner_invitations_lifecycle_check CHECK ((
    CASE status
      WHEN 'pending_delivery' THEN token_digest IS NULL AND expires_at IS NULL
        AND sent_at IS NULL AND accepted_at IS NULL AND revoked_at IS NULL
      WHEN 'sent' THEN token_digest IS NOT NULL AND char_length(token_digest) BETWEEN 64 AND 128
        AND expires_at IS NOT NULL AND sent_at IS NOT NULL
        AND accepted_at IS NULL AND revoked_at IS NULL
      WHEN 'accepted' THEN token_digest IS NULL AND expires_at IS NOT NULL
        AND sent_at IS NOT NULL AND accepted_at IS NOT NULL AND revoked_at IS NULL
      WHEN 'revoked' THEN token_digest IS NULL AND accepted_at IS NULL AND revoked_at IS NOT NULL
      ELSE false
    END
  ) IS TRUE),
  ADD CONSTRAINT organization_owner_invitations_timestamp_order_check CHECK (
    (sent_at IS NULL OR sent_at >= created_at)
    AND ((sent_at IS NULL) = (expires_at IS NULL))
    AND (expires_at IS NULL OR expires_at > sent_at)
    AND (accepted_at IS NULL OR (
      accepted_at >= sent_at AND accepted_at <= expires_at
    ))
    AND (revoked_at IS NULL OR (
      revoked_at >= created_at AND (sent_at IS NULL OR revoked_at >= sent_at)
    ))
  );

-- PostgreSQL is the concurrency authority for outstanding invitations.
CREATE UNIQUE INDEX organization_owner_invitations_outstanding_email_key
  ON public.organization_owner_invitations (organization_id, invited_email)
  WHERE status IN ('pending_delivery', 'sent');

-- Organization, recipient and initiating actor identify the original security decision.
CREATE FUNCTION public.guard_organization_owner_invitation_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
    OR NEW.invited_email IS DISTINCT FROM OLD.invited_email
    OR NEW.invited_by_platform_staff_id IS DISTINCT FROM OLD.invited_by_platform_staff_id
  THEN
    RAISE EXCEPTION 'organization owner invitation identity is immutable'
      USING ERRCODE = '23514',
        CONSTRAINT = 'organization_owner_invitation_identity_guard';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER organization_owner_invitation_identity_guard
BEFORE UPDATE ON public.organization_owner_invitations
FOR EACH ROW EXECUTE FUNCTION public.guard_organization_owner_invitation_identity();

-- Audit metadata is action-specific and cannot describe an impossible state transition.
ALTER TABLE public.organization_ownership_audit_events
  ADD CONSTRAINT organization_ownership_audit_events_request_check CHECK (
    char_length(request_id) BETWEEN 1 AND 128
    AND request_id COLLATE "C" !~ '[^A-Za-z0-9._:-]'
  ),
  ADD CONSTRAINT organization_ownership_audit_events_metadata_check CHECK ((
    CASE action
      WHEN 'invitation_created' THEN previous_invitation_status IS NULL
        AND resulting_invitation_status = 'pending_delivery'
      WHEN 'invitation_revoked' THEN previous_invitation_status IN ('pending_delivery', 'sent')
        AND resulting_invitation_status = 'revoked'
      ELSE false
    END
  ) IS TRUE);

-- Persistence time is assigned by PostgreSQL rather than accepted from an application caller.
CREATE FUNCTION public.stamp_organization_ownership_audit_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  NEW.recorded_at := clock_timestamp();
  RETURN NEW;
END;
$function$;

CREATE TRIGGER organization_ownership_audit_stamp
BEFORE INSERT ON public.organization_ownership_audit_events
FOR EACH ROW EXECUTE FUNCTION public.stamp_organization_ownership_audit_event();

-- Environment-specific runtime/test grants are reviewed separately; PUBLIC receives nothing.
REVOKE ALL ON TABLE
  public.organization_owner_invitations,
  public.organization_ownership_audit_events
FROM PUBLIC;

REVOKE ALL ON TYPE
  public.organization_owner_invitation_status,
  public.organization_ownership_audit_action
FROM PUBLIC;

REVOKE ALL ON FUNCTION
  public.guard_organization_owner_invitation_identity(),
  public.stamp_organization_ownership_audit_event()
FROM PUBLIC;

COMMIT;
