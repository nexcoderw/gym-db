-- Forward-only hardening for the already-applied owner enrollment foundation.
-- This migration intentionally contains no environment-specific role grants.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

LOCK TABLE public.organization_owner_enrollment_challenges IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.organization_owner_acceptance_audit_events IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE public.organization_owner_enrollment_challenges
  ADD CONSTRAINT owner_enrollment_challenges_digest_check
  CHECK ((
    CASE status
      WHEN 'pending' THEN token_digest COLLATE "C" ~ '^[0-9a-f]{64}$'
      WHEN 'verified' THEN token_digest COLLATE "C" ~ '^[0-9a-f]{64}$'
      WHEN 'consumed' THEN token_digest IS NULL
      WHEN 'revoked' THEN token_digest IS NULL
      ELSE false
    END
  ) IS TRUE),
  ADD CONSTRAINT owner_enrollment_challenges_attempts_check
  CHECK ((
    max_attempts BETWEEN 1 AND 10
    AND failed_attempts BETWEEN 0 AND max_attempts
    AND (
      status NOT IN ('verified', 'consumed')
      OR failed_attempts < max_attempts
    )
  ) IS TRUE),
  ADD CONSTRAINT owner_enrollment_challenges_lifecycle_check
  CHECK ((
    CASE status
      WHEN 'pending' THEN
        verified_at IS NULL
        AND consumed_at IS NULL
        AND revoked_at IS NULL
      WHEN 'verified' THEN
        user_id IS NOT NULL
        AND mailbox_verified_at IS NOT NULL
        AND authenticated_at IS NOT NULL
        AND verified_at IS NOT NULL
        AND consumed_at IS NULL
        AND revoked_at IS NULL
      WHEN 'consumed' THEN
        user_id IS NOT NULL
        AND mailbox_verified_at IS NOT NULL
        AND authenticated_at IS NOT NULL
        AND verified_at IS NOT NULL
        AND consumed_at IS NOT NULL
        AND revoked_at IS NULL
      WHEN 'revoked' THEN
        revoked_at IS NOT NULL
        AND consumed_at IS NULL
      ELSE false
    END
  ) IS TRUE),
  ADD CONSTRAINT owner_enrollment_challenges_timestamps_check
  CHECK ((
    updated_at >= created_at
    AND expires_at > created_at
    AND expires_at <= created_at + interval '15 minutes'
    AND (
      mailbox_verified_at IS NULL
      OR mailbox_verified_at BETWEEN created_at AND expires_at
    )
    AND (
      authenticated_at IS NULL
      OR authenticated_at BETWEEN created_at AND expires_at
    )
    AND (
      step_up_verified_at IS NULL
      OR step_up_verified_at BETWEEN created_at AND expires_at
    )
    AND (
      verified_at IS NULL
      OR (
        verified_at BETWEEN created_at AND expires_at
        AND mailbox_verified_at IS NOT NULL
        AND authenticated_at IS NOT NULL
        AND verified_at >= mailbox_verified_at
        AND verified_at >= authenticated_at
        AND (step_up_verified_at IS NULL OR verified_at >= step_up_verified_at)
      )
    )
    AND (
      consumed_at IS NULL
      OR (
        verified_at IS NOT NULL
        AND consumed_at BETWEEN verified_at AND expires_at
      )
    )
    AND (revoked_at IS NULL OR revoked_at >= created_at)
  ) IS TRUE);

ALTER TABLE public.organization_owner_acceptance_audit_events
  ADD CONSTRAINT owner_acceptance_audit_events_request_check
  CHECK ((
    request_id COLLATE "C" ~ '^[A-Za-z0-9._:-]{1,128}$'
    AND occurred_at <= recorded_at
  ) IS TRUE);

CREATE OR REPLACE FUNCTION public.guard_owner_enrollment_challenge()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  checked_at timestamptz := clock_timestamp();
  invitation_record record;
  organization_status public.organization_status;
  user_record record;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status IN ('consumed', 'revoked') AND NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION 'terminal owner enrollment challenges are immutable'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id
      OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
      OR NEW.owner_invitation_id IS DISTINCT FROM OLD.owner_invitation_id
      OR NEW.purpose IS DISTINCT FROM OLD.purpose
      OR NEW.created_at IS DISTINCT FROM OLD.created_at
      OR NEW.expires_at IS DISTINCT FROM OLD.expires_at
      OR NEW.max_attempts IS DISTINCT FROM OLD.max_attempts
    THEN
      RAISE EXCEPTION 'owner enrollment challenge identity is immutable'
        USING ERRCODE = '23514';
    END IF;

    IF OLD.user_id IS NOT NULL AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN
      RAISE EXCEPTION 'owner enrollment challenge user binding is immutable'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.failed_attempts < OLD.failed_attempts THEN
      RAISE EXCEPTION 'owner enrollment failed attempts cannot decrease'
        USING ERRCODE = '23514';
    END IF;

    IF OLD.token_digest IS NOT NULL
      AND NEW.token_digest IS NOT NULL
      AND NEW.token_digest IS DISTINCT FROM OLD.token_digest
    THEN
      RAISE EXCEPTION 'owner enrollment token material cannot be replaced'
        USING ERRCODE = '23514';
    END IF;

    IF NOT (
      (OLD.status = 'pending' AND NEW.status IN ('pending', 'verified', 'revoked'))
      OR (OLD.status = 'verified' AND NEW.status IN ('verified', 'consumed', 'revoked'))
      OR OLD.status = NEW.status
    ) THEN
      RAISE EXCEPTION 'invalid owner enrollment challenge transition'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF NEW.user_id IS NOT NULL THEN
    SELECT user_row.email, user_row.status, user_row.email_verified_at
    INTO user_record
    FROM public.users AS user_row
    WHERE user_row.id = NEW.user_id
    FOR SHARE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'owner enrollment user does not exist'
        USING ERRCODE = '23503';
    END IF;

    SELECT invitation.invited_email,
           invitation.status,
           invitation.expires_at,
           invitation.revoked_at
    INTO invitation_record
    FROM public.organization_owner_invitations AS invitation
    WHERE invitation.organization_id = NEW.organization_id
      AND invitation.id = NEW.owner_invitation_id
    FOR UPDATE;

    IF NOT FOUND OR lower(user_record.email::text) <> lower(invitation_record.invited_email::text) THEN
      RAISE EXCEPTION 'owner enrollment identity does not match the invitation recipient'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE'
    AND OLD.status IS DISTINCT FROM NEW.status
    AND NEW.status IN ('verified', 'consumed')
  THEN
    SELECT organization.status
    INTO organization_status
    FROM public.organizations AS organization
    WHERE organization.id = NEW.organization_id
    FOR SHARE;

    IF NOT FOUND OR organization_status NOT IN ('pending', 'active') THEN
      RAISE EXCEPTION 'organization is not eligible for owner enrollment'
        USING ERRCODE = '23514';
    END IF;

    SELECT invitation.invited_email,
           invitation.status,
           invitation.expires_at,
           invitation.revoked_at
    INTO invitation_record
    FROM public.organization_owner_invitations AS invitation
    WHERE invitation.organization_id = NEW.organization_id
      AND invitation.id = NEW.owner_invitation_id
    FOR UPDATE;

    IF NOT FOUND
      OR invitation_record.status <> 'sent'
      OR invitation_record.expires_at IS NULL
      OR invitation_record.expires_at <= checked_at
      OR invitation_record.revoked_at IS NOT NULL
    THEN
      RAISE EXCEPTION 'owner invitation is not eligible for enrollment'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.expires_at <= checked_at OR NEW.failed_attempts >= NEW.max_attempts THEN
      RAISE EXCEPTION 'owner enrollment proof is expired or exhausted'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.user_id IS NULL THEN
      RAISE EXCEPTION 'owner enrollment requires a bound user'
        USING ERRCODE = '23514';
    END IF;

    IF user_record.status <> 'active' OR user_record.email_verified_at IS NULL THEN
      RAISE EXCEPTION 'owner enrollment requires an active verified user'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.status = 'verified'
      AND EXISTS (
        SELECT 1
        FROM public.platform_staff AS staff
        WHERE staff.user_id = NEW.user_id
      )
      AND NEW.step_up_verified_at IS NULL
    THEN
      RAISE EXCEPTION 'platform staff owner enrollment requires step-up verification'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS owner_enrollment_challenge_guard
  ON public.organization_owner_enrollment_challenges;

CREATE TRIGGER owner_enrollment_challenge_guard
BEFORE INSERT OR UPDATE
ON public.organization_owner_enrollment_challenges
FOR EACH ROW
EXECUTE FUNCTION public.guard_owner_enrollment_challenge();

CREATE OR REPLACE FUNCTION public.stamp_owner_acceptance_audit()
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

CREATE OR REPLACE FUNCTION public.guard_owner_acceptance_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  checked_at timestamptz := clock_timestamp();
  challenge_record record;
  invitation_record record;
  membership_record record;
  organization_status public.organization_status;
  user_record record;
BEGIN
  SELECT challenge.status,
         challenge.token_digest,
         challenge.user_id,
         challenge.consumed_at
  INTO challenge_record
  FROM public.organization_owner_enrollment_challenges AS challenge
  WHERE challenge.organization_id = NEW.organization_id
    AND challenge.id = NEW.enrollment_challenge_id
    AND challenge.owner_invitation_id = NEW.owner_invitation_id
  FOR SHARE;

  IF NOT FOUND
    OR challenge_record.status <> 'consumed'
    OR challenge_record.token_digest IS NOT NULL
    OR challenge_record.user_id IS DISTINCT FROM NEW.actor_user_id
    OR challenge_record.consumed_at IS NULL
    OR NEW.occurred_at < challenge_record.consumed_at
    OR NEW.occurred_at > checked_at + interval '1 second'
  THEN
    RAISE EXCEPTION 'acceptance audit is not backed by consumed enrollment proof'
      USING ERRCODE = '23514';
  END IF;

  SELECT invitation.status,
         invitation.accepted_at,
         invitation.invited_email
  INTO invitation_record
  FROM public.organization_owner_invitations AS invitation
  WHERE invitation.organization_id = NEW.organization_id
    AND invitation.id = NEW.owner_invitation_id
  FOR SHARE;

  IF NOT FOUND
    OR invitation_record.status <> 'accepted'
    OR invitation_record.accepted_at IS NULL
  THEN
    RAISE EXCEPTION 'acceptance audit requires an accepted invitation'
      USING ERRCODE = '23514';
  END IF;

  SELECT organization.status
  INTO organization_status
  FROM public.organizations AS organization
  WHERE organization.id = NEW.organization_id
  FOR SHARE;

  IF NOT FOUND OR organization_status NOT IN ('pending', 'active') THEN
    RAISE EXCEPTION 'acceptance audit organization is not eligible'
      USING ERRCODE = '23514';
  END IF;

  SELECT user_row.email, user_row.status, user_row.email_verified_at
  INTO user_record
  FROM public.users AS user_row
  WHERE user_row.id = NEW.actor_user_id
  FOR SHARE;

  IF NOT FOUND
    OR user_record.status <> 'active'
    OR user_record.email_verified_at IS NULL
    OR lower(user_record.email::text) <> lower(invitation_record.invited_email::text)
  THEN
    RAISE EXCEPTION 'acceptance audit actor is not the verified invitation recipient'
      USING ERRCODE = '23514';
  END IF;

  SELECT membership.status
  INTO membership_record
  FROM public.organization_memberships AS membership
  WHERE membership.organization_id = NEW.organization_id
    AND membership.id = NEW.organization_membership_id
    AND membership.user_id = NEW.actor_user_id
  FOR SHARE;

  IF NOT FOUND OR membership_record.status <> 'active' THEN
    RAISE EXCEPTION 'acceptance audit requires the recipient active membership'
      USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.organization_membership_roles AS assignment
    JOIN public.organization_roles AS role
      ON role.organization_id = assignment.organization_id
      AND role.id = assignment.organization_role_id
    WHERE assignment.organization_id = NEW.organization_id
      AND assignment.organization_membership_id = NEW.organization_membership_id
      AND role.key = 'owner'
      AND role.name = 'Owner'
      AND role.is_system IS TRUE
  ) THEN
    RAISE EXCEPTION 'acceptance audit requires the exact system owner assignment'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS owner_acceptance_audit_guard
  ON public.organization_owner_acceptance_audit_events;
DROP TRIGGER IF EXISTS owner_acceptance_audit_stamp
  ON public.organization_owner_acceptance_audit_events;

CREATE TRIGGER owner_acceptance_audit_guard
BEFORE INSERT
ON public.organization_owner_acceptance_audit_events
FOR EACH ROW
EXECUTE FUNCTION public.guard_owner_acceptance_audit();

CREATE TRIGGER owner_acceptance_audit_stamp
BEFORE INSERT
ON public.organization_owner_acceptance_audit_events
FOR EACH ROW
EXECUTE FUNCTION public.stamp_owner_acceptance_audit();

REVOKE ALL ON TABLE public.organization_owner_enrollment_challenges FROM PUBLIC;
REVOKE ALL ON TABLE public.organization_owner_acceptance_audit_events FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_owner_enrollment_purpose FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_owner_enrollment_status FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_owner_acceptance_audit_action FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_owner_enrollment_challenge() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_owner_acceptance_audit() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.stamp_owner_acceptance_audit() FROM PUBLIC;

COMMIT;
