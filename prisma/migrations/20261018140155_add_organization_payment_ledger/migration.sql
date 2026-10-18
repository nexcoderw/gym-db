-- Additive payment-ledger migration. Apply to the verified disposable test database first.
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

-- CreateEnum
CREATE TYPE "organization_payment_method" AS ENUM ('cash', 'mobile_money', 'bank_transfer', 'card', 'other');

-- CreateEnum
CREATE TYPE "organization_payment_status" AS ENUM ('pending', 'confirmed', 'failed', 'voided', 'partially_refunded', 'refunded');

-- CreateEnum
CREATE TYPE "organization_payment_refund_status" AS ENUM ('pending', 'confirmed', 'failed');

-- CreateEnum
CREATE TYPE "organization_payment_audit_action" AS ENUM ('payment_recorded', 'payment_voided', 'refund_recorded');

-- CreateTable
CREATE TABLE "organization_payments" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "member_id" UUID NOT NULL,
    "receipt_number" VARCHAR(48) NOT NULL,
    "amount_rwf" BIGINT NOT NULL,
    "method" "organization_payment_method" NOT NULL,
    "status" "organization_payment_status" NOT NULL DEFAULT 'pending',
    "provider_reference" VARCHAR(120),
    "note" VARCHAR(500),
    "occurred_at" TIMESTAMPTZ(6) NOT NULL,
    "confirmed_at" TIMESTAMPTZ(6),
    "failed_at" TIMESTAMPTZ(6),
    "voided_at" TIMESTAMPTZ(6),
    "void_reason" VARCHAR(500),
    "idempotency_key" UUID NOT NULL,
    "request_fingerprint" VARCHAR(64) NOT NULL,
    "recorded_by_user_id" UUID NOT NULL,
    "voided_by_user_id" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "organization_payments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organization_payment_allocations" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "payment_id" UUID NOT NULL,
    "member_id" UUID NOT NULL,
    "member_subscription_id" UUID NOT NULL,
    "amount_rwf" BIGINT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "organization_payment_allocations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organization_payment_refunds" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "payment_id" UUID NOT NULL,
    "member_id" UUID NOT NULL,
    "amount_rwf" BIGINT NOT NULL,
    "status" "organization_payment_refund_status" NOT NULL DEFAULT 'pending',
    "reason" VARCHAR(500) NOT NULL,
    "provider_reference" VARCHAR(120),
    "idempotency_key" UUID NOT NULL,
    "request_fingerprint" VARCHAR(64) NOT NULL,
    "requested_by_user_id" UUID NOT NULL,
    "confirmed_at" TIMESTAMPTZ(6),
    "failed_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "organization_payment_refunds_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organization_payment_audit_events" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "payment_id" UUID NOT NULL,
    "refund_id" UUID,
    "actor_user_id" UUID NOT NULL,
    "action" "organization_payment_audit_action" NOT NULL,
    "request_id" VARCHAR(128) NOT NULL,
    "idempotency_key" UUID NOT NULL,
    "request_fingerprint" VARCHAR(64) NOT NULL,
    "previous_status" "organization_payment_status",
    "resulting_status" "organization_payment_status" NOT NULL,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL,
    "recorded_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "organization_payment_audit_events_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "organization_payments_org_status_time_idx" ON "organization_payments"("organization_id", "status", "occurred_at" DESC, "id");

-- CreateIndex
CREATE INDEX "organization_payments_org_method_time_idx" ON "organization_payments"("organization_id", "method", "occurred_at" DESC, "id");

-- CreateIndex
CREATE INDEX "organization_payments_org_member_time_idx" ON "organization_payments"("organization_id", "member_id", "occurred_at" DESC, "id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_payments_org_id_key" ON "organization_payments"("organization_id", "id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_payments_org_id_member_key" ON "organization_payments"("organization_id", "id", "member_id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_payments_org_receipt_key" ON "organization_payments"("organization_id", "receipt_number");

-- CreateIndex
CREATE UNIQUE INDEX "organization_payments_org_idempotency_key" ON "organization_payments"("organization_id", "idempotency_key");

-- CreateIndex
CREATE UNIQUE INDEX "organization_payments_org_provider_ref_key" ON "organization_payments"("organization_id", "method", "provider_reference");

-- CreateIndex
CREATE INDEX "payment_allocations_org_subscription_idx" ON "organization_payment_allocations"("organization_id", "member_subscription_id", "created_at" DESC, "id");

-- CreateIndex
CREATE UNIQUE INDEX "payment_allocations_org_payment_subscription_key" ON "organization_payment_allocations"("organization_id", "payment_id", "member_subscription_id");

-- CreateIndex
CREATE INDEX "payment_refunds_org_payment_time_idx" ON "organization_payment_refunds"("organization_id", "payment_id", "created_at" DESC, "id");

-- CreateIndex
CREATE INDEX "payment_refunds_org_status_time_idx" ON "organization_payment_refunds"("organization_id", "status", "created_at" DESC, "id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_payment_refunds_org_id_key" ON "organization_payment_refunds"("organization_id", "id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_payment_refunds_org_idempotency_key" ON "organization_payment_refunds"("organization_id", "idempotency_key");

-- CreateIndex
CREATE UNIQUE INDEX "organization_payment_refunds_org_provider_ref_key" ON "organization_payment_refunds"("organization_id", "provider_reference");

-- CreateIndex
CREATE INDEX "payment_audit_events_org_payment_time_idx" ON "organization_payment_audit_events"("organization_id", "payment_id", "recorded_at" DESC, "id");

-- CreateIndex
CREATE INDEX "payment_audit_events_org_actor_time_idx" ON "organization_payment_audit_events"("organization_id", "actor_user_id", "recorded_at" DESC, "id");

-- CreateIndex
CREATE INDEX "payment_audit_events_request_idx" ON "organization_payment_audit_events"("request_id");

-- CreateIndex
CREATE UNIQUE INDEX "payment_audit_events_org_idempotency_key" ON "organization_payment_audit_events"("organization_id", "idempotency_key");

-- CreateIndex
CREATE UNIQUE INDEX "member_subscriptions_org_id_member_key" ON "organization_member_subscriptions"("organization_id", "id", "member_id");

-- AddForeignKey
ALTER TABLE "organization_payments" ADD CONSTRAINT "organization_payments_org_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payments" ADD CONSTRAINT "organization_payments_member_fkey" FOREIGN KEY ("organization_id", "member_id") REFERENCES "organization_members"("organization_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payments" ADD CONSTRAINT "organization_payments_recorder_fkey" FOREIGN KEY ("recorded_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payments" ADD CONSTRAINT "organization_payments_voider_fkey" FOREIGN KEY ("voided_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payment_allocations" ADD CONSTRAINT "payment_allocations_org_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payment_allocations" ADD CONSTRAINT "payment_allocations_payment_fkey" FOREIGN KEY ("organization_id", "payment_id", "member_id") REFERENCES "organization_payments"("organization_id", "id", "member_id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payment_allocations" ADD CONSTRAINT "payment_allocations_subscription_fkey" FOREIGN KEY ("organization_id", "member_subscription_id", "member_id") REFERENCES "organization_member_subscriptions"("organization_id", "id", "member_id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payment_refunds" ADD CONSTRAINT "payment_refunds_org_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payment_refunds" ADD CONSTRAINT "payment_refunds_payment_fkey" FOREIGN KEY ("organization_id", "payment_id", "member_id") REFERENCES "organization_payments"("organization_id", "id", "member_id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payment_refunds" ADD CONSTRAINT "payment_refunds_requester_fkey" FOREIGN KEY ("requested_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payment_audit_events" ADD CONSTRAINT "payment_audit_events_org_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payment_audit_events" ADD CONSTRAINT "payment_audit_events_payment_fkey" FOREIGN KEY ("organization_id", "payment_id") REFERENCES "organization_payments"("organization_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payment_audit_events" ADD CONSTRAINT "payment_audit_events_refund_fkey" FOREIGN KEY ("organization_id", "refund_id") REFERENCES "organization_payment_refunds"("organization_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_payment_audit_events" ADD CONSTRAINT "payment_audit_events_actor_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE public.organization_payments
    ADD CONSTRAINT payments_receipt_format_check
        CHECK (receipt_number COLLATE "C" ~ '^PAY-[0-9]{8}-[0-9A-F]{8}$'),
    ADD CONSTRAINT payments_amount_range_check
        CHECK (amount_rwf BETWEEN 1 AND 1000000000),
    ADD CONSTRAINT payments_fingerprint_check
        CHECK (request_fingerprint COLLATE "C" ~ '^[0-9a-f]{64}$'),
    ADD CONSTRAINT payments_provider_reference_check
        CHECK ((method = 'cash' AND provider_reference IS NULL)
            OR (method <> 'cash' AND provider_reference IS NOT NULL
                AND btrim(provider_reference) <> '')),
    ADD CONSTRAINT payments_note_nonblank_check
        CHECK (note IS NULL OR btrim(note) <> ''),
    ADD CONSTRAINT payments_occurred_at_check
        CHECK (occurred_at >= TIMESTAMPTZ '2000-01-01 00:00:00+00'
            AND occurred_at <= created_at + INTERVAL '5 minutes'),
    ADD CONSTRAINT payments_timestamp_order_check
        CHECK (updated_at >= created_at
            AND (confirmed_at IS NULL OR confirmed_at >= created_at)
            AND (failed_at IS NULL OR failed_at >= created_at)
            AND (voided_at IS NULL OR voided_at >= created_at)),
    ADD CONSTRAINT payments_lifecycle_check
        CHECK (CASE status
            WHEN 'pending' THEN confirmed_at IS NULL AND failed_at IS NULL
                AND voided_at IS NULL AND voided_by_user_id IS NULL AND void_reason IS NULL
            WHEN 'confirmed' THEN confirmed_at IS NOT NULL AND failed_at IS NULL
                AND voided_at IS NULL AND voided_by_user_id IS NULL AND void_reason IS NULL
            WHEN 'failed' THEN confirmed_at IS NULL AND failed_at IS NOT NULL
                AND voided_at IS NULL AND voided_by_user_id IS NULL AND void_reason IS NULL
            WHEN 'voided' THEN failed_at IS NULL AND voided_at IS NOT NULL
                AND voided_by_user_id IS NOT NULL AND btrim(void_reason) <> ''
            WHEN 'partially_refunded' THEN confirmed_at IS NOT NULL AND failed_at IS NULL
                AND voided_at IS NULL AND voided_by_user_id IS NULL AND void_reason IS NULL
            WHEN 'refunded' THEN confirmed_at IS NOT NULL AND failed_at IS NULL
                AND voided_at IS NULL AND voided_by_user_id IS NULL AND void_reason IS NULL
        END);

ALTER TABLE public.organization_payment_allocations
    ADD CONSTRAINT payment_allocations_amount_range_check
        CHECK (amount_rwf BETWEEN 1 AND 1000000000);

ALTER TABLE public.organization_payment_refunds
    ADD CONSTRAINT payment_refunds_amount_range_check
        CHECK (amount_rwf BETWEEN 1 AND 1000000000),
    ADD CONSTRAINT payment_refunds_reason_nonblank_check
        CHECK (btrim(reason) <> ''),
    ADD CONSTRAINT payment_refunds_provider_reference_check
        CHECK (provider_reference IS NULL OR btrim(provider_reference) <> ''),
    ADD CONSTRAINT payment_refunds_fingerprint_check
        CHECK (request_fingerprint COLLATE "C" ~ '^[0-9a-f]{64}$'),
    ADD CONSTRAINT payment_refunds_timestamp_order_check
        CHECK (updated_at >= created_at
            AND (confirmed_at IS NULL OR confirmed_at >= created_at)
            AND (failed_at IS NULL OR failed_at >= created_at)),
    ADD CONSTRAINT payment_refunds_lifecycle_check
        CHECK (CASE status
            WHEN 'pending' THEN confirmed_at IS NULL AND failed_at IS NULL
            WHEN 'confirmed' THEN confirmed_at IS NOT NULL AND failed_at IS NULL
            WHEN 'failed' THEN confirmed_at IS NULL AND failed_at IS NOT NULL
        END);

ALTER TABLE public.organization_payment_audit_events
    ADD CONSTRAINT payment_audit_request_id_nonblank_check
        CHECK (btrim(request_id) <> ''),
    ADD CONSTRAINT payment_audit_fingerprint_check
        CHECK (request_fingerprint COLLATE "C" ~ '^[0-9a-f]{64}$'),
    ADD CONSTRAINT payment_audit_timestamp_order_check
        CHECK (recorded_at >= occurred_at),
    ADD CONSTRAINT payment_audit_action_check
        CHECK (CASE action
            WHEN 'payment_recorded' THEN refund_id IS NULL AND previous_status IS NULL
                AND resulting_status IN ('pending', 'confirmed')
            WHEN 'payment_voided' THEN refund_id IS NULL
                AND previous_status IN ('pending', 'confirmed') AND resulting_status = 'voided'
            WHEN 'refund_recorded' THEN refund_id IS NOT NULL
                AND previous_status IN ('confirmed', 'partially_refunded')
                AND resulting_status IN ('partially_refunded', 'refunded')
        END);

CREATE FUNCTION public.guard_organization_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
    IF ROW(NEW.id, NEW.organization_id, NEW.member_id, NEW.receipt_number,
        NEW.amount_rwf, NEW.method, NEW.provider_reference, NEW.note, NEW.occurred_at,
        NEW.idempotency_key, NEW.request_fingerprint, NEW.recorded_by_user_id, NEW.created_at)
        IS DISTINCT FROM
        ROW(OLD.id, OLD.organization_id, OLD.member_id, OLD.receipt_number,
        OLD.amount_rwf, OLD.method, OLD.provider_reference, OLD.note, OLD.occurred_at,
        OLD.idempotency_key, OLD.request_fingerprint, OLD.recorded_by_user_id, OLD.created_at) THEN
        RAISE EXCEPTION 'payment identity and financial terms are immutable'
            USING ERRCODE = '23514', CONSTRAINT = 'organization_payment_history_guard';
    END IF;

    IF (OLD.confirmed_at IS NOT NULL AND NEW.confirmed_at IS DISTINCT FROM OLD.confirmed_at)
        OR (OLD.failed_at IS NOT NULL AND NEW.failed_at IS DISTINCT FROM OLD.failed_at)
        OR (OLD.voided_at IS NOT NULL AND NEW.voided_at IS DISTINCT FROM OLD.voided_at)
        OR (OLD.voided_by_user_id IS NOT NULL
            AND NEW.voided_by_user_id IS DISTINCT FROM OLD.voided_by_user_id)
        OR (OLD.void_reason IS NOT NULL AND NEW.void_reason IS DISTINCT FROM OLD.void_reason) THEN
        RAISE EXCEPTION 'recorded payment lifecycle evidence is immutable'
            USING ERRCODE = '23514', CONSTRAINT = 'organization_payment_lifecycle_guard';
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
        (OLD.status = 'pending' AND NEW.status IN ('confirmed', 'failed', 'voided'))
        OR (OLD.status = 'confirmed' AND NEW.status IN ('voided', 'partially_refunded', 'refunded'))
        OR (OLD.status = 'partially_refunded' AND NEW.status = 'refunded')
    ) THEN
        RAISE EXCEPTION 'invalid payment status transition'
            USING ERRCODE = '23514', CONSTRAINT = 'organization_payment_status_guard';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER organization_payment_history_guard
BEFORE UPDATE ON public.organization_payments
FOR EACH ROW EXECUTE FUNCTION public.guard_organization_payment();

CREATE FUNCTION public.guard_payment_allocation_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
    RAISE EXCEPTION 'payment allocations are immutable'
        USING ERRCODE = '23514', CONSTRAINT = 'payment_allocation_history_guard';
END;
$function$;

CREATE TRIGGER payment_allocation_history_guard
BEFORE UPDATE OR DELETE ON public.organization_payment_allocations
FOR EACH ROW EXECUTE FUNCTION public.guard_payment_allocation_history();

CREATE FUNCTION public.guard_payment_refund_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'payment refunds are append-only'
            USING ERRCODE = '23514', CONSTRAINT = 'payment_refund_history_guard';
    END IF;

    IF ROW(NEW.id, NEW.organization_id, NEW.payment_id, NEW.member_id, NEW.amount_rwf,
        NEW.reason, NEW.provider_reference, NEW.idempotency_key, NEW.request_fingerprint,
        NEW.requested_by_user_id, NEW.created_at)
        IS DISTINCT FROM
        ROW(OLD.id, OLD.organization_id, OLD.payment_id, OLD.member_id, OLD.amount_rwf,
        OLD.reason, OLD.provider_reference, OLD.idempotency_key, OLD.request_fingerprint,
        OLD.requested_by_user_id, OLD.created_at) THEN
        RAISE EXCEPTION 'payment refund identity and terms are immutable'
            USING ERRCODE = '23514', CONSTRAINT = 'payment_refund_history_guard';
    END IF;

    IF (OLD.confirmed_at IS NOT NULL AND NEW.confirmed_at IS DISTINCT FROM OLD.confirmed_at)
        OR (OLD.failed_at IS NOT NULL AND NEW.failed_at IS DISTINCT FROM OLD.failed_at)
        OR (NEW.status IS DISTINCT FROM OLD.status AND NOT
            (OLD.status = 'pending' AND NEW.status IN ('confirmed', 'failed'))) THEN
        RAISE EXCEPTION 'invalid payment refund lifecycle transition'
            USING ERRCODE = '23514', CONSTRAINT = 'payment_refund_lifecycle_guard';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER payment_refund_history_guard
BEFORE UPDATE OR DELETE ON public.organization_payment_refunds
FOR EACH ROW EXECUTE FUNCTION public.guard_payment_refund_history();

CREATE FUNCTION public.guard_payment_audit_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
    RAISE EXCEPTION 'payment audit events are append-only'
        USING ERRCODE = '23514', CONSTRAINT = 'payment_audit_history_guard';
END;
$function$;

CREATE TRIGGER payment_audit_history_guard
BEFORE UPDATE OR DELETE ON public.organization_payment_audit_events
FOR EACH ROW EXECUTE FUNCTION public.guard_payment_audit_history();

CREATE FUNCTION public.stamp_payment_audit_recorded_at()
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

CREATE TRIGGER payment_audit_recorded_at_stamp
BEFORE INSERT ON public.organization_payment_audit_events
FOR EACH ROW EXECUTE FUNCTION public.stamp_payment_audit_recorded_at();

CREATE FUNCTION public.validate_payment_allocation_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    target_organization_id uuid;
    target_payment_id uuid;
    payment_amount bigint;
    allocated_amount bigint;
BEGIN
    IF TG_TABLE_NAME = 'organization_payments' THEN
        target_organization_id := NEW.organization_id;
        target_payment_id := NEW.id;
    ELSIF TG_OP = 'DELETE' THEN
        target_organization_id := OLD.organization_id;
        target_payment_id := OLD.payment_id;
    ELSE
        target_organization_id := NEW.organization_id;
        target_payment_id := NEW.payment_id;
    END IF;

    SELECT amount_rwf INTO payment_amount
    FROM public.organization_payments
    WHERE organization_id = target_organization_id AND id = target_payment_id;

    IF FOUND THEN
        SELECT COALESCE(sum(amount_rwf), 0) INTO allocated_amount
        FROM public.organization_payment_allocations
        WHERE organization_id = target_organization_id AND payment_id = target_payment_id;

        IF allocated_amount <> payment_amount THEN
            RAISE EXCEPTION 'payment allocations must equal the payment amount'
                USING ERRCODE = '23514', CONSTRAINT = 'payment_allocation_balance_guard';
        END IF;
    END IF;
    RETURN NULL;
END;
$function$;

CREATE CONSTRAINT TRIGGER payment_allocation_balance_payment_guard
AFTER INSERT OR UPDATE ON public.organization_payments
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.validate_payment_allocation_balance();

CREATE CONSTRAINT TRIGGER payment_allocation_balance_allocation_guard
AFTER INSERT OR UPDATE OR DELETE ON public.organization_payment_allocations
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.validate_payment_allocation_balance();

CREATE FUNCTION public.validate_payment_refund_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    target_organization_id uuid;
    target_payment_id uuid;
    payment_amount bigint;
    payment_status public.organization_payment_status;
    refunded_amount bigint;
BEGIN
    IF TG_TABLE_NAME = 'organization_payments' THEN
        target_organization_id := NEW.organization_id;
        target_payment_id := NEW.id;
    ELSIF TG_OP = 'DELETE' THEN
        target_organization_id := OLD.organization_id;
        target_payment_id := OLD.payment_id;
    ELSE
        target_organization_id := NEW.organization_id;
        target_payment_id := NEW.payment_id;
    END IF;

    SELECT amount_rwf, status INTO payment_amount, payment_status
    FROM public.organization_payments
    WHERE organization_id = target_organization_id AND id = target_payment_id;

    IF FOUND THEN
        SELECT COALESCE(sum(amount_rwf), 0) INTO refunded_amount
        FROM public.organization_payment_refunds
        WHERE organization_id = target_organization_id AND payment_id = target_payment_id
            AND status = 'confirmed';

        IF refunded_amount > payment_amount
            OR (refunded_amount = 0 AND payment_status IN ('partially_refunded', 'refunded'))
            OR (refunded_amount > 0 AND refunded_amount < payment_amount
                AND payment_status <> 'partially_refunded')
            OR (refunded_amount = payment_amount AND payment_status <> 'refunded') THEN
            RAISE EXCEPTION 'confirmed refunds and payment status are inconsistent'
                USING ERRCODE = '23514', CONSTRAINT = 'payment_refund_balance_guard';
        END IF;
    END IF;
    RETURN NULL;
END;
$function$;

CREATE CONSTRAINT TRIGGER payment_refund_balance_payment_guard
AFTER INSERT OR UPDATE ON public.organization_payments
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.validate_payment_refund_balance();

CREATE CONSTRAINT TRIGGER payment_refund_balance_refund_guard
AFTER INSERT OR UPDATE OR DELETE ON public.organization_payment_refunds
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.validate_payment_refund_balance();

REVOKE ALL ON TABLE public.organization_payments FROM PUBLIC;
REVOKE ALL ON TABLE public.organization_payment_allocations FROM PUBLIC;
REVOKE ALL ON TABLE public.organization_payment_refunds FROM PUBLIC;
REVOKE ALL ON TABLE public.organization_payment_audit_events FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_payment_method FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_payment_status FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_payment_refund_status FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_payment_audit_action FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_organization_payment() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_payment_allocation_history() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_payment_refund_history() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_payment_audit_history() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.stamp_payment_audit_recorded_at() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.validate_payment_allocation_balance() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.validate_payment_refund_balance() FROM PUBLIC;

COMMIT;
