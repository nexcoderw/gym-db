-- Additive migration. Apply to the verified disposable test database first.
-- btree_gist supplies UUID equality for concurrency-safe date-range exclusion.
-- The migration role must be permitted to install this extension.
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- CreateEnum
CREATE TYPE "member_period_unit" AS ENUM ('days', 'weeks', 'months', 'years');

-- CreateTable
CREATE TABLE "organization_members" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "normalized_name" VARCHAR(160) NOT NULL,
    "email" CITEXT,
    "phone_number" VARCHAR(16) NOT NULL,
    "archived_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "organization_members_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organization_member_subscriptions" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "member_id" UUID NOT NULL,
    "membership_plan_id" UUID NOT NULL,
    "plan_name" VARCHAR(120) NOT NULL,
    "price_rwf" BIGINT NOT NULL,
    "period_unit" "member_period_unit" NOT NULL,
    "period_count" INTEGER NOT NULL,
    "start_date" DATE NOT NULL,
    "end_date" DATE NOT NULL,
    "idempotency_key" UUID NOT NULL,
    "request_fingerprint" VARCHAR(64) NOT NULL,
    "created_by_user_id" UUID NOT NULL,
    "cancelled_at" TIMESTAMPTZ(6),
    "cancelled_by_user_id" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "member_subscriptions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "organization_members_org_archive_created_idx" ON "organization_members"("organization_id", "archived_at", "created_at" DESC, "id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_members_org_name_key" ON "organization_members"("organization_id", "normalized_name");

-- CreateIndex
CREATE UNIQUE INDEX "organization_members_org_phone_key" ON "organization_members"("organization_id", "phone_number");

-- CreateIndex
CREATE UNIQUE INDEX "organization_members_org_id_key" ON "organization_members"("organization_id", "id");

-- CreateIndex
CREATE INDEX "member_subscriptions_org_member_created_idx" ON "organization_member_subscriptions"("organization_id", "member_id", "created_at" DESC, "id");

-- CreateIndex
CREATE INDEX "member_subscriptions_org_member_dates_idx" ON "organization_member_subscriptions"("organization_id", "member_id", "cancelled_at", "start_date", "end_date");

-- CreateIndex
CREATE INDEX "member_subscriptions_org_plan_idx" ON "organization_member_subscriptions"("organization_id", "membership_plan_id");

-- CreateIndex
CREATE INDEX "member_subscriptions_org_expiry_idx" ON "organization_member_subscriptions"("organization_id", "end_date", "id");

-- CreateIndex
CREATE UNIQUE INDEX "member_subscriptions_org_idempotency_key" ON "organization_member_subscriptions"("organization_id", "idempotency_key");

-- AddForeignKey
ALTER TABLE "organization_members" ADD CONSTRAINT "organization_members_org_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_member_subscriptions" ADD CONSTRAINT "member_subscriptions_org_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_member_subscriptions" ADD CONSTRAINT "member_subscriptions_member_fkey" FOREIGN KEY ("organization_id", "member_id") REFERENCES "organization_members"("organization_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_member_subscriptions" ADD CONSTRAINT "member_subscriptions_plan_fkey" FOREIGN KEY ("organization_id", "membership_plan_id") REFERENCES "organization_membership_plans"("organization_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_member_subscriptions" ADD CONSTRAINT "member_subscriptions_creator_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_member_subscriptions" ADD CONSTRAINT "member_subscriptions_canceller_fkey" FOREIGN KEY ("cancelled_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE public.organization_members
    ADD CONSTRAINT members_name_nonblank_check
        CHECK (btrim(name) <> '' AND btrim(normalized_name) <> ''),
    ADD CONSTRAINT members_phone_format_check
        CHECK (phone_number COLLATE "C" ~ '^\+[1-9][0-9]{7,14}$'),
    ADD CONSTRAINT members_email_nonblank_check
        CHECK (email IS NULL OR btrim(email::text) <> ''),
    ADD CONSTRAINT members_timestamp_order_check
        CHECK (updated_at >= created_at AND (archived_at IS NULL OR archived_at >= created_at));

ALTER TABLE public.organization_member_subscriptions
    ADD CONSTRAINT member_subscriptions_snapshot_check
        CHECK (btrim(plan_name) <> '' AND price_rwf BETWEEN 0 AND 1000000000),
    ADD CONSTRAINT member_subscriptions_fingerprint_check
        CHECK (request_fingerprint COLLATE "C" ~ '^[0-9a-f]{64}$'),
    ADD CONSTRAINT member_subscriptions_period_check
        CHECK (period_count >= 1 AND period_count <= CASE period_unit
            WHEN 'days' THEN 3650 WHEN 'weeks' THEN 520
            WHEN 'months' THEN 120 WHEN 'years' THEN 10 END),
    -- Calendar anniversaries clamp to month end; stored end dates are inclusive.
    ADD CONSTRAINT member_subscriptions_end_date_check
        CHECK (start_date BETWEEN DATE '2000-01-01' AND DATE '2099-12-31'
            AND end_date >= start_date
            AND end_date = (start_date + CASE period_unit
                WHEN 'days' THEN make_interval(days => period_count)
                WHEN 'weeks' THEN make_interval(days => period_count * 7)
                WHEN 'months' THEN make_interval(months => period_count)
                WHEN 'years' THEN make_interval(years => period_count)
            END)::date - 1),
    ADD CONSTRAINT member_subscriptions_cancellation_check
        CHECK ((cancelled_at IS NULL) = (cancelled_by_user_id IS NULL)
            AND (cancelled_at IS NULL OR cancelled_at >= created_at)),
    ADD CONSTRAINT member_subscriptions_timestamp_order_check
        CHECK (updated_at >= created_at),
    -- Unlike a SELECT-based trigger, this also rejects concurrent overlapping inserts.
    ADD CONSTRAINT member_subscriptions_no_overlap
        EXCLUDE USING gist (
            organization_id WITH =,
            member_id WITH =,
            daterange(start_date, end_date, '[]') WITH &&
        ) WHERE (cancelled_at IS NULL);

CREATE FUNCTION public.guard_member_subscription_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
    IF ROW(NEW.id, NEW.organization_id, NEW.member_id, NEW.membership_plan_id,
        NEW.plan_name, NEW.price_rwf, NEW.period_unit, NEW.period_count,
        NEW.start_date, NEW.end_date, NEW.idempotency_key, NEW.request_fingerprint,
        NEW.created_by_user_id, NEW.created_at)
        IS DISTINCT FROM
        ROW(OLD.id, OLD.organization_id, OLD.member_id, OLD.membership_plan_id,
        OLD.plan_name, OLD.price_rwf, OLD.period_unit, OLD.period_count,
        OLD.start_date, OLD.end_date, OLD.idempotency_key, OLD.request_fingerprint,
        OLD.created_by_user_id, OLD.created_at)
        OR (OLD.cancelled_at IS NOT NULL AND ROW(NEW.cancelled_at, NEW.cancelled_by_user_id)
            IS DISTINCT FROM ROW(OLD.cancelled_at, OLD.cancelled_by_user_id)) THEN
        RAISE EXCEPTION 'subscription terms and completed cancellation are immutable'
            USING ERRCODE = '23514', CONSTRAINT = 'member_subscription_history_guard';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER member_subscription_history_guard
BEFORE UPDATE ON public.organization_member_subscriptions
FOR EACH ROW EXECUTE FUNCTION public.guard_member_subscription_history();

REVOKE ALL ON TABLE public.organization_members FROM PUBLIC;
REVOKE ALL ON TABLE public.organization_member_subscriptions FROM PUBLIC;
REVOKE ALL ON TYPE public.member_period_unit FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_member_subscription_history() FROM PUBLIC;

COMMIT;
