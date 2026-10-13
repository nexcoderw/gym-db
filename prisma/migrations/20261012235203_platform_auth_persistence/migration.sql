-- CreateTable
CREATE TABLE "platform_admin_sessions" (
    "id" UUID NOT NULL,
    "platform_staff_id" UUID NOT NULL,
    "token_digest" VARCHAR(128) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "idle_expires_at" TIMESTAMPTZ(6) NOT NULL,
    "last_seen_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "mfa_verified_at" TIMESTAMPTZ(6) NOT NULL,
    "revoked_at" TIMESTAMPTZ(6),

    CONSTRAINT "platform_admin_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "platform_totp_credentials" (
    "id" UUID NOT NULL,
    "platform_staff_id" UUID NOT NULL,
    "encrypted_secret" BYTEA NOT NULL,
    "encryption_key_id" VARCHAR(120) NOT NULL,
    "encryption_version" INTEGER NOT NULL DEFAULT 1,
    "initialization_vector" BYTEA NOT NULL,
    "authentication_tag" BYTEA NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "verified_at" TIMESTAMPTZ(6),
    "last_used_at" TIMESTAMPTZ(6),
    "last_accepted_time_step" BIGINT,
    "disabled_at" TIMESTAMPTZ(6),

    CONSTRAINT "platform_totp_credentials_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "platform_recovery_codes" (
    "id" UUID NOT NULL,
    "platform_staff_id" UUID NOT NULL,
    "code_digest" VARCHAR(128) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "used_at" TIMESTAMPTZ(6),

    CONSTRAINT "platform_recovery_codes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "platform_mfa_challenges" (
    "id" UUID NOT NULL,
    "platform_staff_id" UUID NOT NULL,
    "token_digest" VARCHAR(128) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "consumed_at" TIMESTAMPTZ(6),
    "failed_attempts" INTEGER NOT NULL DEFAULT 0,
    "max_attempts" INTEGER NOT NULL DEFAULT 5,

    CONSTRAINT "platform_mfa_challenges_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "platform_admin_sessions_token_digest_key" ON "platform_admin_sessions"("token_digest");

-- CreateIndex
CREATE INDEX "platform_admin_sessions_staff_active_idx" ON "platform_admin_sessions"("platform_staff_id", "revoked_at", "expires_at");

-- CreateIndex
CREATE INDEX "platform_admin_sessions_expires_at_idx" ON "platform_admin_sessions"("expires_at");

-- CreateIndex
CREATE INDEX "platform_admin_sessions_idle_expires_at_idx" ON "platform_admin_sessions"("idle_expires_at");

-- CreateIndex
CREATE UNIQUE INDEX "platform_totp_credentials_staff_key" ON "platform_totp_credentials"("platform_staff_id");

-- CreateIndex
CREATE UNIQUE INDEX "platform_recovery_codes_digest_key" ON "platform_recovery_codes"("code_digest");

-- CreateIndex
CREATE INDEX "platform_recovery_codes_staff_unused_idx" ON "platform_recovery_codes"("platform_staff_id", "used_at");

-- CreateIndex
CREATE UNIQUE INDEX "platform_mfa_challenges_token_digest_key" ON "platform_mfa_challenges"("token_digest");

-- CreateIndex
CREATE INDEX "platform_mfa_challenges_staff_active_idx" ON "platform_mfa_challenges"("platform_staff_id", "consumed_at", "expires_at");

-- CreateIndex
CREATE INDEX "platform_mfa_challenges_expires_at_idx" ON "platform_mfa_challenges"("expires_at");

-- AddForeignKey
ALTER TABLE "platform_admin_sessions" ADD CONSTRAINT "platform_admin_sessions_platform_staff_id_fkey" FOREIGN KEY ("platform_staff_id") REFERENCES "platform_staff"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "platform_totp_credentials" ADD CONSTRAINT "platform_totp_credentials_platform_staff_id_fkey" FOREIGN KEY ("platform_staff_id") REFERENCES "platform_staff"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "platform_recovery_codes" ADD CONSTRAINT "platform_recovery_codes_platform_staff_id_fkey" FOREIGN KEY ("platform_staff_id") REFERENCES "platform_staff"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "platform_mfa_challenges" ADD CONSTRAINT "platform_mfa_challenges_platform_staff_id_fkey" FOREIGN KEY ("platform_staff_id") REFERENCES "platform_staff"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;
