-- AlterTable
ALTER TABLE "organization_feature_entitlement_audit_events" ALTER COLUMN "id" DROP DEFAULT;

-- AlterTable
ALTER TABLE "organization_members" ADD COLUMN     "joined_on" DATE;

-- CreateIndex
CREATE INDEX "organization_members_org_joined_on_id_idx" ON "organization_members"("organization_id", "joined_on", "id");
