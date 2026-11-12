
-- CreateEnum
CREATE TYPE "organization_member_gender" AS ENUM (
    'male',
    'female',
    'other',
    'prefer_not_to_say'
);

-- AlterTable
ALTER TABLE "organization_members"
ADD COLUMN "gender" "organization_member_gender";
