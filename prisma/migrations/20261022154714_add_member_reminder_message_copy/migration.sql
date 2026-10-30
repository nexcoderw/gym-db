-- Add nullable snapshots for owner-composed reminder content without rewriting existing rows.
ALTER TABLE "organization_member_reminder_deliveries"
	ADD COLUMN "message_subject" VARCHAR(160),
	ADD COLUMN "message_body" VARCHAR(4000);
