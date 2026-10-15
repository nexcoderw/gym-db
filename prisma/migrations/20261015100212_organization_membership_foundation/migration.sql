-- CreateEnum
CREATE TYPE "organization_membership_status" AS ENUM ('pending', 'active', 'suspended', 'revoked');

-- CreateTable
CREATE TABLE "organization_memberships" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "status" "organization_membership_status" NOT NULL DEFAULT 'pending',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    "activated_at" TIMESTAMPTZ(6),
    "suspended_at" TIMESTAMPTZ(6),
    "revoked_at" TIMESTAMPTZ(6),

    CONSTRAINT "organization_memberships_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organization_roles" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "key" VARCHAR(63) NOT NULL,
    "name" VARCHAR(120) NOT NULL,
    "description" VARCHAR(500),
    "is_system" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "organization_roles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organization_membership_roles" (
    "organization_id" UUID NOT NULL,
    "organization_membership_id" UUID NOT NULL,
    "organization_role_id" UUID NOT NULL,
    "assigned_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "organization_membership_roles_pkey" PRIMARY KEY ("organization_id","organization_membership_id","organization_role_id")
);

-- CreateIndex
CREATE INDEX "organization_memberships_org_status_created_id_idx" ON "organization_memberships"("organization_id", "status", "created_at" DESC, "id");

-- CreateIndex
CREATE INDEX "organization_memberships_org_created_id_idx" ON "organization_memberships"("organization_id", "created_at" DESC, "id");

-- CreateIndex
CREATE INDEX "organization_memberships_user_status_created_id_idx" ON "organization_memberships"("user_id", "status", "created_at" DESC, "id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_memberships_organization_user_key" ON "organization_memberships"("organization_id", "user_id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_memberships_organization_id_key" ON "organization_memberships"("organization_id", "id");

-- CreateIndex
CREATE INDEX "organization_roles_org_system_created_id_idx" ON "organization_roles"("organization_id", "is_system", "created_at" DESC, "id");

-- CreateIndex
CREATE UNIQUE INDEX "organization_roles_organization_key_key" ON "organization_roles"("organization_id", "key");

-- CreateIndex
CREATE UNIQUE INDEX "organization_roles_organization_id_key" ON "organization_roles"("organization_id", "id");

-- CreateIndex
CREATE INDEX "organization_membership_roles_org_role_membership_idx" ON "organization_membership_roles"("organization_id", "organization_role_id", "organization_membership_id");

-- AddForeignKey
ALTER TABLE "organization_memberships" ADD CONSTRAINT "organization_memberships_organization_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_memberships" ADD CONSTRAINT "organization_memberships_user_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_roles" ADD CONSTRAINT "organization_roles_organization_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_membership_roles" ADD CONSTRAINT "organization_membership_roles_membership_fkey" FOREIGN KEY ("organization_id", "organization_membership_id") REFERENCES "organization_memberships"("organization_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- AddForeignKey
ALTER TABLE "organization_membership_roles" ADD CONSTRAINT "organization_membership_roles_role_fkey" FOREIGN KEY ("organization_id", "organization_role_id") REFERENCES "organization_roles"("organization_id", "id") ON DELETE RESTRICT ON UPDATE RESTRICT;

-- Enforce the reviewed tenant-role text and trusted OWNER-role contract for every SQL writer.
ALTER TABLE public.organization_roles
  ADD CONSTRAINT organization_roles_key_format_check CHECK (
    char_length(key) BETWEEN 2 AND 63
    AND key COLLATE "C" ~ '^[a-z][a-z0-9]*([._-][a-z0-9]+)*$'
  ),
  ADD CONSTRAINT organization_roles_name_nonblank_check CHECK (
    char_length(btrim(name,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
    )) > 0
  ),
  ADD CONSTRAINT organization_roles_description_nonblank_check CHECK (
    description IS NULL OR char_length(btrim(description,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
    )) > 0
  ),
  ADD CONSTRAINT organization_roles_owner_system_check CHECK (
    key <> 'owner' OR is_system
  );

-- Tenant authorization tables are never exposed through PostgreSQL's PUBLIC pseudo-role.
REVOKE ALL ON TABLE
  public.organization_memberships,
  public.organization_roles,
  public.organization_membership_roles
FROM PUBLIC;

REVOKE ALL ON TYPE public.organization_membership_status FROM PUBLIC;
