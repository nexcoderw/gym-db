-- EnableExtension
CREATE EXTENSION IF NOT EXISTS citext;

-- CreateEnum
CREATE TYPE "user_status" AS ENUM ('pending', 'active', 'suspended');

-- CreateEnum
CREATE TYPE "platform_staff_status" AS ENUM ('pending', 'active', 'suspended', 'revoked');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "email" CITEXT NOT NULL,
    "display_name" VARCHAR(160) NOT NULL,
    "status" "user_status" NOT NULL DEFAULT 'pending',
    "email_verified_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "password_credentials" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "password_hash" VARCHAR(255) NOT NULL,
    "password_changed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "password_credentials_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "platform_staff" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "status" "platform_staff_status" NOT NULL,
    "suspended_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "platform_staff_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "platform_roles" (
    "id" UUID NOT NULL,
    "key" CITEXT NOT NULL,
    "name" VARCHAR(120) NOT NULL,
    "description" VARCHAR(500) NOT NULL,
    "is_system" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "platform_roles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "platform_permissions" (
    "id" UUID NOT NULL,
    "key" CITEXT NOT NULL,
    "description" VARCHAR(500) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "platform_permissions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "platform_staff_roles" (
    "platform_staff_id" UUID NOT NULL,
    "platform_role_id" UUID NOT NULL,
    "assigned_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "platform_staff_roles_pkey" PRIMARY KEY ("platform_staff_id","platform_role_id")
);

-- CreateTable
CREATE TABLE "platform_role_permissions" (
    "platform_role_id" UUID NOT NULL,
    "platform_permission_id" UUID NOT NULL,
    "granted_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "platform_role_permissions_pkey" PRIMARY KEY ("platform_role_id","platform_permission_id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE INDEX "users_status_idx" ON "users"("status");

-- CreateIndex
CREATE UNIQUE INDEX "password_credentials_user_id_key" ON "password_credentials"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "platform_staff_user_id_key" ON "platform_staff"("user_id");

-- CreateIndex
CREATE INDEX "platform_staff_status_idx" ON "platform_staff"("status");

-- CreateIndex
CREATE UNIQUE INDEX "platform_roles_key_key" ON "platform_roles"("key");

-- CreateIndex
CREATE UNIQUE INDEX "platform_permissions_key_key" ON "platform_permissions"("key");

-- CreateIndex
CREATE INDEX "platform_staff_roles_role_id_idx" ON "platform_staff_roles"("platform_role_id");

-- CreateIndex
CREATE INDEX "platform_role_permissions_permission_id_idx" ON "platform_role_permissions"("platform_permission_id");

-- AddForeignKey
ALTER TABLE "password_credentials" ADD CONSTRAINT "password_credentials_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "platform_staff" ADD CONSTRAINT "platform_staff_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "platform_staff_roles" ADD CONSTRAINT "platform_staff_roles_platform_staff_id_fkey" FOREIGN KEY ("platform_staff_id") REFERENCES "platform_staff"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "platform_staff_roles" ADD CONSTRAINT "platform_staff_roles_platform_role_id_fkey" FOREIGN KEY ("platform_role_id") REFERENCES "platform_roles"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "platform_role_permissions" ADD CONSTRAINT "platform_role_permissions_platform_role_id_fkey" FOREIGN KEY ("platform_role_id") REFERENCES "platform_roles"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "platform_role_permissions" ADD CONSTRAINT "platform_role_permissions_platform_permission_id_fkey" FOREIGN KEY ("platform_permission_id") REFERENCES "platform_permissions"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;
