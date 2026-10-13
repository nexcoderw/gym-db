-- CreateEnum
CREATE TYPE "organization_status" AS ENUM ('pending', 'active', 'suspended', 'archived');

-- CreateTable
CREATE TABLE "organizations" (
    "id" UUID NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "slug" VARCHAR(63) NOT NULL,
    "status" "organization_status" NOT NULL DEFAULT 'pending',
    "activated_at" TIMESTAMPTZ(6),
    "suspended_at" TIMESTAMPTZ(6),
    "archived_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "organizations_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "organizations_slug_key" ON "organizations"("slug");

-- CreateIndex
CREATE INDEX "organizations_status_created_at_id_idx" ON "organizations"("status", "created_at" DESC, "id");
