-- CreateTable
CREATE TABLE "organization_membership_plans" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "name" VARCHAR(120) NOT NULL,
    "normalized_name" VARCHAR(120) NOT NULL,
    "price_rwf" BIGINT NOT NULL,
    "description" VARCHAR(1000),
    "archived_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "organization_membership_plans_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "membership_plans_name_nonblank_check"
        CHECK (btrim("name") <> ''),
    CONSTRAINT "membership_plans_normalized_name_nonblank_check"
        CHECK (btrim("normalized_name") <> ''),
    CONSTRAINT "membership_plans_price_rwf_range_check"
        CHECK ("price_rwf" BETWEEN 0 AND 1000000000),
    CONSTRAINT "membership_plans_description_nonblank_check"
        CHECK ("description" IS NULL OR btrim("description") <> ''),
    CONSTRAINT "membership_plans_updated_at_order_check"
        CHECK ("updated_at" >= "created_at"),
    CONSTRAINT "membership_plans_archived_at_order_check"
        CHECK ("archived_at" IS NULL OR "archived_at" >= "created_at")
);

-- CreateIndex
CREATE INDEX "organization_membership_plans_org_archive_created_id_idx" ON "organization_membership_plans"("organization_id", "archived_at", "created_at" DESC, "id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_membership_plans_org_name_key" ON "organization_membership_plans"("organization_id", "normalized_name");

-- CreateIndex
CREATE UNIQUE INDEX "organization_membership_plans_organization_id_key" ON "organization_membership_plans"("organization_id", "id");

-- AddForeignKey
ALTER TABLE "organization_membership_plans" ADD CONSTRAINT "organization_membership_plans_organization_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;
