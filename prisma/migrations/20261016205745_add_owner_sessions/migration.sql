BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

-- CreateEnum
CREATE TYPE "owner_session_assurance" AS ENUM ('aal1', 'aal2');

-- CreateTable
CREATE TABLE "owner_sessions" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "token_digest" VARCHAR(128) NOT NULL,
    "assurance" "owner_session_assurance" NOT NULL DEFAULT 'aal1',
    "authenticated_at" TIMESTAMPTZ(6) NOT NULL,
    "mfa_verified_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_activity_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "idle_expires_at" TIMESTAMPTZ(6) NOT NULL,
    "absolute_expires_at" TIMESTAMPTZ(6) NOT NULL,
    "revoked_at" TIMESTAMPTZ(6),

    CONSTRAINT "owner_sessions_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "owner_sessions_token_digest_check" CHECK ((
      token_digest COLLATE "C" ~ '^[0-9a-f]{64}$'
    ) IS TRUE),
    CONSTRAINT "owner_sessions_assurance_check" CHECK ((
      CASE assurance
        WHEN 'aal1' THEN mfa_verified_at IS NULL
        WHEN 'aal2' THEN mfa_verified_at IS NOT NULL
        ELSE false
      END
    ) IS TRUE),
    CONSTRAINT "owner_sessions_timestamp_order_check" CHECK ((
      authenticated_at <= created_at
      AND (mfa_verified_at IS NULL OR (
        mfa_verified_at >= authenticated_at
        AND mfa_verified_at <= created_at
      ))
      AND last_activity_at >= created_at
      AND idle_expires_at > last_activity_at
      AND idle_expires_at <= last_activity_at + interval '24 hours'
      AND absolute_expires_at > created_at
      AND absolute_expires_at <= created_at + interval '30 days'
      AND idle_expires_at <= absolute_expires_at
      AND (revoked_at IS NULL OR revoked_at >= created_at)
    ) IS TRUE)
);

-- CreateIndex
CREATE UNIQUE INDEX "owner_sessions_token_digest_key" ON "owner_sessions"("token_digest");

-- CreateIndex
CREATE INDEX "owner_sessions_user_active_idx" ON "owner_sessions"("user_id", "revoked_at", "idle_expires_at", "absolute_expires_at");

-- CreateIndex
CREATE INDEX "owner_sessions_idle_expiry_idx" ON "owner_sessions"("idle_expires_at");

-- CreateIndex
CREATE INDEX "owner_sessions_absolute_expiry_idx" ON "owner_sessions"("absolute_expires_at");

-- AddForeignKey
ALTER TABLE "owner_sessions" ADD CONSTRAINT "owner_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

CREATE FUNCTION public.guard_owner_session()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  current_user_status public.user_status;
BEGIN
  SELECT account.status
  INTO current_user_status
  FROM public.users AS account
  WHERE account.id = NEW.user_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'owner session user does not exist'
      USING ERRCODE = '23503', CONSTRAINT = 'owner_sessions_user_id_fkey';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF current_user_status <> 'active' THEN
      RAISE EXCEPTION 'owner sessions require an active user'
        USING ERRCODE = '23514', CONSTRAINT = 'owner_session_guard';
    END IF;

    RETURN NEW;
  END IF;

  IF OLD.revoked_at IS NOT NULL AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'revoked owner sessions are immutable'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_session_guard';
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
    OR NEW.user_id IS DISTINCT FROM OLD.user_id
    OR NEW.token_digest IS DISTINCT FROM OLD.token_digest
    OR NEW.assurance IS DISTINCT FROM OLD.assurance
    OR NEW.authenticated_at IS DISTINCT FROM OLD.authenticated_at
    OR NEW.mfa_verified_at IS DISTINCT FROM OLD.mfa_verified_at
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
    OR NEW.absolute_expires_at IS DISTINCT FROM OLD.absolute_expires_at
  THEN
    RAISE EXCEPTION 'owner session identity and authentication evidence are immutable'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_session_guard';
  END IF;

  IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL THEN
    IF NEW.last_activity_at IS DISTINCT FROM OLD.last_activity_at
      OR NEW.idle_expires_at IS DISTINCT FROM OLD.idle_expires_at
    THEN
      RAISE EXCEPTION 'owner session revocation cannot refresh activity'
        USING ERRCODE = '23514', CONSTRAINT = 'owner_session_guard';
    END IF;

    RETURN NEW;
  END IF;

  IF NEW.revoked_at IS DISTINCT FROM OLD.revoked_at THEN
    RAISE EXCEPTION 'owner session revocation is one-way'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_session_guard';
  END IF;

  IF NEW.last_activity_at <= OLD.last_activity_at
    OR NEW.idle_expires_at <= OLD.idle_expires_at
  THEN
    RAISE EXCEPTION 'owner session activity and idle expiry must advance together'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_session_guard';
  END IF;

  IF current_user_status <> 'active' THEN
    RAISE EXCEPTION 'inactive users cannot refresh owner sessions'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_session_guard';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER owner_session_guard
BEFORE INSERT OR UPDATE ON public.owner_sessions
FOR EACH ROW
EXECUTE FUNCTION public.guard_owner_session();

REVOKE ALL ON TABLE public.owner_sessions FROM PUBLIC;
REVOKE ALL ON TYPE public.owner_session_assurance FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_owner_session() FROM PUBLIC;

COMMIT;
