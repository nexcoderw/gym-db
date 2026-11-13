-- Ensure SMS suppression timestamp and reason are paired.
ALTER TABLE "organization_members"
ADD CONSTRAINT "organization_members_sms_suppression_pair_check"
CHECK (
  ("reminder_sms_suppressed_at" IS NULL) =
  ("reminder_sms_suppression_reason" IS NULL)
);

-- Enforce synthetic member identity and suppression.
ALTER TABLE "organization_members"
ADD CONSTRAINT "organization_members_synthetic_protection_check"
CHECK (
  (
    "is_synthetic" = false
    AND "synthetic_batch_id" IS NULL
  )
  OR
  (
    "is_synthetic" = true
    AND "synthetic_batch_id" IS NOT NULL
    AND length(btrim("synthetic_batch_id")) BETWEEN 1 AND 120
    AND "email" IS NULL
    AND "reminder_email_suppressed_at" IS NOT NULL
    AND "reminder_email_suppression_reason" IS NOT NULL
    AND "reminder_sms_suppressed_at" IS NOT NULL
    AND "reminder_sms_suppression_reason" IS NOT NULL
  )
);
