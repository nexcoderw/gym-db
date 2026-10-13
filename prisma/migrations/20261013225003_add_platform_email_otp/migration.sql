-- AlterTable
ALTER TABLE "platform_mfa_challenges" ADD COLUMN     "email_otp_digest" VARCHAR(128),
ADD COLUMN     "email_otp_expires_at" TIMESTAMPTZ(6),
ADD COLUMN     "email_otp_send_count" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "email_otp_sent_at" TIMESTAMPTZ(6);
