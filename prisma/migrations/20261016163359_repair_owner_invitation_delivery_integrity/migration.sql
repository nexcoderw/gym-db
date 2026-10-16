BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

ALTER TABLE public.organization_owner_invitation_deliveries
  ADD CONSTRAINT organization_owner_invitation_deliveries_lifecycle_check CHECK ((
    CASE status
      WHEN 'queued' THEN next_attempt_at IS NOT NULL AND token_digest IS NOT NULL
        AND confirmed_at IS NULL AND failed_at IS NULL AND uncertain_at IS NULL
        AND provider_message_id IS NULL AND last_error_code IS NULL
      WHEN 'processing' THEN attempt_count > 0 AND next_attempt_at IS NULL
        AND token_digest IS NOT NULL AND confirmed_at IS NULL AND failed_at IS NULL
        AND uncertain_at IS NULL AND provider_message_id IS NULL AND last_error_code IS NULL
      WHEN 'confirmed' THEN attempt_count > 0 AND next_attempt_at IS NULL
        AND confirmed_at IS NOT NULL AND failed_at IS NULL AND uncertain_at IS NULL
        AND provider_message_id IS NOT NULL AND last_error_code IS NULL
        AND token_digest IS NULL AND token_erased_at IS NOT NULL
      WHEN 'failed' THEN failed_at IS NOT NULL AND last_error_code IS NOT NULL
        AND confirmed_at IS NULL AND uncertain_at IS NULL AND provider_message_id IS NULL
        AND (
          (next_attempt_at IS NULL AND token_digest IS NULL AND token_erased_at IS NOT NULL)
          OR (next_attempt_at IS NOT NULL AND token_digest IS NOT NULL
            AND attempt_count > 0 AND attempt_count < max_attempts
            AND last_error_code IN ('PROVIDER_RATE_LIMITED', 'PROVIDER_REJECTED_RETRYABLE'))
        )
      WHEN 'uncertain' THEN attempt_count > 0 AND next_attempt_at IS NULL
        AND confirmed_at IS NULL AND failed_at IS NULL AND uncertain_at IS NOT NULL
        AND last_error_code IS NOT NULL
      ELSE false
    END
  ) IS TRUE),
  ADD CONSTRAINT organization_owner_invitation_deliveries_lease_check CHECK ((
    CASE WHEN status = 'processing' THEN
      lease_acquired_at IS NOT NULL AND lease_expires_at IS NOT NULL AND claimed_by IS NOT NULL
      AND lease_expires_at > lease_acquired_at
      AND lease_expires_at <= lease_acquired_at + interval '5 minutes'
      AND lease_expires_at <= token_expires_at
    ELSE lease_acquired_at IS NULL AND lease_expires_at IS NULL AND claimed_by IS NULL END
  ) IS TRUE),
  ADD CONSTRAINT organization_owner_invitation_deliveries_retry_check CHECK (
    max_attempts BETWEEN 1 AND 10 AND attempt_count BETWEEN 0 AND max_attempts
  ),
  ADD CONSTRAINT organization_owner_invitation_deliveries_token_material_check CHECK ((
    (num_nonnulls(token_digest, token_ciphertext, token_initialization_vector,
      token_authentication_tag, token_encryption_key_id, token_encryption_version) = 0
      AND token_erased_at IS NOT NULL)
    OR (num_nonnulls(token_digest, token_ciphertext, token_initialization_vector,
      token_authentication_tag, token_encryption_key_id, token_encryption_version) = 6
      AND token_erased_at IS NULL
      AND token_digest COLLATE "C" ~ '^[0-9a-f]{64}$'
      AND octet_length(token_ciphertext) BETWEEN 32 AND 4096
      AND octet_length(token_initialization_vector) = 12
      AND octet_length(token_authentication_tag) = 16
      AND char_length(token_encryption_key_id) BETWEEN 1 AND 120
      AND token_encryption_key_id COLLATE "C" !~ '[^A-Za-z0-9._:-]'
      AND token_encryption_version = 1)
  ) IS TRUE),
  ADD CONSTRAINT organization_owner_invitation_deliveries_timestamp_order_check CHECK ((
    updated_at >= created_at AND token_expires_at > created_at
    AND token_expires_at <= created_at + interval '7 days'
    AND (next_attempt_at IS NULL OR (next_attempt_at >= created_at
      AND next_attempt_at < token_expires_at
      AND (failed_at IS NULL OR next_attempt_at > failed_at)))
    AND (lease_acquired_at IS NULL OR lease_acquired_at >= created_at)
    AND (confirmed_at IS NULL OR (confirmed_at >= created_at AND confirmed_at < token_expires_at))
    AND (failed_at IS NULL OR failed_at >= created_at)
    AND (uncertain_at IS NULL OR uncertain_at >= created_at)
    AND (token_erased_at IS NULL OR token_erased_at >= created_at)
  ) IS TRUE),
  ADD CONSTRAINT organization_owner_invitation_deliveries_bounded_text_check CHECK (
    char_length(provider_idempotency_key) BETWEEN 1 AND 128
    AND provider_idempotency_key COLLATE "C" !~ '[^A-Za-z0-9._:/-]'
    AND (provider_message_id IS NULL OR (char_length(provider_message_id) BETWEEN 1 AND 128
      AND provider_message_id COLLATE "C" !~ '[^A-Za-z0-9._:-]'))
    AND (claimed_by IS NULL OR (char_length(claimed_by) BETWEEN 1 AND 120
      AND claimed_by COLLATE "C" !~ '[^A-Za-z0-9._:-]'))
    AND (last_error_code IS NULL OR (char_length(last_error_code) BETWEEN 1 AND 63
      AND last_error_code COLLATE "C" ~ '^[A-Z][A-Z0-9_]*$'))
  );

CREATE FUNCTION public.guard_owner_invitation_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  invitation record;
  organization_status public.organization_status;
  checked_at timestamptz := clock_timestamp();
  erasing boolean;
BEGIN
  -- Parent locks serialize worker claims with invitation revocation and lifecycle restrictions.
  SELECT status INTO organization_status
  FROM public.organizations
  WHERE id = NEW.organization_id
  FOR SHARE;

  IF NOT FOUND THEN
    IF TG_OP = 'INSERT' THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'immutable delivery parent'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
  END IF;

  SELECT status, token_digest, expires_at, sent_at
  INTO invitation
  FROM public.organization_owner_invitations
  WHERE organization_id = NEW.organization_id AND id = NEW.owner_invitation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    IF TG_OP = 'INSERT' THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'immutable delivery parent'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
  END IF;

  checked_at := clock_timestamp();

  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'queued' OR NEW.attempt_count <> 0
      OR invitation.status <> 'pending_delivery'
      OR organization_status NOT IN ('pending', 'active')
      OR NEW.token_expires_at <= checked_at
    THEN
      RAISE EXCEPTION 'invalid delivery reservation'
        USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
    END IF;
    RETURN NEW;
  END IF;

  erasing := NEW.token_digest IS NULL
    AND NEW.token_ciphertext IS NULL
    AND NEW.token_initialization_vector IS NULL
    AND NEW.token_authentication_tag IS NULL
    AND NEW.token_encryption_key_id IS NULL
    AND NEW.token_encryption_version IS NULL
    AND NEW.token_erased_at IS NOT NULL
    AND (NEW.status IN ('confirmed', 'uncertain')
      OR (NEW.status = 'failed' AND NEW.next_attempt_at IS NULL));

  IF NEW.id IS DISTINCT FROM OLD.id
    OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
    OR NEW.owner_invitation_id IS DISTINCT FROM OLD.owner_invitation_id
    OR NEW.requested_by_platform_staff_id IS DISTINCT FROM OLD.requested_by_platform_staff_id
    OR NEW.provider_idempotency_key IS DISTINCT FROM OLD.provider_idempotency_key
    OR NEW.token_expires_at IS DISTINCT FROM OLD.token_expires_at
    OR NEW.max_attempts IS DISTINCT FROM OLD.max_attempts
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
    OR NEW.attempt_count < OLD.attempt_count
    OR (OLD.provider_message_id IS NOT NULL
      AND NEW.provider_message_id IS DISTINCT FROM OLD.provider_message_id)
    OR (OLD.token_erased_at IS NOT NULL
      AND NEW.token_erased_at IS DISTINCT FROM OLD.token_erased_at)
    OR ((NEW.token_digest IS DISTINCT FROM OLD.token_digest
      OR NEW.token_ciphertext IS DISTINCT FROM OLD.token_ciphertext
      OR NEW.token_initialization_vector IS DISTINCT FROM OLD.token_initialization_vector
      OR NEW.token_authentication_tag IS DISTINCT FROM OLD.token_authentication_tag
      OR NEW.token_encryption_key_id IS DISTINCT FROM OLD.token_encryption_key_id
      OR NEW.token_encryption_version IS DISTINCT FROM OLD.token_encryption_version) AND NOT erasing)
    OR OLD.status = 'confirmed'
    OR (OLD.status = 'failed' AND OLD.next_attempt_at IS NULL)
  THEN
    RAISE EXCEPTION 'immutable delivery reservation'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
  END IF;

  IF OLD.status = 'uncertain' AND NEW.status = 'uncertain' AND (
    OLD.token_digest IS NULL
    OR NEW.uncertain_at IS DISTINCT FROM OLD.uncertain_at
    OR NEW.last_error_code IS DISTINCT FROM OLD.last_error_code
    OR NEW.provider_message_id IS DISTINCT FROM OLD.provider_message_id
  ) THEN
    RAISE EXCEPTION 'uncertain cleanup must preserve outcome metadata'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
  END IF;

  IF NEW.status = 'processing' THEN
    IF OLD.status NOT IN ('queued', 'failed')
      OR OLD.next_attempt_at IS NULL
      OR OLD.next_attempt_at > checked_at
      OR OLD.attempt_count >= OLD.max_attempts
      OR OLD.token_digest IS NULL
      OR NEW.token_expires_at <= checked_at
      OR invitation.status <> 'pending_delivery'
      OR organization_status NOT IN ('pending', 'active')
      OR NEW.attempt_count <> OLD.attempt_count + 1
      OR NEW.lease_expires_at <= checked_at
      OR NEW.lease_acquired_at > checked_at + interval '1 second'
    THEN
      RAISE EXCEPTION 'delivery cannot be claimed'
        USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
    END IF;
  ELSE
    IF NEW.attempt_count <> OLD.attempt_count OR NOT (
      (OLD.status = 'queued' AND NEW.status = 'failed' AND NEW.next_attempt_at IS NULL)
      OR (OLD.status = 'processing' AND NEW.status IN ('confirmed', 'failed', 'uncertain'))
      OR (OLD.status = 'failed' AND NEW.status = 'failed' AND NEW.next_attempt_at IS NULL)
      OR (OLD.status = 'uncertain' AND NEW.status = 'confirmed')
      OR (OLD.status = 'uncertain' AND NEW.status = 'failed'
        AND NEW.next_attempt_at IS NULL AND erasing)
      OR (OLD.status = 'uncertain' AND NEW.status = 'uncertain' AND erasing)
    ) THEN
      RAISE EXCEPTION 'invalid delivery transition'
        USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
    END IF;

    IF OLD.status = 'processing'
      AND NEW.status <> 'uncertain'
      AND OLD.lease_expires_at <= checked_at
    THEN
      RAISE EXCEPTION 'expired delivery lease requires reconciliation'
        USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
    END IF;
  END IF;

  IF NEW.next_attempt_at IS NOT NULL AND NEW.status = 'failed' AND (
    invitation.status <> 'pending_delivery'
    OR organization_status NOT IN ('pending', 'active')
    OR NEW.token_expires_at <= checked_at
  ) THEN
    RAISE EXCEPTION 'ineligible delivery cannot retry'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
  END IF;

  IF NEW.status = 'confirmed' AND (
    OLD.token_digest IS NULL
    OR invitation.status <> 'sent'
    OR organization_status NOT IN ('pending', 'active')
    OR NEW.token_expires_at <= checked_at
    OR invitation.token_digest IS DISTINCT FROM OLD.token_digest
    OR invitation.expires_at IS DISTINCT FROM OLD.token_expires_at
    OR invitation.sent_at IS DISTINCT FROM NEW.confirmed_at
  ) THEN
    RAISE EXCEPTION 'delivery confirmation requires matching sent invitation'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER owner_invitation_delivery_guard
BEFORE INSERT OR UPDATE ON public.organization_owner_invitation_deliveries
FOR EACH ROW EXECUTE FUNCTION public.guard_owner_invitation_delivery();

CREATE OR REPLACE FUNCTION public.guard_organization_owner_invitation_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
    OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
    OR NEW.invited_email IS DISTINCT FROM OLD.invited_email
    OR NEW.invited_by_platform_staff_id IS DISTINCT FROM OLD.invited_by_platform_staff_id
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
    OR (OLD.status IN ('revoked', 'accepted') AND NEW IS DISTINCT FROM OLD)
    OR (OLD.status = 'sent' AND NEW.status = 'pending_delivery')
    OR (OLD.status = 'pending_delivery' AND NEW.status = 'accepted')
    OR (OLD.status = 'sent' AND NEW.status = 'sent' AND (
      NEW.token_digest IS DISTINCT FROM OLD.token_digest
      OR NEW.expires_at IS DISTINCT FROM OLD.expires_at
      OR NEW.sent_at IS DISTINCT FROM OLD.sent_at))
  THEN
    RAISE EXCEPTION 'invalid invitation identity or lifecycle change'
      USING ERRCODE = '23514', CONSTRAINT = 'organization_owner_invitation_identity_guard';
  END IF;
  RETURN NEW;
END;
$function$;

ALTER TABLE public.organization_ownership_audit_events
  DROP CONSTRAINT organization_ownership_audit_events_metadata_check,
  ADD CONSTRAINT organization_ownership_audit_events_metadata_check CHECK ((
    CASE action
      WHEN 'invitation_created' THEN previous_invitation_status IS NULL
        AND resulting_invitation_status = 'pending_delivery'
      WHEN 'invitation_revoked' THEN previous_invitation_status IN ('pending_delivery', 'sent')
        AND resulting_invitation_status = 'revoked'
      WHEN 'invitation_delivery_queued' THEN previous_invitation_status = 'pending_delivery'
        AND resulting_invitation_status = 'pending_delivery'
      ELSE false
    END
  ) IS TRUE);

REVOKE ALL ON TABLE
  public.organization_owner_invitation_deliveries,
  public.organization_owner_invitations,
  public.organization_ownership_audit_events
FROM PUBLIC;

REVOKE ALL ON TYPE public.organization_owner_invitation_delivery_status FROM PUBLIC;

REVOKE ALL ON FUNCTION
  public.guard_owner_invitation_delivery(),
  public.guard_organization_owner_invitation_identity()
FROM PUBLIC;

COMMIT;
