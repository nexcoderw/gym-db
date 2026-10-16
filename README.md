# @nexcoderw/gym-db

Private database foundation for NEXCODE Gym Management SaaS. This repository is the only source of
truth for PostgreSQL schema, migrations, generated Prisma Client, and reusable NestJS database access.
It is a package consumed by `gym-api`; it is not a public server and contains no controllers.

## Architecture

### Email verification expansion (pending human migration review)

`PlatformMfaChallenge` now defines nullable email OTP digest/expiry/send timestamps and a send
counter defaulting to zero. These fields store no plaintext code or recipient. The API scopes keyed
digests to challenge and verified mailbox, consumes codes transactionally, and bounds resends.
Existing challenge records remain compatible with authenticator and recovery verification.

From this package, the human runs `npm run prisma:format`, `npm run prisma:validate`, then
`npm run migration:create -- --name add_platform_email_otp`. Review the resulting create-only SQL
before deployment: it must add only the four challenge columns with appropriate nullability and
the zero counter default, without dropping or rewriting existing authentication structures.
Do not modify applied migrations. Deploy the reviewed expansion to the intended development and
disposable test databases before starting the updated API. Regenerate Prisma and build this package
so its local API consumer sees the new fields. Roll back application behavior by disabling email
OTP, not by dropping fields or authentication data. No migration or generation was executed by
an agent; the expansion is not deployed until the human confirms it.

- Prisma 7 owns the canonical schema in `prisma/schema.prisma` and migration history in
  `prisma/migrations/`.
- The `prisma-client` generator writes release-time sources to `src/generated/prisma/`. Those sources
  are ignored by Git, compiled into `dist`, and included in the published package.
- `DatabaseModule` creates one lifecycle-managed `PrismaService` using `@prisma/adapter-pg`.
- `TenantTransactionService` installs transaction-local organization and branch context for future
  fail-closed PostgreSQL RLS policies. Prisma does not provide tenant isolation on its own.
- Global users remain separate from NEXCODE platform-staff assignments and explicit platform RBAC.
  Creating an account grants no platform access.
- Platform administration authentication uses dedicated server-session, TOTP, recovery-code, and
  pre-authentication challenge records that are never tenant scoped.
- `src/index.ts` is the sole supported public entry point.

Essential package guidance lives in this README; agent-only engineering rules live in `.agents/`.

## Responsibilities

This package owns models, relations, constraints, indexes, enums, migrations, client generation,
connection lifecycle, database configuration, tenant primitives, integrity tests, and migration
safety controls. `gym-api` owns transport, authentication, authorization decisions, business workflows,
email, billing orchestration, and user-facing DTOs. The API must not carry a schema or migrations.

## Prerequisites

- Node.js `^20.19.0`, `^22.12.0`, or `>=24.0.0`
- npm 10 or later
- PostgreSQL supported by the selected Prisma 7 release
- Separate disposable databases for development shadowing and integration tests
- GitHub Packages read/write tokens as appropriate

## Environment

Use separate ignored files for each workflow. Copy only the templates you need and replace their
placeholders with independently provisioned, non-production credentials:

| Local file              | Consumer                                                | Contents                                                                              |
| ----------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `.env.local`            | Application runtime; integration-test target comparison | Runtime `DATABASE_URL` only                                                           |
| `.env.migrations.local` | Prisma CLI                                              | `DIRECT_DATABASE_URL`, `SHADOW_DATABASE_URL`, `TEST_MIGRATION_DATABASE_URL`           |
| `.env.test.local`       | `npm run test:integration`                              | Restricted `TEST_DATABASE_URL`, marker, password-free migration/shadow reference URLs |

Matching `.example` files are tracked; real files must stay ignored and mode `600`. Do not source
these files in a shell: Node/dotenv parse URL query strings and password characters as data.
Never load `.env.migrations.local` into Jest or an application. Reference-only URLs in `.env.test.local`
retain the real migration/shadow host, port, database and username, but contain no password. Update
those references if you change a migration target; they preserve the existing isolation comparisons.

### Two Neon branches

Use `development` for four separate PostgreSQL databases: `gym_dev` (everyday application),
`gym_test` (integration fixtures), `gym_bootstrap_test` (API first-owner tests), and `gym_shadow`
(Prisma scratch space). Use `production` only for `gym_prod`. Branch count does not determine database
count: URLs on the same development endpoint remain isolated by their database names. Pooled and
direct URLs to the same database are not separate environments. `NODE_ENV` never selects a branch.

Use `gym_app` for application DML, `gym_migrator` for reviewed DDL, `gym_test` for integration-test DML,
and separate `gym_bootstrap` / `gym_bootstrap_test` roles for operator and disposable bootstrap work.
Create restricted roles with SQL rather than the Neon role-creation UI, and do not grant them
administrative role membership. Provision database markers independently before tests or bootstrap.
Production credentials and roles must be provisioned independently, not copied from development.

Keep existing migrations and safety checks when replacing an empty Neon project. Apply the committed
migrations to fresh databases; do not generate a replacement initial migration or use `db push`.
Do not remove the old project until every real local profile points to the new endpoint and the
human-operated checks pass. This repository never deletes remote projects automatically.

The migration profile needs no duplicate `DATABASE_URL`: `DIRECT_DATABASE_URL` selects `gym_dev`.
The CLI still accepts an externally supplied `DATABASE_URL` fallback for managed environments.

| Variable                         | Required by                | Description                                      |
| -------------------------------- | -------------------------- | ------------------------------------------------ |
| `DATABASE_URL`                   | runtime or CLI fallback    | Role depends on the workflow file, never shared  |
| `DIRECT_DATABASE_URL`            | migration CLI when pooled  | Direct migration-role URL; preferred for DDL     |
| `SHADOW_DATABASE_URL`            | local migration generation | Disposable development shadow database           |
| `DATABASE_POOL_MAX`              | runtime, optional          | Positive per-process pool limit; default `10`    |
| `DATABASE_CONNECTION_TIMEOUT_MS` | runtime, optional          | Positive connection timeout; default `10000`     |
| `TEST_DATABASE_URL`              | integration tests          | Restricted DML-only disposable test URL          |
| `TEST_DATABASE_MARKER`           | integration tests          | UUID recorded in the disposable database comment |
| `TEST_MIGRATION_DATABASE_URL`    | test migration deployment  | Direct owner URL; never used by test execution   |

Production secrets belong in the deployment secret manager. Never commit `.env` files or embed tokens
in `.npmrc`. PostgreSQL timestamps are UTC; user-facing business times use `Africa/Kigali`.

## Local development workflow

All commands in this repository are human-operated. From `api/db`:

```bash
npm install
cp .env.local.example .env.local
cp .env.migrations.local.example .env.migrations.local
cp .env.test.local.example .env.test.local
chmod 600 .env.local .env.migrations.local .env.test.local
```

Do not copy over existing files. Fill in the reviewed targets and independently provision the test
marker/role before continuing. Existing installations should move values, not regenerate credentials
or markers. Prisma now loads only `.env.migrations.local`, never `.env.local` or `.env`.

```bash
npm run prisma:generate
npm run prisma:format
npm run prisma:validate
npm run format
npm run lint
npm run typecheck
npm run test:unit
npm run test:integration
npm run build
npm pack --dry-run
```

To apply existing reviewed migrations to the integration-test database only:

```bash
npm run migration:test:deploy
npm run test:integration
```

`migration:test:deploy` uses `TEST_MIGRATION_DATABASE_URL` through `prisma.test.config.ts` and does not
configure a shadow database. It never runs automatically before tests. For normal reviewed migration
deployment use `npm run migration:deploy`; for create-only development migrations use
`npm run migration:create -- --name descriptive_change`. Confirm the printed database target before
continuing. Never use a production or application database as the disposable test target.

Node/dotenv preserve already exported shell values. Start a fresh terminal or unset conflicting
database variables before using local profiles; a file is not an override for managed secrets.
`npm test` and `npm run test:integration` explicitly load the local runtime/test files;
`npm run test:unit` needs no database profile.
Production CLI operations receive managed environment values and must not ship these local files.
CI/managed integration tests use `npm run test:integration:managed` with externally supplied runtime
reference URLs, restricted test credentials and marker; it loads no local profiles and performs the
same live safety checks.

`npm install` must regenerate `package-lock.json` after dependency edits. Prisma generation must happen
before type-checking, tests, or builds because generated sources are intentionally not committed.

## Use from gym-api

Authenticate to GitHub Packages, install an explicit immutable version, then register the module once:

```ts
import { DatabaseModule, loadDatabaseConfig } from '@nexcoderw/gym-db';
import { Module } from '@nestjs/common';

@Module({
  imports: [DatabaseModule.forRoot(loadDatabaseConfig())],
})
export class AppModule {}
```

At API bootstrap, call `app.enableShutdownHooks()` so Nest invokes database disconnect lifecycle hooks.
Tenant-owned work must pass the authenticated organization context to `TenantTransactionService`; IDs
from request bodies are not trusted authorization context.

## Schema and migrations

Do not build the full gym model speculatively. Each change follows this order:

1. Edit the schema here and have a human run a create-only migration.
2. Review generated SQL, locks, integrity, tenant scoping, rollout, and recovery.
3. Run validation and integration checks against isolated PostgreSQL.
4. Apply the approved expansion migration under human control.
5. Publish a compatible package and update `gym-api` to that exact version.
6. Contract only in a later release after old readers/writers are gone.

Never use `prisma db push` in production or edit a migration already applied. Follow the approved
deployment and incident procedures maintained outside this repository.

## Platform authentication persistence

`PlatformAdminSession` stores only unique session-token digests and requires an MFA verification
timestamp. Absolute and idle expiration timestamps plus per-session revocation support bounded
server-side sessions and revoking every session for one platform administrator.

`PlatformTotpCredential` stores authenticated-encryption ciphertext, key identifier, format version,
initialization vector, and authentication tag. Encryption keys never belong in PostgreSQL. Enrollment
is incomplete until `verifiedAt` is set, and the future API must atomically advance
`lastAcceptedTimeStep` to prevent replay. Factor replacement or disabling requires recent
reauthentication, authorization, and a privileged audit event.

`PlatformRecoveryCode` stores only unique digests. The future API generates high-entropy codes,
reveals them only during enrollment or regeneration, consumes them with an atomic conditional update,
and revokes the previous set when issuing replacements. `PlatformMfaChallenge` stores only a digest
and bounded, short-lived attempt state; it never grants platform access or substitutes for a session.

The API owns cryptographically secure token generation, digest construction, versioned authenticated
encryption, TOTP verification, cookie security, CSRF protection, reauthentication, cleanup, key
rotation, retention, and audit workflows. Login or an MFA challenge alone grants nothing. Every
administrative request must verify the user and platform-staff records are active, password and MFA
requirements were satisfied, the session is neither expired nor revoked, and effective platform
permissions allow the operation. Tenant context must never authorize access to these global records.
Production database privileges and service-level authorization must restrict these sensitive models
to the platform authentication service even though the generated Prisma client exposes them.

## Versioning and publication

Use SemVer for the package. A backwards-compatible API/schema addition is normally minor; fixes are
patches; removal or incompatible client API requires a major version. Database rollout compatibility
can require expand-and-contract even when the package API change is minor. Published versions are
immutable.

GitHub Packages publication requires an npm token with `write:packages` (and repository access when
private). Consumers need `read:packages`. Use `npm login --scope=@nexcoderw --auth-type=legacy
--registry=https://npm.pkg.github.com`, never a committed token. Follow the approved release procedure
maintained outside this repository.

## Testing and security

Unit tests cover configuration, module exports, tenant validation, parameterized context setup, and
fail-before-callback behavior. Integration tests require a disposable `TEST_DATABASE_URL`, a unique
`TEST_DATABASE_MARKER`, and a dedicated non-administrative test role. Before any write, the suite
verifies the actual connected database, its human-provisioned marker, and role privileges. URL
inequality and database naming are only preliminary heuristics; different URLs can still reach the
same database. Fixture cleanup is limited to identifiers reserved by the current test and preserves
unrelated rows. The suite verifies transaction-local context, success and rollback cleanup, sequential
tenant replacement, concurrent tenant separation, platform identity uniqueness, restrictive
relationships, explicit RBAC assignments, suspension/revocation states, and rollback. Future tenant
models must add cross-tenant denial tests under RLS. Follow the integration-test safety requirements
in this section before running the suite.

Use distinct least-privilege runtime and migration roles, TLS outside trusted local development,
parameterized SQL, and synthetic examples (for example fictional Soho Gym branches in Kimihurura and
Remera). Follow the tenant-isolation requirements in this section.

## Troubleshooting

- **Generated client import missing:** run `npm run prisma:generate` after installing dependencies.
- **CLI uses a pooler:** set `DIRECT_DATABASE_URL` to a direct migration connection.
- **Shadow database matches the migration database:** provision a dedicated disposable shadow database
  and update `SHADOW_DATABASE_URL`. Prisma Migrate may reset it, so never reuse runtime or test data.
- **Migration deploy reports no migrations:** run the reviewed create-only workflow first; do not deploy
  until the generated SQL has been inspected and approved.
- **Integration suite requires configuration:** provision a unique database marker and restricted role,
  then apply reviewed migrations. Missing, privileged, reused, or unverified configurations fail before
  test writes.
- **Process does not disconnect:** verify the API enabled Nest shutdown hooks.
- **GitHub Packages returns 401/403:** confirm scope registry, token scopes, SSO/repository access, and
  that the token is supplied through the user npm configuration rather than this repository.
- **Migration drift:** stop deployment and follow the approved recovery procedure. Do not use `db push`.

## Organization foundation (Step 10)

`Organization` is an independent business/tenant root mapped to `public.organizations`, not a User,
PlatformStaff assignment or tenant-owned child. It has no self-referencing organizationId, owner
identity, branch, subscription, financial, contact or arbitrary metadata fields. Creating a row grants
no account, platform permission, tenant membership, subscription or feature entitlement.

Fields: UUID `id`; required nonunique `name` (varchar 160); globally unique `slug` (varchar 63);
`status` defaulting to PENDING; `createdAt`/`updatedAt`; nullable `activatedAt`, `suspendedAt` and
`archivedAt`. All dates use timestamptz(6). Prisma supplies UUIDs and updates updatedAt; these are not
PostgreSQL UUID/updatedAt triggers, so raw SQL writers must supply those values explicitly. Future
workflows must never replace the UUID when names, slugs or lifecycle state change.

`organization_status` maps PENDING/ACTIVE/SUSPENDED/ARCHIVED to lowercase database enum values:

- PENDING: registered, not approved for normal operation.
- ACTIVE: operational from the platform lifecycle perspective only.
- SUSPENDED: operational access disabled pending review.
- ARCHIVED: inactive and retained pending approved records handling.

Status is authoritative. Nullable lifecycle dates record the latest corresponding transition,
not an exhaustive audit log or independent access grants; restoration may retain earlier dates.
This package implements no transitions, timestamp/status coupling, authorization or automatic
activation. Future API workflows must apply permissions, transactions and audit requirements.
Archival retains the unique slug; no partial uniqueness or automatic reassignment is implemented.
No automatic deletion/cascade is introduced. Future dependent relations require reviewed restrictive
foreign keys. Archival is not legal erasure or a justification for indefinite retention.

### Slugs and required PostgreSQL checks

Slugs are public routing identifiers, never credentials. Require 3–63 ASCII characters, starting
with a lowercase letter, ending in a letter/digit, with single hyphens separating alphanumeric
groups. Uppercase, Unicode, dots, underscores, spaces, repeated/edge hyphens are invalid. Future
API normalization must occur before persistence; PostgreSQL rejects invalid input rather than
silently normalizing it. Subdomain provisioning and reassignment are not implemented.

The reserved list below covers the requested infrastructure names plus account/accounts, oauth,
console, internal, health, metrics, production, development and bootstrap. It is a reviewed initial
allocation, not a complete prediction of future infrastructure. New reserved names require a
reviewed migration and a preflight for existing organizations; never silently steal a held slug.

Schema uniqueness and the enum do not enforce name/slug checks. The human-generated migration
`20261013195500_create_organizations` creates the table/type/indexes without the checks below and
has already been applied to a database. Preserve that file unchanged. Review and approve these
additions in a new, unapplied forward migration; do not rewrite applied history:

```sql
ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_name_nonblank_check CHECK (
    char_length(btrim(name,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
    )) > 0
  ),
  ADD CONSTRAINT organizations_slug_format_check CHECK (
    char_length(slug) BETWEEN 3 AND 63
    AND slug COLLATE "C" ~ '^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
  ),
  ADD CONSTRAINT organizations_slug_reserved_check CHECK (
    slug NOT IN (
      'admin', 'api', 'app', 'www', 'auth', 'login', 'member', 'members',
      'portal', 'dashboard', 'billing', 'support', 'status', 'static',
      'assets', 'cdn', 'mail', 'dev', 'staging', 'test', 'localhost',
      'account', 'accounts', 'oauth', 'console', 'internal', 'health',
      'metrics', 'production', 'development', 'bootstrap'
    )
  );

REVOKE ALL ON TABLE public.organizations FROM PUBLIC;
```

If an environment recorded the earlier integrity migration before its constraint SQL was present,
deploy `20261015091135_repair_organization_integrity_constraints` as the forward repair. It adds
missing named checks, validates existing unvalidated checks and retains already validated checks.
The repair runs transactionally with a 10-second lock timeout and 60-second statement timeout because
adding or validating checks scans existing organization rows and requires a table lock. A timeout or
invalid existing row rolls the entire repair back; correct the data or schedule a quiet deployment
window and retry instead of editing migration history.

The name check explicitly covers ASCII and Unicode whitespace (including NBSP/ideographic spaces)
and BOM; it does not trim or prohibit Unicode display names. Require UTF-8 server encoding for this
reviewed Unicode policy. The slug regex uses C collation for stable ASCII ranges. See PostgreSQL's
[Unicode literal syntax](https://www.postgresql.org/docs/current/sql-syntax-lexical.html) and
[CHECK constraints](https://www.postgresql.org/docs/current/ddl-constraints.html).

Expected objects: `organizations_pkey`, `organizations_slug_key`, the three named CHECK constraints
above, and `organizations_status_created_at_id_idx` on (status, created_at DESC, id). The latter
supports filtered platform administration ordering and a deterministic tie-breaker; no duplicate
single-column status/slug indexes are needed. Unfiltered global ordering may need future measured
query/index design, not speculative extra indexes here. Uniqueness is database-enforced under
concurrency and applies to every status. Confirm all checks are validated, not left NOT VALID.

### Platform versus tenant access: exposure blocker

The registry is currently platform-managed only. Do not apply a tenant-owned child rule by adding a
self-reference, and do not add an unrestricted all-tenants runtime helper. `TenantTransactionService`
validates UUID shape and sets transaction-local context; it neither authenticates membership nor
creates PostgreSQL policies. Organization selection/slug knowledge is never authorization.

Before exposing any tenant-facing organization data, implement and verify separate platform and
tenant runtime roles/privileges plus fail-closed policies where appropriate. Audit inherited grants,
role memberships, table ownership, BYPASSRLS and migrator default privileges. The current general
application role cannot be treated as an isolated tenant role merely by setting a context variable.
Do not add a permissive RLS policy to accommodate that shared role. Platform listing requires an
explicit platform permission and audited interface; tenant roles must have no unrestricted registry
access. Table owners and privileged roles need separate consideration in RLS design.

The draft must revoke PUBLIC access and include only approved platform grants after role review.
Normal platform runtime privileges should not include DELETE for an archival-only workflow;
retention deletion belongs to a separately approved operational process.
Do not grant this table to future tenant roles, broaden schema-wide grants or let runtime roles own
or alter it. On the disposable test database only, its verified restricted test role needs explicit
SELECT/INSERT/UPDATE/DELETE on organizations and schema/type usage, but no DDL/administrative powers.
Tests prove persistence constraints, not completed tenant isolation. Future child records require
organization foreign keys, organization-leading indexes/uniques, restrictive relationships and
branch-to-organization consistency when branches are later added.

### Human-controlled migration and verification gate

For the already-applied initial organization migration, first inspect the status of both the normal
development target and the configured disposable test target. A generated client does not create
database tables, and application and test profiles may select different databases:

```bash
npm run migration:status
npx prisma migrate status --config prisma.test.config.ts
```

The human-generated `20261013203346_harden_organization_constraints` migration contains only an
empty-migration comment and has already been applied somewhere. It adds no CHECK constraints.
Preserve its exact contents/checksum and generate another SQL-only draft using the separate shadow
database:

```bash
npm run migration:create -- --name enforce_organization_integrity_permissions
```

Create-only supports an empty migration when the Prisma schema has no changes. Do not accept a reset
prompt if drift is reported; stop and review the target/history. Send the new migration.sql for review
before it is populated or deployed. **Do not deploy the empty draft.** It must contain the three
reviewed CHECK additions and PUBLIC-access revocation shown above before migration deployment.
Applied migration status alone cannot prove those objects exist. Existing rows must satisfy all
checks before adding them; conflicts
require separately reviewed correction, not silent renaming or deletion. The initial organization
migration remains unchanged, including on databases where it is still pending. The commands below
for create_organizations describe the original creation workflow, not a request to repeat it.

From `api/db`, confirm `.env.migrations.local` selects the direct migration role on the intended
development database and a separate disposable shadow database. Shell variables take precedence
over dotenv; remove stale exports before running these commands. Never print connection credentials.

```bash
npm run prisma:format
npm run prisma:validate
npm run migration:create -- --name create_organizations
```

**Stop here and provide the generated migration.sql for review before deployment.** Review all DDL:
only the organization enum/table, required checks, unique/administration indexes and approved grants
may change. Existing platform identity/authentication tables and applied migrations must remain
unchanged. Review schema placement, object names, defaults/nullability, Unicode/check behavior,
privileges and default grants. Do not fabricate migration directories or use db push.

After SQL approval only, verify the disposable target, marker, role and `TEST_MIGRATION_DATABASE_URL`
point to gym_test rather than gym_dev, gym_shadow, gym_bootstrap_test or production. Deploy with its
separate migrator, then have the human apply the approved table-specific restricted test grants.
If the verified role is named gym_test, the following SQL belongs only in the development branch's
gym_test database after migration approval/deployment (not in a cross-environment migration):

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.organizations TO gym_test;
GRANT USAGE ON TYPE public.organization_status TO gym_test;
```

Confirm existing schema USAGE without CREATE remains in place. If the verified role has another
name, review the actual role rather than granting to an assumed identity.

```bash
npm run migration:test:deploy
npm run prisma:generate
npx prettier --write test/integration/organization-test-fixtures.ts test/integration/organization.integration.spec.ts test/unit/organization-schema.spec.ts test/unit/package-exports.spec.ts README.md
npm run format:check
npm run test:unit
npm run test:integration
npm run lint
npm run typecheck
npm run build
```

Generation is required before compilation/tests: existing generated sources do not yet contain
Organization/OrganizationStatus. The current src/index.ts already re-exports the generated public
contract; no private imports, schema copy, new client or hand-edited generated artifacts are needed.
The schema remains additive, but consumers need the migration before querying the new table.
The current API uses a local sibling file dependency, so a rebuilt db package supplies development
exports without a registry lookup. A future immutable release needs a separately reviewed compatible
version/package process; no version is invented or bumped in this step.

Organization integration tests verify the live database safety marker before fixtures, use fictional
gym names, reserve UUIDs/slugs before writes (and track generated UUIDs before commit), and delete only
exact tracked ID/slug pairs. They cover defaults, length/Unicode/blank checks, every reserved slug,
duplicate/concurrent/archived uniqueness, enum/lifecycle persistence, rollback, mapped catalog objects
and sentinel preservation. Suite setup also checks that the organization table and all three named,
validated constraints exist before enabling fixtures or cleanup, so missing migrations fail setup
instead of issuing repeated writes/deletes against an absent table. Existing platform suites remain
regression coverage. Missing constraints,
migrations, generated exports, marker or role grants are failures, not reasons to skip checks.

Do not deploy to development/production or publish based on authored tests alone. After successful
disposable verification, obtain explicit approval for each target and follow expansion deployment
order before consumer rollout. Stop on drift or failed migration; review applied state and use a
forward fix rather than rewriting applied history or dropping a table containing organization data.
Branches, memberships/owners, gym staff, members, subscriptions, payments, frontend and domain
provisioning remain deferred. The Step 11 API exists separately in gym-api; its mutation provider
remains fail-closed until the Step 12 database contract, privileges and API implementation are verified.

## Durable organization audit — Step 12 database review checkpoint

### Actual repository history and current implementation status

The inspected history is `c169ddf` (gym-db) and `9493a57` (gym-api). Both
`20261013203346_harden_organization_constraints` **and**
`20261013204701_enforce_organization_integrity` contain only an empty-migration comment.
Neither enforces organization integrity. Preserve both, plus the already-applied
`20261013195500_create_organizations`, unchanged. The applied state of the newer empty draft is not
known from repository files; do not infer it or replace its checksum. This section supersedes the
older SQL-only draft-generation instructions above for the current Step 12 workflow.

The original Phase A proposed two additive models and tests. The repository now contains
`20261013213208_organization_integrity_and_audit`; its presence is not proof of live deployment or
the custom CHECK/trigger/grant prerequisites below. Preserve its checksum. The API now implements
the supplied-transaction organization audit provider; the operator-only permission-provisioning CLI
remains separate. The archival expansion below requires a new human-generated migration. No live
schema checks, migrations, grants or tests were run by the agent for this expansion.

`OrganizationAuditEvent` maps to `organization_audit_events`: required organization/actor foreign
keys, request ID (1–128 ASCII correlation characters), action, previous/resulting lifecycle state,
action-specific changed fields, bounded prior/resulting names, occurredAt and database-controlled
recordedAt. CREATE maps to `create`, UPDATE to `update`, ACTIVATE to `activate`, SUSPEND to `suspend`,
and ARCHIVE maps to `archive` after the archival expansion is deployed.
Names are included only for creation/renaming; lifecycle metadata does not copy request bodies.
Indexes lead with organization or actor and recordedAt/id; additional recorded-time and request-ID
indexes support controlled investigation/export. These records are platform-managed, not tenant
authorization or a public query interface.

`PlatformAuthorizationAuditEvent` maps to `platform_authorization_audit_events`: required target
staff/role references, one action (`provision_organization_manager`), exact approved permission keys,
actual newly granted keys, authenticated session/effective database role, connected database name,
approval reference (2–120 ASCII change-reference characters), UUID correlation, occurredAt/recordedAt
and outcome (`granted` or `already_granted`). An already-granted outcome has no newly granted keys.
Target staff/role are subjects, not proof of operator authentication. The stamping trigger overwrites
caller identity/timestamp claims with values from the actual connection. This verifies the DB login,
not the individual human using shared credentials: production needs individually attributable
operator access, secret-manager access logs and independently approved change tickets.

All four new FKs use RESTRICT on deletion/update. Organizations, staff and roles with history cannot
be silently cascade-deleted. No updatedAt, arbitrary JSON, tokens, password material, MFA codes,
cookies, headers, session identifiers or unbounded payloads are introduced. UUID defaults remain
Prisma-managed; raw writers must supply their UUIDs. recordedAt defaults alone are insufficient:
the reviewed INSERT triggers below are required to prevent caller-supplied clocks/identities.

### Human preflight: no deployment yet

Confirm `.env.migrations.local` selects the intended **development** branch's direct gym_migrator
connection to gym_dev, with gym_shadow as a different database. gym_test is disposable, not the daily
application database. Neon branch names are not database identity checks; verify the SQL result.
From `api/db`, inspect migration status without sharing passwords:

```bash
npm run migration:status
npx prisma migrate status --config prisma.test.config.ts
```

In Neon SQL Editor, explicitly select development / gym_dev and inspect:

```sql
SELECT current_database(), current_user;
SELECT migration_name, finished_at, rolled_back_at
FROM public._prisma_migrations ORDER BY started_at;
SELECT conname, convalidated, pg_get_constraintdef(oid)
FROM pg_catalog.pg_constraint
WHERE conrelid = to_regclass('public.organizations') ORDER BY conname;

-- Return only identifiers of rows requiring human review. Never rewrite or delete them automatically.
SELECT id FROM public.organizations
WHERE char_length(btrim(name,
  U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
)) = 0 OR char_length(slug) NOT BETWEEN 3 AND 63
OR NOT (slug COLLATE "C" ~ '^[a-z][a-z0-9]*(-[a-z0-9]+)*$')
OR slug IN (
  'admin', 'api', 'app', 'www', 'auth', 'login', 'member', 'members',
  'portal', 'dashboard', 'billing', 'support', 'status', 'static',
  'assets', 'cdn', 'mail', 'dev', 'staging', 'test', 'localhost',
  'account', 'accounts', 'oauth', 'console', 'internal', 'health',
  'metrics', 'production', 'development', 'bootstrap'
);
```

Stop on wrong target, unexpected history/check definitions or incompatible existing rows. Do not
accept a Prisma reset, silently clean existing data, deploy an empty migration, or mark the old empty
migration as enforcement. If checks already exist, review their actual definitions/history before
deciding the new SQL; do not blindly add duplicate names or hide drift with IF NOT EXISTS.

After preflight, the human runs:

```bash
cd /Users/dvniels/Desktop/projects/gym/api/db
npm run prisma:format
npm run prisma:validate
npm run migration:create -- --name organization_integrity_and_audit
```

**STOP. Supply the newly generated migration.sql for review before any deployment.** Prisma generates
the enum/table/index/FK DDL, not the custom checks, triggers or security grants. Do not apply the
generated draft as-is. No agent-created timestamp or fabricated migration file is permitted.
Review object ordering, additive DDL, named/restrictive FKs, no drops/renames of existing identity
tables, existing rows, locks and target-specific role grants. The three organization CHECK additions
and PUBLIC revocation in the earlier section must be included once, after confirming their absence.

### Required custom SQL for the new, unapplied draft — review material only

The following definitions belong **after** the generated audit tables/enums. They are not a separate
migration or permission to execute SQL before review. Existing migration files are never edited.
Array ordering is canonical and intentional, matching the proposed API event contract; no duplicates,
NULL arrays/elements, arbitrary field names or extra permissions are accepted. SQL CHECK expressions
use IS TRUE where nullable values could otherwise pass as UNKNOWN.

```sql
ALTER TABLE public.organization_audit_events
  ADD CONSTRAINT organization_audit_events_request_check CHECK (
    char_length(request_id) BETWEEN 1 AND 128
    AND request_id COLLATE "C" !~ '[^A-Za-z0-9._:-]'
  ),
  ADD CONSTRAINT organization_audit_events_metadata_check CHECK ((
    CASE action::text
      WHEN 'create' THEN previous_status IS NULL AND resulting_status = 'pending'
        AND changed_fields = ARRAY['name','slug','status']::varchar(32)[]
        AND previous_name IS NULL AND resulting_name IS NOT NULL
      WHEN 'update' THEN previous_status IS NOT NULL AND resulting_status = previous_status
        AND changed_fields = ARRAY['name']::varchar(32)[]
        AND previous_name IS NOT NULL AND resulting_name IS NOT NULL
      WHEN 'activate' THEN previous_status IN ('pending','suspended') AND resulting_status = 'active'
        AND changed_fields = ARRAY['status','activatedAt']::varchar(32)[]
        AND previous_name IS NULL AND resulting_name IS NULL
      WHEN 'suspend' THEN previous_status = 'active' AND resulting_status = 'suspended'
        AND changed_fields = ARRAY['status','suspendedAt']::varchar(32)[]
        AND previous_name IS NULL AND resulting_name IS NULL
      WHEN 'archive' THEN previous_status IN ('pending','active','suspended')
        AND resulting_status = 'archived'
        AND changed_fields = ARRAY['status','archivedAt']::varchar(32)[]
        AND previous_name IS NULL AND resulting_name IS NULL
      ELSE false
    END
  ) IS TRUE),
  ADD CONSTRAINT organization_audit_events_names_check CHECK (
    (previous_name IS NULL OR char_length(btrim(previous_name,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
    )) > 0) AND
    (resulting_name IS NULL OR char_length(btrim(resulting_name,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
    )) > 0)
  );

ALTER TABLE public.platform_authorization_audit_events
  ADD CONSTRAINT platform_authorization_audit_events_approval_check CHECK (
    char_length(approval_reference) BETWEEN 2 AND 120
    AND approval_reference COLLATE "C" !~ '[^A-Za-z0-9._:/-]'
  ),
  ADD CONSTRAINT platform_authorization_audit_events_permissions_check CHECK ((
    approved_permission_keys = ARRAY[
      'platform.organizations.create', 'platform.organizations.read',
      'platform.organizations.update', 'platform.organizations.activate',
      'platform.organizations.suspend'
    ]::varchar(80)[]
    AND ((outcome = 'granted' AND granted_permission_keys = approved_permission_keys)
      OR (outcome = 'already_granted' AND granted_permission_keys = ARRAY[]::varchar(80)[]))
  ) IS TRUE);

CREATE FUNCTION public.stamp_organization_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
BEGIN
  NEW.recorded_at := pg_catalog.clock_timestamp();
  RETURN NEW;
END;
$$;
CREATE TRIGGER organization_audit_stamp BEFORE INSERT ON public.organization_audit_events
FOR EACH ROW EXECUTE FUNCTION public.stamp_organization_audit();

CREATE FUNCTION public.stamp_platform_authorization_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
BEGIN
  NEW.recorded_at := pg_catalog.clock_timestamp();
  NEW.operator_session_role := SESSION_USER;
  NEW.operator_database_role := CURRENT_USER;
  NEW.database_name := pg_catalog.current_database();
  RETURN NEW;
END;
$$;
CREATE TRIGGER platform_authorization_audit_stamp
BEFORE INSERT ON public.platform_authorization_audit_events
FOR EACH ROW EXECUTE FUNCTION public.stamp_platform_authorization_audit();

REVOKE ALL ON FUNCTION public.stamp_organization_audit() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.stamp_platform_authorization_audit() FROM PUBLIC;
REVOKE ALL ON TABLE public.organization_audit_events,
  public.platform_authorization_audit_events FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_audit_action,
  public.platform_authorization_audit_action,
  public.platform_authorization_audit_outcome FROM PUBLIC;
```

The required scalar fields are NOT NULL in generated SQL. PostgreSQL array fields may be generated
nullable; IS TRUE equality checks above explicitly reject NULL arrays. Keep all checks validated.
The DB validates event shape, not the truth of an arbitrary SQL writer's narrative. Normal API and
CLI implementations must record the actual prior/resulting state in the same transaction; a failed
insert/late error must roll back the mutation/grant. Never record success out-of-band or retry a
failed grant as though it committed. occurredAt is application operation time, recordedAt is the
database ingestion clock; neither timestamp is a global transaction-order guarantee.

### Archival expansion and runtime write rollout

The API now records organization mutations using the existing audit table in the SAME transaction.
Archival preserves the organization, actor references, slug and audit history. It needs the new
`OrganizationAuditAction.ARCHIVE` enum member; it does not delete rows or grant runtime DELETE.
Before using the updated API, a human must complete these steps on the approved development target.
Production is a separate reviewed rollout, never a fallback target for development commands.

1. Inspect `.env.migrations.local` locally without sharing credentials. DIRECT_DATABASE_URL must
   select gym_dev as gym_migrator; TEST_MIGRATION_DATABASE_URL must select the marked gym_test.
   SHADOW_DATABASE_URL must select the disposable gym_shadow, never gym_dev or production.
2. Inspect deployed migration status and actual audit definitions using the read-only preflight below.
   Confirm the request/names CHECKs and stamping trigger are installed and validated. If absent,
   include the missing reviewed definitions from this README in a NEW forward migration, never
   change an applied file or bypass the checks. Stop if existing data violates the intended checks.
3. Generate the archival migration draft, then stop for SQL review:

```bash
cd /Users/dvniels/Desktop/projects/gym/api/db
npm run prisma:format
npm run prisma:validate
npm run migration:status
npm run migration:create -- --name add_organization_archival_audit
```

Do not accept a reset or use db push. The generated draft should add only the `archive` enum label.
If it proposes dropping objects or unrelated changes, stop and resolve drift. In that NEW unapplied
draft, extend the metadata CHECK to the complete `CASE action::text` definition above (including
archive). Replace the existing named metadata CHECK only after inspecting its definition; if absent,
add it and the other missing prerequisites. Preserve all existing action branches, validated state,
request/name checks, foreign keys and stamping triggers. Text comparison deliberately avoids using
the new enum literal as an enum value before the enum-addition transaction commits. Do not merely
add the enum: an older metadata CHECK will reject every archive event.

Read-only Neon SQL Editor preflight (development branch, gym_dev, authorized schema owner):

```sql
SELECT current_database(), current_user;
SELECT conname, convalidated, pg_get_constraintdef(oid) AS definition
FROM pg_catalog.pg_constraint
WHERE conrelid = to_regclass('public.organization_audit_events') AND contype = 'c';
SELECT tgname, tgenabled, pg_get_triggerdef(oid) AS definition
FROM pg_catalog.pg_trigger
WHERE tgrelid = to_regclass('public.organization_audit_events') AND NOT tgisinternal;
SELECT enumlabel
FROM pg_catalog.pg_enum
WHERE enumtypid = 'public.organization_audit_action'::regtype
ORDER BY enumsortorder;
```

After the new draft is reviewed, the human deploys to development and its independently verified
test database, then regenerates the local package before API compilation:

```bash
npm run migration:deploy
npm run migration:test:deploy
npm run prisma:generate
npm run format
npm run lint
npm run typecheck
npm run test:unit
npm run test:integration
npm run build
```

Any other disposable database used by bootstrap tests must receive the reviewed migrations via
its own verified migration URL. Do not point those tests at gym_dev. Organization and authorization
audit integration tests use the existing restricted `gym_test` connection and safety marker.

The following targeted runtime grants address missing organization write/audit privileges, not
superadmin identity. Run them only after reviewing gym_app membership/ownership and existing ACLs.
Use Neon SQL Editor on development / gym_dev as the authorized owner, never the API connection.
The transaction guard refuses a differently named database; independently confirm the branch too.

```sql
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'gym_dev' THEN
    RAISE EXCEPTION 'Expected development gym_dev; refusing runtime grants';
  END IF;
END $$;
GRANT USAGE ON SCHEMA public TO gym_app;
GRANT SELECT, INSERT, UPDATE ON TABLE public.organizations TO gym_app;
GRANT SELECT, INSERT ON TABLE public.organization_audit_events TO gym_app;
GRANT USAGE ON TYPE public.organization_status, public.organization_audit_action TO gym_app;
REVOKE DELETE, TRUNCATE, TRIGGER ON TABLE public.organizations FROM gym_app;
REVOKE UPDATE, DELETE, TRUNCATE, TRIGGER ON TABLE public.organization_audit_events FROM gym_app;
COMMIT;

SELECT
  has_table_privilege('gym_app', 'public.organizations', 'SELECT') AS can_read,
  has_table_privilege('gym_app', 'public.organizations', 'INSERT') AS can_create,
  has_table_privilege('gym_app', 'public.organizations', 'UPDATE') AS can_update,
  has_table_privilege('gym_app', 'public.organization_audit_events', 'INSERT') AS can_append_audit,
  (has_any_column_privilege('gym_app', 'public.organization_audit_events', 'UPDATE')
   OR has_table_privilege('gym_app', 'public.organization_audit_events', 'DELETE,TRUNCATE,TRIGGER'))
    AS can_mutate_audit;
```

Expected: the first four results are true, can_mutate_audit is false. A table REVOKE does not remove
column grants, PUBLIC/inherited access or ownership; stop if the audit mutation check remains true.
Do not use ALL TABLES grants/default privileges: future tables and authorization-audit records need
separate approval. The runtime must remain unable to mutate permissions or erase audit history.
The separate provisioning permission allowlist remains five keys; archival for non-owner staff
requires independent approval and is not silently added to that contract.

### Privilege review and approved role responsibilities

| Role                       | Access expectations                                                                                                                                                                                                 |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| gym_app (platform runtime) | Approved identity/session access; organizations SELECT/INSERT/UPDATE; organization audit SELECT/INSERT only; no RBAC DML, no authorization-audit INSERT, no audit UPDATE/DELETE/TRUNCATE/TRIGGER, no DDL/ownership. |
| gym_migrator               | Human-controlled DDL/grants only; never API or provisioning credentials.                                                                                                                                            |
| gym_security_operator      | Separate human-authorized login; narrow eligibility reads and RBAC SELECT/INSERT plus authorization-audit SELECT/INSERT; no audit UPDATE/DELETE, no DDL/ownership/admin or runtime credential reuse.                |
| gym_test                   | Independently verified disposable gym_test only; explicitly authorized fixture cleanup, not production privileges.                                                                                                  |
| future tenant role         | No global registry or either audit-table grants. Future tenant policies require separate reviewed isolation work.                                                                                                   |

Roles must exist under human control before role-specific grant SQL is approved. Inherited membership,
column-level ACLs, existing broad grants and migrator default privileges can defeat a table REVOKE;
review all of them, plus ownership, database/schema CREATE, superuser/CREATEROLE/CREATEDB/REPLICATION/
BYPASSRLS and predefined read-all/write-all roles. Do not add memberships to gym_migrator,
neondb_owner, neon_superuser, pg_read_all_data or pg_write_all_data. Neon console-created roles may be
administrative; provision restricted logins through SQL under a reviewed human identity. No role
passwords are included here; manage them through protected input/secret management.

After actual role names/membership/ownership are approved, review these **environment-specific**
grants with the migration; they are not permission to change any live role yet:

```sql
REVOKE ALL ON TABLE public.organization_audit_events,
  public.platform_authorization_audit_events FROM gym_app, gym_security_operator;
GRANT SELECT, INSERT ON TABLE public.organization_audit_events TO gym_app;
GRANT USAGE ON TYPE public.organization_audit_action, public.organization_status TO gym_app;
GRANT SELECT, INSERT ON TABLE public.platform_authorization_audit_events TO gym_security_operator;
GRANT USAGE ON TYPE public.platform_authorization_audit_action,
  public.platform_authorization_audit_outcome TO gym_security_operator;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
  public.platform_roles, public.platform_permissions, public.platform_role_permissions,
  public.platform_staff_roles FROM gym_app;
GRANT SELECT ON TABLE public.platform_roles, public.platform_permissions,
  public.platform_role_permissions, public.platform_staff_roles TO gym_security_operator;
GRANT INSERT ON TABLE public.platform_roles, public.platform_permissions,
  public.platform_role_permissions, public.platform_staff_roles TO gym_security_operator;
GRANT SELECT (id, user_id, status, suspended_at) ON public.platform_staff TO gym_security_operator;
GRANT SELECT (id, status, email_verified_at) ON public.users TO gym_security_operator;
GRANT SELECT (user_id, password_changed_at) ON public.password_credentials TO gym_security_operator;
GRANT SELECT (platform_staff_id, verified_at, disabled_at) ON public.platform_totp_credentials
  TO gym_security_operator;
```

Retain required schema USAGE but never CREATE. Revoke organization DELETE/TRUNCATE/TRIGGER for the
runtime. Audit runtime may append organization events but cannot grant permissions; operator may
grant approved permissions but cannot change organizations. Normal application grants must not
include audit deletion. No broad ALL TABLES/schema grants should be added to fix failures.
The reviewed CLI is the control on the exact RBAC keys/target; possession of operator credentials is
itself a powerful capability. Narrow INSERT grants are not database enforcement of every approved
role assignment or mandatory audit against arbitrary operator SQL. Production must restrict human
credential access, approve the command/source, monitor direct SQL and consider a reviewed constrained
database procedure if database-enforced provisioning exclusivity is required.

Privileges protect against ordinary writers, not owners/superusers. A migrator/owner can alter tables,
triggers, ACLs or committed data. Before production establish protected retention periods, backup
and restore verification, privileged-change monitoring, time synchronization, restricted audit-read
access and, where needed, signed/immutable external export. Audit names/identity IDs are retained
personal/business data; privacy owners must approve purpose/retention and controlled erasure handling.

### Disposable test authorization and post-review commands

`organization-audit.integration.spec.ts` uses `TEST_DATABASE_URL` and independently verifies the
existing human-provisioned `TEST_DATABASE_MARKER` through the live connection before writes. This is
the existing disposable `gym_test` database, not another branch/database or a production runtime URL.
Setup fails on missing schema, checks, triggers, a wrong target or an unsafe test role; it never skips
a missing prerequisite.

After SQL review and explicit isolated deployment approval, the human migrator deploys to gym_test,
then an authorized owner applies the separately approved, **gym_test-only** fixture grants:

```sql
GRANT SELECT, INSERT, DELETE ON TABLE public.organization_audit_events,
  public.platform_authorization_audit_events TO gym_test;
GRANT USAGE ON TYPE public.organization_audit_action,
  public.platform_authorization_audit_action, public.platform_authorization_audit_outcome TO gym_test;
```

The test role also requires existing identity/RBAC/organization fixture grants. Because the same
restricted role performs fixture cleanup, this suite does not claim to prove runtime privilege denial
for an independent append-only login. Review `gym_app` effective privileges separately with the
targeted ACL query above. Never copy fixture DELETE grants into `gym_dev` or `gym_prod`.

After review only, in dependency order:

```bash
cd /Users/dvniels/Desktop/projects/gym/api/db
npm run migration:test:deploy
# Apply the separately approved disposable role grants in Neon SQL Editor (gym_test only).
npm run prisma:generate
npx prettier --write test/integration/audit-test-fixtures.ts test/integration/organization-audit.integration.spec.ts test/unit/audit-schema.spec.ts test/unit/package-exports.spec.ts README.md
npm run format:check
npm run lint
npm run typecheck
npm run test:unit
npm run test:integration
npm run build
```

The real PostgreSQL suite covers action/metadata/checks/FKs, forged operator/clock replacement,
organization+audit commit/rollback, authorization+assignment atomicity, failed-audit rollback,
organization and audit PUBLIC ACLs, and scoped sentinel preservation. It reuses the existing safety,
identity and organization fixtures. Audit cleanup reserves UUIDs and matches exact IDs plus parent
identifiers/correlation before deleting; audit cleanup precedes referenced parent cleanup. Runtime
append-only privileges remain an environment-specific operational review because the cleanup role
must delete its own fixtures. The existing organization suite covers the three checks and all 31
reserved slugs. These are authored tests, not passing evidence; strict compilation requires human
client generation first.

Only after successful isolated verification, approved normal-target migration/grants and a rebuilt
public db package may Phase B activate durable API mutations. Keep the local sibling package
workflow; no registry lookup or invented package version is needed. The required Phase B operator
CLI verifies actual database/session/effective role plus independently provisioned marker, rejects
owner/migrator/unsafe memberships, requires interactive operation/target and approval confirmation,
locks concurrent provisioning, selects only a verified active MFA-capable staff identity, creates
only the exact five permissions and dedicated `platform.organization.manager` role, refuses
conflicting existing state, and records assignment/outcome in the same transaction. The
`platform.owner` role remains dashboard-only and is never silently expanded. Failed provisioning
attempts belong in sanitized protected operational monitoring, not falsely committed success events.
Those CLI/provider changes and their API tests are the next phase, not yet implemented or verified.

## Organization ownership and membership foundation (Step 15)

`OrganizationMembership` connects one global `User` to one `Organization` without copying email,
display name, password material or verification state. The same user can hold separate memberships in
Soho Gym and Power Gym, and multiple users can belong to either organization. The database keeps one
durable membership identity per `(organization_id, user_id)` even after revocation; rejoining must use
a separately reviewed workflow rather than silently replacing history.

Membership status maps to the lowercase `organization_membership_status` enum:

- `PENDING`: provisioned but not eligible for tenant access.
- `ACTIVE`: eligible for later authorization evaluation, never sufficient by itself.
- `SUSPENDED`: retained while organization access is temporarily disabled.
- `REVOKED`: retained after access removal.

`created_at` and `updated_at` are required timestamptz(6) values. Nullable `activated_at`,
`suspended_at` and `revoked_at` record lifecycle metadata; status remains authoritative. An ACTIVE
membership still requires an authenticated active User, verified identity, matching active
Organization, applicable organization role and future permission, subscription and feature checks.
A known slug, membership row or client-supplied role name is never authorization.

`OrganizationRole` belongs to exactly one organization. Its key is unique only within that
organization, so each gym may have its own trusted `owner` role. `owner` means gym-level ownership
authority for that organization only: it is not PostgreSQL ownership, NEXCODE platform staff,
`platform.owner`, or authority over another gym. `is_system` records trusted provisioning policy and
grants nothing by itself. Manager, receptionist, trainer, accountant and custom roles are supported by
the model but are neither pre-created nor assigned in this step.

`OrganizationMembershipRole` uses `(organization_id, organization_membership_id,
organization_role_id)` as its primary key. Its two composite foreign keys reference scoped unique
keys on memberships and roles:

- `(organization_id, organization_membership_id)` references the membership's organization and ID.
- `(organization_id, organization_role_id)` references the role's organization and ID.

PostgreSQL therefore rejects a Soho Gym membership paired with Power Gym's OWNER role even when both
global UUIDs exist. All parent relations use `ON DELETE RESTRICT ON UPDATE RESTRICT`; revocation and
ownership transfer must be explicit, authorized and audited rather than implicit cascade deletion.
Organization-leading status/creation and role indexes serve tenant administration. The intentional
user-leading membership index supports discovering organizations for one already verified global
identity; it is not an all-tenant query permission.

Creating an Organization creates no role, membership, owner, User or platform privilege. Existing
zero-owner organizations remain valid. A future onboarding workflow must associate a verified global
identity, create a PENDING membership, provision that organization's system OWNER role, assign it and
activate only after all required checks. Step 16 must first define a dedicated durable ownership audit
contract; existing organization lifecycle audit actions must not be reused to disguise ownership
grants or revocations.

An operational onboarded gym must eventually retain at least one eligible ACTIVE OWNER unless a
separately authorized recovery or transfer process is in progress. A normal unique constraint cannot
enforce that invariant safely. The future mutation workflow requires transaction-safe locking and an
explicit onboarding/operational state or an equivalently reviewed database design. This foundation
does not add a race-prone count-then-update check and does not invalidate current zero-owner gyms.

### Required migration checks and privilege boundary

The human-generated `organization_membership_foundation` migration must contain the generated enum,
tables, organization-leading indexes, scoped unique keys and restrictive composite foreign keys. Add
the following reviewed SQL to that **new, unapplied draft** after its generated table statements:

```sql
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

REVOKE ALL ON TABLE
  public.organization_memberships,
  public.organization_roles,
  public.organization_membership_roles
FROM PUBLIC;

REVOKE ALL ON TYPE public.organization_membership_status FROM PUBLIC;
```

The varchar definitions enforce upper bounds for role key, name and description. The named checks
enforce the lower bounds, stable ASCII key grammar, nonblank human text and OWNER reservation for raw
SQL writers. Review that Prisma emits `organization_memberships_organization_id_key` and
`organization_roles_organization_id_key` before the two composite foreign keys. Do not replace those
foreign keys with independent ID-only references, cascade actions, triggers that silently create
owners, or a seed operation.

These access-control tables must not receive broad schema/table grants. Ordinary tenant runtime
operations receive no unrestricted DML in this step. `TenantTransactionService` safely installs
transaction-local organization context but does not prove membership and no complete RLS policy is
introduced here. Before any tenant API ships, security owners must approve dedicated runtime roles,
role inheritance and ownership, BYPASSRLS posture, fail-closed policies for missing/wrong
`app.current_organization_id`, pooled-connection behavior, and a separate audited provisioning path.
That missing production database authorization boundary is a deployment blocker for tenant access.

### Human migration and disposable-test verification

From `api/db`, first inspect the clean migration history and actual target. The committed
`20261015093808_repair_audit_contract` migration is separate history; never repurpose or edit it after
application. Remove stale shell overrides, format and validate the schema, then generate a new
create-only migration:

```bash
unset DATABASE_URL DIRECT_DATABASE_URL SHADOW_DATABASE_URL
unset TEST_DATABASE_URL TEST_MIGRATION_DATABASE_URL TEST_DATABASE_MARKER

npm run migration:status
npm run prisma:format
npm run prisma:validate
npm run migration:create -- --name organization_membership_foundation
```

Stop after creation and review `migration.sql`. Reject resets, drops, edits to existing User,
Organization, PlatformStaff/PlatformRole or audit objects, missing mapped names, implicit cascades,
ID-only assignment foreign keys, unvalidated checks, owner seeds and unexpected data changes. Confirm
the SQL adds only the new enum/tables/indexes/constraints plus the reviewed custom SQL above. A failed
deployment rolls forward with a new reviewed migration; do not rewrite applied history. This additive
schema remains unusable to consumers until the expansion migration is deployed and Prisma Client is
regenerated. Publish a separately reviewed compatible package release before an external consumer
depends on the new generated models.

After migration review and explicit disposable-database approval, deploy to independently verified
`gym_test`, then have its authorized owner apply only these test-fixture grants:

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.organization_memberships,
  public.organization_roles,
  public.organization_membership_roles
TO gym_test;

GRANT USAGE ON TYPE public.organization_membership_status TO gym_test;
```

To prevent the same omission for later test-only tables, configure default privileges once in
`gym_test` as the role that owns migration-created objects. First confirm that `current_user` is
`gym_migrator`; never run this against `gym_dev` or production. These defaults affect only objects
created later by `gym_migrator` in this database and do not repair existing tables:

```sql
SELECT current_database(), current_user;

ALTER DEFAULT PRIVILEGES FOR ROLE gym_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO gym_test;

ALTER DEFAULT PRIVILEGES FOR ROLE gym_migrator IN SCHEMA public
  GRANT USAGE ON TYPES TO gym_test;

ALTER DEFAULT PRIVILEGES FOR ROLE gym_migrator IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO gym_test;
```

The integration safety layer still verifies effective privileges for each new fixture table before
authorizing writes. Default privileges are preventive, not a substitute for migration review,
PUBLIC revocation, the database marker or the non-administrative test-role checks.

The existing restricted test role must retain its previously reviewed User and Organization fixture
grants. These DELETE privileges exist only for tracked fixture cleanup in `gym_test`; never copy them
to production runtime roles. Integration setup verifies the database marker, table/check/composite-FK
prerequisites and non-administrative role before writes. Cleanup deletes tracked assignments before
their tracked roles and memberships, then tracked organizations and users. The tests establish
relational integrity, concurrency behavior and platform-domain separation; without RLS they do not
prove authorization isolation for a future HTTP API.

Human verification order after migration approval:

```bash
npm run migration:test:deploy
# Apply the separately reviewed gym_test-only grants above in Neon SQL Editor.
npm run prisma:generate
npm run format:check
npm run lint
npm run typecheck
npm run test:unit
npm run test:integration
npm run build
```

Do not deploy to `gym_dev` or `gym_prod`, publish a package, or start ownership onboarding based only
on authored tests. Production rollout separately requires approved runtime/RLS privileges, the Step 16
ownership audit contract, transaction-safe final-owner protection, privacy/retention ownership and an
authorized onboarding API. Membership rows link personal identity to organizations and require
tenant-scoped access, approved retention, audited privileged access and reviewed erasure handling;
archiving or revocation is not legal erasure.

## Secure organization-owner invitations (Step 16, database gate)

`OrganizationOwnerInvitation` is a NEXCODE control-plane offer to begin onboarding a gym owner. It
does not create or activate a `User`, `OrganizationMembership`, organization OWNER role assignment,
credential, tenant session or platform permission. The normalized intended email remains independent
of `User.email`: matching an existing account is not identity proof and must never reset or overwrite
that account. One person may be invited to several organizations, so email is not globally unique.

The invitation lifecycle maps to `organization_owner_invitation_status`:

- `PENDING_DELIVERY` is the only state created in Step 16. No token or delivery timestamps exist.
- `SENT` is reserved for a future approved delivery operation with a token digest, issue time and
  bounded expiry. Plaintext tokens are never persisted or returned by an ordinary API response.
- `ACCEPTED` is reserved for a future verified claim transaction and cannot be reused.
- `REVOKED` invalidates any digest but does not revoke a User, membership or established ownership.

Expiration is derived from `expires_at`; no state-changing GET is required. The initial application
policy may create invitations only for PENDING or ACTIVE organizations. SUSPENDED and ARCHIVED
organizations are denied by the API. This lifecycle eligibility is separate from tenant-login
eligibility and a PENDING organization remains non-operational.

`OrganizationOwnershipAuditEvent` is dedicated owner-onboarding history. Initial actions are only
`INVITATION_CREATED` and `INVITATION_REVOKED`; lifecycle audit actions for organizations are not
reused. Its composite `(organization_id, owner_invitation_id)` foreign key references the invitation's
scoped unique key, preventing an audit from naming an invitation from another organization. The
direct Organization and PlatformStaff references are also restrictive. Metadata is limited to the
previous/resulting invitation states, request identifier and timestamps; token material, credentials,
email OTPs, recipient email and raw requests are deliberately absent.

Creation and revocation must persist the invitation change and its successful ownership audit in one
short database transaction. An audit failure rolls back the invitation change, and a persistence
failure never leaves a false success event. Email is an external side effect and must never execute
inside that transaction. No owner-acceptance page or API currently exists, so delivery remains
disabled and new records remain PENDING_DELIVERY. Do not call the platform-email-OTP transport or send
an unusable link.

### Gate order and generated migration review

Gate A is the locally generated, unapplied
`20261015100212_organization_membership_foundation` migration. It must be reviewed first. Confirm it
contains the four documented organization-role checks, scoped composite foreign keys and PUBLIC
revocations, then apply it to the approved development/test target and regenerate Prisma Client. Do
not generate it twice and do not edit it after application.

Only after Gate A succeeds may a human generate Gate B from `api/db`:

```bash
unset DATABASE_URL DIRECT_DATABASE_URL SHADOW_DATABASE_URL
unset TEST_DATABASE_URL TEST_MIGRATION_DATABASE_URL TEST_DATABASE_MARKER

npm run migration:status
npm run prisma:format
npm run prisma:validate
npm run migration:create -- --name organization_owner_invitations
```

Stop after create-only generation. Reject any reset, drop, seed, data rewrite, cascade, edit to an
existing table beyond relation constraints, or automatic membership/role/User creation. The draft
must add exactly the two enums, invitation table, ownership-audit table, restrictive foreign keys,
scoped unique key and organization-leading indexes represented by the canonical schema. Add the
following reviewed SQL only to that new, unapplied Gate B draft after its generated table statements:

```sql
ALTER TABLE public.organization_owner_invitations
  ADD CONSTRAINT organization_owner_invitations_email_check CHECK (
    char_length(invited_email::text) BETWEEN 3 AND 254
    AND invited_email::text = lower(btrim(invited_email::text))
  ),
  ADD CONSTRAINT organization_owner_invitations_display_name_nonblank_check CHECK (
    char_length(btrim(invited_display_name,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
    )) > 0
  ),
  ADD CONSTRAINT organization_owner_invitations_lifecycle_check CHECK ((
    CASE status
      WHEN 'pending_delivery' THEN token_digest IS NULL AND expires_at IS NULL
        AND sent_at IS NULL AND accepted_at IS NULL AND revoked_at IS NULL
      WHEN 'sent' THEN token_digest IS NOT NULL AND char_length(token_digest) BETWEEN 64 AND 128
        AND expires_at IS NOT NULL AND sent_at IS NOT NULL
        AND accepted_at IS NULL AND revoked_at IS NULL
      WHEN 'accepted' THEN token_digest IS NULL AND expires_at IS NOT NULL
        AND sent_at IS NOT NULL AND accepted_at IS NOT NULL AND revoked_at IS NULL
      WHEN 'revoked' THEN token_digest IS NULL AND accepted_at IS NULL AND revoked_at IS NOT NULL
      ELSE false
    END
  ) IS TRUE),
  ADD CONSTRAINT organization_owner_invitations_timestamp_order_check CHECK (
    (sent_at IS NULL OR sent_at >= created_at)
    AND ((sent_at IS NULL) = (expires_at IS NULL))
    AND (expires_at IS NULL OR expires_at > sent_at)
    AND (accepted_at IS NULL OR (
      accepted_at >= sent_at AND accepted_at <= expires_at
    ))
    AND (revoked_at IS NULL OR (
      revoked_at >= created_at AND (sent_at IS NULL OR revoked_at >= sent_at)
    ))
  );

CREATE UNIQUE INDEX organization_owner_invitations_outstanding_email_key
  ON public.organization_owner_invitations (organization_id, invited_email)
  WHERE status IN ('pending_delivery', 'sent');

CREATE FUNCTION public.guard_organization_owner_invitation_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
    OR NEW.invited_email IS DISTINCT FROM OLD.invited_email
    OR NEW.invited_by_platform_staff_id IS DISTINCT FROM OLD.invited_by_platform_staff_id
  THEN
    RAISE EXCEPTION 'organization owner invitation identity is immutable'
      USING ERRCODE = '23514',
        CONSTRAINT = 'organization_owner_invitation_identity_guard';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER organization_owner_invitation_identity_guard
BEFORE UPDATE ON public.organization_owner_invitations
FOR EACH ROW EXECUTE FUNCTION public.guard_organization_owner_invitation_identity();

ALTER TABLE public.organization_ownership_audit_events
  ADD CONSTRAINT organization_ownership_audit_events_request_check CHECK (
    char_length(request_id) BETWEEN 1 AND 128
    AND request_id COLLATE "C" !~ '[^A-Za-z0-9._:-]'
  ),
  ADD CONSTRAINT organization_ownership_audit_events_metadata_check CHECK ((
    CASE action
      WHEN 'invitation_created' THEN previous_invitation_status IS NULL
        AND resulting_invitation_status = 'pending_delivery'
      WHEN 'invitation_revoked' THEN previous_invitation_status IN ('pending_delivery', 'sent')
        AND resulting_invitation_status = 'revoked'
      ELSE false
    END
  ) IS TRUE);

CREATE FUNCTION public.stamp_organization_ownership_audit_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  NEW.recorded_at := clock_timestamp();
  RETURN NEW;
END;
$function$;

CREATE TRIGGER organization_ownership_audit_stamp
BEFORE INSERT ON public.organization_ownership_audit_events
FOR EACH ROW EXECUTE FUNCTION public.stamp_organization_ownership_audit_event();

REVOKE ALL ON TABLE
  public.organization_owner_invitations,
  public.organization_ownership_audit_events
FROM PUBLIC;

REVOKE ALL ON TYPE
  public.organization_owner_invitation_status,
  public.organization_ownership_audit_action
FROM PUBLIC;

REVOKE ALL ON FUNCTION
  public.guard_organization_owner_invitation_identity(),
  public.stamp_organization_ownership_audit_event()
FROM PUBLIC;
```

The partial unique index serializes concurrent outstanding invitations for one organization/email
without preventing the same person from being invited to another gym or a later reinvitation after
the prior row is ACCEPTED/REVOKED. CITEXT provides case-insensitive comparison while the named check
requires the canonical lowercase, trimmed representation. The identity trigger blocks silent
organization, recipient-email or initiating-actor rewrites. The lifecycle checks reserve future SENT
and ACCEPTED states but do not implement them.

The base invitation migration was applied to the approved development database before this custom
SQL was added. Its checksum remains unchanged. The generated forward-only repair is
`20261015105926_harden_organization_owner_invitations`; it contains the schema-derived
organization/action/time index and the complete reviewed hardening SQL above. Do not move these
statements into the applied base migration or resolve its checksum.

For another environment that already contains the base migration, deploy the committed forward
migration in normal order. If an equivalent recovery must ever be regenerated from the canonical
schema before this repair is committed, use:

```bash
npm run migration:deploy
npm run migration:create -- --name harden_organization_owner_invitations
```

The forward migration must contain the organization/action/time investigation index and the complete
reviewed hardening SQL. Stop before applying it and inspect the resulting SQL as one unit. Deploy that
forward migration to every database that received the incomplete base migration. This recovery
preserves immutable migration history and gives every environment the same final constraints,
partial uniqueness, triggers and PUBLIC revocations.

### Runtime privileges, RLS limitation and disposable tests

Owner invitations contain personal information and access-control intent. Grant no access to normal
gym tenant roles. After the migration is approved and deployed, an authorized database owner applies
the following separately reviewed control-plane grants to the platform runtime role in each intended
database. Revoke first to clear historical grants made directly to `gym_app`; inherited privileges
must be inspected separately because revoking from this role does not revoke access inherited through
another role:

```sql
REVOKE ALL ON TABLE
  public.organization_owner_invitations,
  public.organization_ownership_audit_events
FROM gym_app;

GRANT SELECT, INSERT
ON TABLE public.organization_owner_invitations
TO gym_app;

GRANT UPDATE (
  status,
  token_digest,
  expires_at,
  sent_at,
  accepted_at,
  revoked_at,
  updated_at
)
ON TABLE public.organization_owner_invitations
TO gym_app;

GRANT SELECT, INSERT
ON TABLE public.organization_ownership_audit_events
TO gym_app;

GRANT USAGE ON TYPE
  public.organization_owner_invitation_status,
  public.organization_ownership_audit_action
TO gym_app;
```

Do not grant direct function execution: PostgreSQL invokes the already-installed trigger functions
through their triggers, while direct calls remain unavailable after PUBLIC revocation. Verify actual
ownership, inherited roles, BYPASSRLS and default privileges before production. In particular,
confirm that `gym_app` has no table-level UPDATE, DELETE, TRUNCATE or TRIGGER privilege on either
table and has UPDATE only on the seven invitation lifecycle columns above. These grants make routine
audit access append-only but cannot make infrastructure immutable from a database owner or superuser.
No permissive RLS policy is introduced, and `TenantTransactionService` alone is not platform
authorization.

After Gate B review and explicit approval, deploy both gates to the independently marked disposable
test database. Its authorized owner may apply only these test-fixture privileges:

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.organization_owner_invitations,
  public.organization_ownership_audit_events
TO gym_test;

GRANT USAGE ON TYPE
  public.organization_owner_invitation_status,
  public.organization_ownership_audit_action
TO gym_test;

GRANT EXECUTE ON FUNCTION
  public.guard_organization_owner_invitation_identity(),
  public.stamp_organization_ownership_audit_event()
TO gym_test;
```

If the Step 15 grants were skipped earlier, apply both the Step 15 and Step 16 blocks in the same
reviewed `gym_test` maintenance session. The direct grants repair existing tables; the default
privileges documented in Step 15 protect future migration-owned test tables. A `42501 permission
denied` error means the direct grants are still missing or were applied in a different database.

DELETE exists only so tests can remove their explicitly tracked invitation/audit UUIDs. Never copy it
to a runtime or production audit role. Integration setup verifies the independent database marker,
tables, named checks, partial index and triggers before authorizing fixture writes. Cleanup removes
tracked audit children before invitations, then existing fixture managers remove tracked
organizations and platform identities. It never performs table-wide cleanup.

Human verification after the approved Gate B migration is deployed:

```bash
npm run migration:test:deploy
# Apply the reviewed gym_test-only grants above in Neon SQL Editor.
npm run prisma:generate
npm run format:check
npm run lint
npm run typecheck
npm run test:unit
npm run test:integration
npm run build
```

Do not activate the API integration until the migrated package is generated, verified and made
available to `gym-api` through its approved sibling/package workflow. A future acceptance transaction
must independently authenticate/verify the recipient, safely resolve or create the global User,
establish the organization-scoped system OWNER role and membership through the existing composite
keys, consume the invitation and append a dedicated ownership audit atomically. It must reject
expired/revoked/used tokens and must not overwrite an existing account. Owner revocation/transfer and
last-owner protection remain future work requiring transaction-safe locking and a reviewed recovery
procedure; current zero-owner organizations remain valid.

## Owner invitation delivery foundation (Step 18, migration review checkpoint)

The original Step 18 Phase A proposed the following schema; see the Step 19 prerequisite review below
for the subsequently applied migration and outstanding hardening. The Prisma schema defines
`OrganizationOwnerInvitationDelivery` as a durable outbox/reservation owned by one Organization and
one existing invitation. The composite invitation foreign key prevents cross-organization attachment,
and a unique `(organization_id, owner_invitation_id)` key makes repeated administrative requests
resolve to the same reservation instead of producing duplicate emails. This record does not grant a
User, membership, OWNER role, credential or session.

The delivery lifecycle is separate from the invitation lifecycle:

- `QUEUED` is eligible for a future atomic worker claim.
- `PROCESSING` has one bounded lease and an incremented attempt count.
- `CONFIRMED` means the provider accepted the API request; it does not prove inbox delivery.
- `FAILED` records a classified known failure and may carry one bounded future retry.
- `UNCERTAIN` records an outcome such as an HTTP timeout where blind retry is unsafe.

An invitation remains `PENDING_DELIVERY` until provider acceptance is finalized. Finalization must
atomically recheck the invitation is still pending, move it to `SENT` with its digest and expiry,
mark the delivery `CONFIRMED`, and erase recoverable token material. A concurrent revocation wins if
that eligibility recheck updates no row. PostgreSQL and Resend cannot provide exactly-once delivery;
stable provider idempotency plus explicit `UNCERTAIN` reconciliation limits, but cannot eliminate,
that boundary.

`INVITATION_DELIVERY_QUEUED` records the authenticated platform administrator who authorized queueing.
It keeps both invitation statuses at `PENDING_DELIVERY`. Worker claims, provider acceptance and later
recipient verification are not falsely attributed to that administrator. Delivery attempt/status
columns are the durable operational record for worker and provider outcomes. Recipient acceptance
still requires a future audit design with the verified recipient User as actor.

### Token envelope and retention contract

The future API must generate an opaque token with at least 256 bits of CSPRNG entropy and calculate a
purpose-separated HMAC digest. Only the digest is copied to the invitation when delivery is confirmed.
Before delivery, the recoverable token is stored only as authenticated ciphertext with a 96-bit IV,
128-bit authentication tag, explicit key ID and format version. Associated data must bind at least the
delivery ID, organization ID, invitation ID and the fixed owner-invitation purpose label.

The encryption key belongs to a server-managed keyring, never this package or the database. New writes
use the active key; workers may decrypt with retained read keys during rotation. A key cannot be removed
until no unexpired delivery envelope references it. `CONFIRMED` and terminal `FAILED` rows erase the
delivery copy of the digest and all encryption fields, then set `token_erased_at`. The invitation keeps
the digest only after a confirmed `SENT` transition. `UNCERTAIN` may retain its envelope for bounded manual
provider reconciliation and must never be automatically resent. Expired envelopes require a controlled
terminal cleanup that preserves non-secret delivery metadata and audit history.

The digest and ciphertext are both sensitive. Neither is permitted in logs, audit metadata, API
responses, analytics, correlation IDs or exception messages. Database backups may retain historical
ciphertext, so key retirement and backup retention are part of the operational erasure model.

### Historical foundation generation (do not repeat)

This section describes the original Step 18 checkpoint only. That foundation and the Step 19
foundation are now committed. **Do not run their create commands again.** Use the Step 21 forward
repair checkpoint below, after independently reviewing actual migration history.

The foundation generation command has been removed because that file already exists. Its applied
SQL is immutable and contains the enum/table/indexes/restrictive foreign keys and the new audit enum
value. Put the missing checks, transition guards and PUBLIC revocations in a separate reviewed forward
repair. See the Step 21 checkpoint below. Never accept a reset prompt, use `db push`, hand-create a
timestamped directory or regenerate the foundation to supply missing SQL-only integrity objects.

Prisma will not generate the required lifecycle checks or transition guard. During SQL review, the
draft must receive six validated named checks covering:

- lifecycle metadata for every delivery status;
- all-or-none lease fields and a positive lease interval;
- `0 <= attempt_count <= max_attempts`, with a reviewed `max_attempts` range of 1 through 10;
- all-or-none authenticated-encryption fields, exact 12-byte IV and 16-byte tag sizes, bounded
  ciphertext/key ID, and a positive format version;
- expiry and outcome timestamp ordering; and
- bounded ASCII provider idempotency/message IDs, worker IDs and uppercase error classifications.

The required names are:

```text
organization_owner_invitation_deliveries_lifecycle_check
organization_owner_invitation_deliveries_lease_check
organization_owner_invitation_deliveries_retry_check
organization_owner_invitation_deliveries_token_material_check
organization_owner_invitation_deliveries_timestamp_order_check
organization_owner_invitation_deliveries_bounded_text_check
```

The reviewed transition trigger must make organization, invitation, requesting administrator,
provider idempotency key, token digest, token expiry and maximum attempts immutable; reject decreasing
attempt counts; reject worker processing after the invitation leaves `PENDING_DELIVERY`; and allow
`CONFIRMED` only after the same invitation is atomically `SENT` with the matching digest and expiry.
It must permit only the reviewed queue, processing, retry, terminal and reconciliation transitions.
This trigger is defense in depth; the worker must still use conditional updates and short database
transactions, and must never hold a transaction open during the Resend HTTP request.

The existing `organization_ownership_audit_events_metadata_check` must be replaced in the same
reviewed migration so `invitation_delivery_queued` requires both previous and resulting invitation
status to be `pending_delivery`. Existing creation and revocation branches must remain unchanged.
PUBLIC must receive no table/type/function privileges for the delivery objects. No environment role
names belong in the portable migration.

### Runtime and disposable-test privileges

After migration approval and deployment to an explicitly selected target, separately review the
platform runtime role. The intended minimum is SELECT/INSERT plus narrowly approved UPDATE columns on
the delivery table; it must not receive DELETE, TRUNCATE, TRIGGER, DDL, table ownership or tenant-role
inheritance. The dispatcher needs only the fields required to claim leases and record classified
outcomes. Audit remains append-only and invitation lifecycle UPDATE remains restricted as documented
in Step 16. Verify inherited grants, default privileges and BYPASSRLS rather than relying on direct
grants alone.

Only in the independently marked disposable `gym_test` database, after the reviewed migration is
deployed, its existing restricted test role needs:

```sql
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.organization_owner_invitation_deliveries
TO gym_test;

GRANT USAGE
ON TYPE public.organization_owner_invitation_delivery_status
TO gym_test;
```

If the verified test role has a different name, substitute only that inspected role. Never copy the
test DELETE grant into development runtime or production. Existing Step 15/16 test grants remain
required because the focused suite creates explicitly tracked organizations, staff, invitations and
audits, then deletes children before parents by reserved UUID only.

After SQL approval, target verification, migration deployment and those test-only grants, the human
runs:

```bash
npm run migration:test:deploy
npm run prisma:generate
npm run format:check
npm run lint
npm run typecheck
npm run test:unit
npm run test:integration
npm run build
```

The integration suite verifies the disposable marker and live prerequisites before writes. It covers
tenant-scoped relations, duplicate reservations, concurrent claims, expired-lease recovery, atomic
provider finalization, revocation races, retry/uncertain outcomes, audit rollback, encrypted-material
cleanup, PUBLIC revocation and scoped fixture cleanup. Authored tests do not prove deployment.

### API and release blockers

No Step 18 API functionality is activated at this checkpoint. `gym-api` work starts only after the
human approves the generated migration, deploys it to the verified disposable target, regenerates the
client, verifies this package and makes the compatible package available. Live delivery must remain
disabled until a separate owner-facing acceptance page is implemented and reviewed, an approved fixed
HTTPS acceptance origin and sender domain exist, cryptographic keys are provisioned, provider sandbox
tests pass, and production runtime privileges are approved.

The later preview endpoint may reveal only generic validity and the minimum reviewed gym display
information. It must issue no cookie/session, modify no User, create no membership, grant no OWNER role
and reveal no account-existence signal. Future acceptance must independently authenticate and verify
the recipient's mailbox, bind the correct global User, establish membership/OWNER authorization and
consume the invitation in one audited transaction. That acceptance transaction is not Step 18 Phase A.

## Owner enrollment and recipient acceptance (Step 19, database checkpoint)

This section describes the Phase A schema proposal and authored tests. The acceptance API, new-user
enrollment, existing-user authentication and mailbox verification are not operational. No tenant or
platform session is issued. The owner-facing application is still absent. Step 19 section 26 requires
SQL review before the API phase begins.

### Step 18 prerequisite discovered during inspection

`20261015233646_owner_invitation_delivery_foundation` now exists and the developer confirmed it has
already been applied to a database. Preserve its checksum. Its checked-in SQL contains the delivery
enum/table/indexes/foreign keys, but none of the six delivery CHECK constraints, the transition guard,
the queue-audit metadata update or PUBLIC revocations specified above. A committed migration does not
prove those objects exist. A separate human-generated forward repair is required; never modify that
applied migration or generate the foundation twice. Its applied state on every target remains
unverified. The owner-delivery API, worker and preview endpoint are also absent in the inspected API.

Both foundation files now exist in history, and neither may be regenerated or rewritten. Their
presence does not establish their deployed state. Step 21 requires reviewing pending history before
any create-only command; the delivery-only repair must not silently deploy the unreviewed enrollment
foundation. Keep enrollment and delivery hardening separately reviewed. No migration has been
generated by the agent.

### Narrow proof persistence and actor integrity

`OrganizationOwnerEnrollmentChallenge` stores the organization, scoped invitation, purpose,
optionally resolved User, an erasable challenge-token digest, bounded attempts and proof timestamps.
The purpose distinguishes `NEW_USER_ENROLLMENT` from `EXISTING_USER_AUTHENTICATION`. Its status is
`PENDING`, `VERIFIED`, `CONSUMED` or `REVOKED`. Expiration remains an absolute timestamp; no background
job is needed to make an expired proof invalid. No plaintext OTP, invitation token, password, password
hash, platform cookie or tenant session belongs in this model.

`OrganizationOwnerAcceptanceAuditEvent` identifies the actual recipient through `actorUserId` and
has its own action, `OWNER_INVITATION_ACCEPTED`. Existing administrator audits remain unchanged.
Composite foreign keys bind `(organization, invitation, challenge, recipient)` and
`(organization, membership, recipient)`. A new membership unique key includes its User specifically
to support this database-enforced actor check. The audit permits only one acceptance per organization
and invitation. Every relationship uses RESTRICT. No platform administrator is substituted for the
recipient and no platform role is assigned.

The proof timestamps are persisted evidence references, not proof by themselves. A future trusted
verifier must authenticate their source. SQL cannot establish that a human supplied the correct
password, mailbox proof or MFA merely because an application wrote a timestamp. Runtime privileges,
the verifier interface and the acceptance transaction must protect that boundary together.

### Required migration review contract

The future `owner_enrollment_acceptance_foundation` draft must add only the three enums, two models,
their indexes and restrictive foreign keys, the membership composite unique key, and the following
reviewed integrity/security additions. Do not deploy raw Prisma output without them. Existing rows
and applied migration SQL must be preserved. Explicit mapped names must fit PostgreSQL's 63-byte
identifier limit; the existing schema-wide byte-length regression test covers these additions.

Required validated CHECK names and behavior:

- `owner_enrollment_challenges_digest_check`: live challenges have a lowercase 64-character HMAC
  digest; terminal challenges erase it. No plaintext token is accepted as a digest.
- `owner_enrollment_challenges_attempts_check`: `max_attempts` is 1–10, `failed_attempts` is 0 through
  that maximum, and VERIFIED/CONSUMED challenges have not exhausted their attempts.
- `owner_enrollment_challenges_lifecycle_check`: PENDING has no verified/consumed/revoked timestamp;
  VERIFIED requires resolved User, mailbox proof, authentication and verified timestamp; CONSUMED
  additionally requires consumption and cleared digest; REVOKED requires revocation, cleared digest
  and no consumption. Proof timestamps must be internally consistent.
- `owner_enrollment_challenges_timestamps_check`: absolute lifetime is positive and at most 15
  minutes; proof and consumption timestamps occur within that lifetime, verification follows mailbox
  and authentication evidence, step-up precedes verification, and revocation follows creation.
- `owner_acceptance_audit_events_request_check`: correlation IDs are 1–128 allowlisted ASCII
  characters (`A-Z`, `a-z`, digits, `.`, `_`, `:`, `-`). Audit time must be coherent with consumption.

Nullable CHECK expressions must use `IS TRUE` where UNKNOWN would otherwise permit malformed data.
The `owner_enrollment_challenge_guard` trigger must preserve organization, invitation, purpose,
creation/expiration, maximum attempts and existing non-null resolved User identity. It must reject
decreasing attempts, digest replacement, terminal-state reuse and verification without an eligible
verified User whose email matches the immutable invited email. Creating a PENDING proof is not a
claim that verification succeeded. On transition to VERIFIED or CONSUMED, lock and recheck the
invitation, current database time, User and Organization. Reject expiry, exhausted attempts,
revocation, non-SENT invitations, SUSPENDED/ARCHIVED organizations and mismatched identity. Allow
PENDING to VERIFIED/REVOKED and VERIFIED to CONSUMED/REVOKED only; terminal rows cannot regain a token.
Bind a User only once and do not allow replacing the evidence after verification.

`owner_acceptance_audit_stamp` assigns `recorded_at` with `clock_timestamp()`, overriding supplied
timestamps. `owner_acceptance_audit_guard` must verify the same recipient, accepted invitation,
consumed challenge, eligible Organization, active membership and exact organization-scoped system
OWNER assignment exist in the transaction. Reject inconsistent historical success claims. The audit
insert is the last write in the acceptance transaction; if it fails, every ownership write rolls
back. Its recorded time must not predate consumption. Database-owner access remains an operational
trust boundary; normal runtime roles cannot update or delete acceptance audits.

Revoke PUBLIC access to the two tables, three enum types and all new trigger functions. Do not add
permissive RLS policies or embed environment-specific role names in migrations. Review inherited and
default grants, table ownership and BYPASSRLS. The normal runtime role needs approved SELECT/INSERT
on acceptance audits and minimal challenge DML, never audit UPDATE/DELETE/TRUNCATE/TRIGGER or DDL.
The schema proposal is not permission to extend runtime grants before the identity flow is reviewed.

### Acceptance and identity contracts for the later API phase

The new-account verifier must establish mailbox control, apply the existing approved password policy
and Argon2id implementation, and establish a verified enrollment context. Account creation and
credential insertion must use database uniqueness and an atomic strategy. If the email already
exists, fail generically and require the separately authenticated existing-account path; never
overwrite its credentials, verified email, status or MFA requirements. Do expensive password hashing
before the short ownership transaction, and do not persist a pending password in a challenge.

The existing-account verifier must supply a fresh global User authentication proof and verified
matching email, including required MFA/step-up. No reusable non-platform authentication provider
exists in the inspected API, so that interface must fail with a safe unavailable response until an
approved implementation exists. The platform administration cookie cannot satisfy that interface.
An invitation token or successful preview alone never authenticates an existing account.

The future acceptance service must use one short transaction with a documented lock order:
Organization, invitation, User, challenge, membership/role. Recheck current database time and all
eligibility after acquiring locks. PENDING and ACTIVE Organizations may enroll an owner; their status
must not change. Consume the VERIFIED challenge while its invitation is still SENT, conditionally
consume the same unexpired invitation and clear its digest, find/create the exact `owner`/`Owner`/
`isSystem=true` role, establish the matching active membership and assignment, then insert the
recipient acceptance audit. A failed guard or insert rolls everything back. Database uniqueness and
locks arbitrate duplicate roles, memberships and submissions. Return a conflict on replay; do not
report success on an ambiguous commit timeout or blindly retry it.

For existing memberships, PENDING may activate after proof, ACTIVE may gain OWNER only if it has no
existing OWNER assignment, and SUSPENDED/REVOKED are denied. A redundant OWNER acceptance is a
conflict. Keep other roles intact. Do not activate the Organization, add subscriptions, issue a
tenant session or add platform privileges. Lock the live User and Organization during acceptance so
concurrent suspension or email change cannot invalidate an earlier unprotected check.

No owner-enrollment endpoints are registered in Phase A. Future preview, challenge start/verify and
acceptance contracts require strict bounded DTOs, generic enumeration-safe errors, rate limiting,
no-store, approved HTTPS origin and reviewed cookie/CSRF handling. Browser cookie scope remains
undecided until the owner-facing origin is approved. A configuration switch alone cannot satisfy
missing delivery, mailbox verification, authentication, migration or audit prerequisites.

### Retention and disposable verification

Challenge validity defaults to ten minutes and is capped at fifteen. Erase its digest immediately
on consumption/revocation. A controlled cleanup may revoke and erase expired unconsumed challenges;
hard-delete expired, unaudited challenges after a proposed 24-hour diagnostic window only under the
approved retention policy. Acceptance-linked challenges remain minimal referenced evidence; keep
their credential digest erased and retain their metadata under the same reviewed schedule as the
acceptance audit. Audit and expired invitation retention require an explicit security/privacy policy
before release, including backup treatment. Never silently purge successful audit history. Pending
global-account retention belongs to the future enrollment design; no pending global accounts are
created by this phase.

The authored database tests use only fictional recipients and the independently verified disposable
database. Synthetic SENT/proof fixtures test persistence contracts; they are not provider delivery or
authentication evidence for a development account. Setup requires all checks, triggers and fixture
privileges before writes. Cleanup removes explicitly reserved acceptance-audit and challenge UUIDs,
then tracked memberships/roles, invitations, organizations and Users. A sentinel test protects other
records. The suite covers cross-organization references, proof identity, expiration, attempt bounds,
single consumption, concurrent acceptance, revocation before/during acceptance, rollback, restricted parent
deletion, recipient audit identity and PUBLIC revocation. HTTP/authentication tests belong to Phase B.

The Step 19 foundation already exists; its generation command has been removed. After the Step 21
repair, use status and deployment review instead:

```bash
cd /Users/dvniels/Desktop/projects/gym/api/db
unset DATABASE_URL DIRECT_DATABASE_URL SHADOW_DATABASE_URL
unset TEST_DATABASE_URL TEST_MIGRATION_DATABASE_URL TEST_DATABASE_MARKER
npm run migration:status
npm run prisma:format
npm run prisma:validate
```

**Stop for SQL review.** `migration:create` can apply earlier pending migrations while generating a
draft. Do not run it while an incomplete foundation or an unapproved repair is pending.
Do not generate a duplicate Step 19 migration. After SQL approval, independently verify the
disposable target and deploy the reviewed migrations. Its restricted test role needs explicit DML
for tracked fixture cleanup on the two new tables and USAGE on the three new enum types. Reuse the
existing test role; no new audit URL or administrative test identity is needed. Keep normal runtime
audit grants append-only and review those effective privileges separately.

```bash
npm run migration:test:deploy
# Human: apply the separately approved gym_test-only grants after selecting gym_test in Neon.
npm run prisma:generate
npm run format:check
npm run lint
npm run typecheck
npm run test:unit
npm run test:integration
npm run build
```

Compatible generated client/package exports are required before running tests that reference the new
models. No generated client, migration, database access, verification command or Git write was
executed by the agent. Keep API activation blocked until Step 18 delivery and the recipient verifier,
approved owner origin, both migration contracts, runtime privileges and acceptance audit have been
verified. After that checkpoint, the API human checks are `npm run format:check`, `npm run lint`,
`npm run typecheck`, `npm run test:unit`, `npm run test:integration`, `npm run test:e2e` and
`npm run build` from `api/api` with its compatible database package. Do not start Step 20 here.

## Step 21: forward delivery-integrity repair (SQL review checkpoint)

Inspected repository heads: gym-db `6bd4e1b` and gym-api `4bb4ccf`, both on `main`. The API still has
only invitation creation, listing and audited revocation. Its existing MFA Resend adapter is not an
invitation sender. The frontend is inspection-only in this step. API delivery, token/envelope
utilities, dispatching and preview are deferred until this database checkpoint is approved; no
runtime flag, worker, email or acceptance endpoint is activated by this proposal.

The applied foundation `20261015233646_owner_invitation_delivery_foundation` must remain byte-for-byte
unchanged. The six documented constraint identifiers already fit PostgreSQL's 63-byte limit; no
shortening or silent identifier truncation is required. The proposed function and trigger names
below are also below that limit. This repair changes no Prisma models, columns, indexes or enums.
The existing composite foreign key and unique organization/invitation reservation remain authoritative.

### Human checkpoint before creating the repair

Review the development/shadow connection targets locally without sharing passwords. In the Neon
SQL editor, select the intended development branch and database and run these read-only checks:

```sql
SELECT current_database() AS database_name, current_user AS connected_role;
SELECT migration_name, checksum, finished_at, rolled_back_at
FROM public._prisma_migrations
WHERE migration_name IN (
  '20261015233646_owner_invitation_delivery_foundation',
  '20261015235222_owner_enrollment_acceptance_foundation'
)
ORDER BY migration_name;

-- Counts only: do not export recipients, digests or encrypted material for review.
SELECT status, count(*) FROM public.organization_owner_invitations GROUP BY status;
SELECT status, count(*) FROM public.organization_owner_invitation_deliveries GROUP BY status;
```

From the DB checkout, compare the local SHA-256 checksum to each applied migration's recorded value:

```bash
cd /Users/dvniels/Desktop/projects/gym/api/db
shasum -a 256 prisma/migrations/20261015233646_owner_invitation_delivery_foundation/migration.sql
shasum -a 256 prisma/migrations/20261015235222_owner_enrollment_acceptance_foundation/migration.sql
unset DATABASE_URL DIRECT_DATABASE_URL SHADOW_DATABASE_URL
unset TEST_DATABASE_URL TEST_MIGRATION_DATABASE_URL TEST_DATABASE_MARKER
npm run migration:status
npm run prisma:format
npm run prisma:validate
```

**Stop if history is pending, failed, checksums differ, or Prisma reports drift.** Do not run the next
command in that case: create-only can apply earlier pending migrations. Resolve ordering through a
separately reviewed plan, without reset, `db push`, editing history, or silently deploying Step 19.
Only after history is reconciled and no earlier migration can apply unexpectedly, have the human run:

```bash
npm run migration:create -- --name repair_owner_invitation_delivery_integrity
```

**Stop after generation and review its actual file.** SQL-only additions can produce an empty draft
or no draft; if no file is produced, report that result instead of inventing a timestamped directory.
The SQL below is a review proposal, not an applied or approved migration. Once the human-generated
draft exists, place this proposal into that draft and review the complete SQL before any deployment.
If existing rows violate these checks, validation must fail and roll back. Do not weaken constraints
or mutate/delete historical delivery data automatically to make deployment pass.

### Proposed forward SQL

```sql
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

ALTER TABLE public.organization_owner_invitation_deliveries
  ADD CONSTRAINT organization_owner_invitation_deliveries_lifecycle_check CHECK ((
    CASE status
      WHEN 'queued' THEN next_attempt_at IS NOT NULL AND token_digest IS NOT NULL
        AND confirmed_at IS NULL AND failed_at IS NULL AND uncertain_at IS NULL
        AND provider_message_id IS NULL AND last_error_code IS NULL
      WHEN 'processing' THEN attempt_count > 0 AND next_attempt_at IS NULL
        AND token_digest IS NOT NULL AND confirmed_at IS NULL AND failed_at IS NULL
        AND uncertain_at IS NULL AND provider_message_id IS NULL AND last_error_code IS NULL
      WHEN 'confirmed' THEN attempt_count > 0 AND next_attempt_at IS NULL
        AND confirmed_at IS NOT NULL AND failed_at IS NULL AND uncertain_at IS NULL
        AND provider_message_id IS NOT NULL AND last_error_code IS NULL
        AND token_digest IS NULL AND token_erased_at IS NOT NULL
      WHEN 'failed' THEN failed_at IS NOT NULL AND last_error_code IS NOT NULL
        AND confirmed_at IS NULL AND uncertain_at IS NULL AND provider_message_id IS NULL
        AND (
          (next_attempt_at IS NULL AND token_digest IS NULL AND token_erased_at IS NOT NULL)
          OR (next_attempt_at IS NOT NULL AND token_digest IS NOT NULL
            AND attempt_count > 0 AND attempt_count < max_attempts
            AND last_error_code IN ('PROVIDER_RATE_LIMITED', 'PROVIDER_REJECTED_RETRYABLE'))
        )
      WHEN 'uncertain' THEN attempt_count > 0 AND next_attempt_at IS NULL
        AND confirmed_at IS NULL AND failed_at IS NULL AND uncertain_at IS NOT NULL
        AND last_error_code IS NOT NULL
      ELSE false
    END
  ) IS TRUE),
  ADD CONSTRAINT organization_owner_invitation_deliveries_lease_check CHECK ((
    CASE WHEN status = 'processing' THEN
      lease_acquired_at IS NOT NULL AND lease_expires_at IS NOT NULL AND claimed_by IS NOT NULL
      AND lease_expires_at > lease_acquired_at
      AND lease_expires_at <= lease_acquired_at + interval '5 minutes'
      AND lease_expires_at <= token_expires_at
    ELSE lease_acquired_at IS NULL AND lease_expires_at IS NULL AND claimed_by IS NULL END
  ) IS TRUE),
  ADD CONSTRAINT organization_owner_invitation_deliveries_retry_check CHECK (
    max_attempts BETWEEN 1 AND 10 AND attempt_count BETWEEN 0 AND max_attempts
  ),
  ADD CONSTRAINT organization_owner_invitation_deliveries_token_material_check CHECK ((
    (num_nonnulls(token_digest, token_ciphertext, token_initialization_vector,
      token_authentication_tag, token_encryption_key_id, token_encryption_version) = 0
      AND token_erased_at IS NOT NULL)
    OR (num_nonnulls(token_digest, token_ciphertext, token_initialization_vector,
      token_authentication_tag, token_encryption_key_id, token_encryption_version) = 6
      AND token_erased_at IS NULL
      AND token_digest COLLATE "C" ~ '^[0-9a-f]{64}$'
      AND octet_length(token_ciphertext) BETWEEN 32 AND 512
      AND octet_length(token_initialization_vector) = 12
      AND octet_length(token_authentication_tag) = 16
      AND char_length(token_encryption_key_id) BETWEEN 1 AND 120
      AND token_encryption_key_id COLLATE "C" !~ '[^A-Za-z0-9._:-]'
      AND token_encryption_version = 1)
  ) IS TRUE),
  ADD CONSTRAINT organization_owner_invitation_deliveries_timestamp_order_check CHECK ((
    updated_at >= created_at AND token_expires_at > created_at
    AND token_expires_at <= created_at + interval '7 days'
    AND (next_attempt_at IS NULL OR (next_attempt_at >= created_at
      AND next_attempt_at < token_expires_at
      AND (failed_at IS NULL OR next_attempt_at > failed_at)))
    AND (lease_acquired_at IS NULL OR lease_acquired_at >= created_at)
    AND (confirmed_at IS NULL OR (confirmed_at >= created_at AND confirmed_at < token_expires_at))
    AND (failed_at IS NULL OR failed_at >= created_at)
    AND (uncertain_at IS NULL OR uncertain_at >= created_at)
    AND (token_erased_at IS NULL OR token_erased_at >= created_at)
  ) IS TRUE),
  ADD CONSTRAINT organization_owner_invitation_deliveries_bounded_text_check CHECK (
    char_length(provider_idempotency_key) BETWEEN 1 AND 128
    AND provider_idempotency_key COLLATE "C" !~ '[^A-Za-z0-9._:/-]'
    AND (provider_message_id IS NULL OR (char_length(provider_message_id) BETWEEN 1 AND 128
      AND provider_message_id COLLATE "C" !~ '[^A-Za-z0-9._:-]'))
    AND (claimed_by IS NULL OR (char_length(claimed_by) BETWEEN 1 AND 120
      AND claimed_by COLLATE "C" !~ '[^A-Za-z0-9._:-]'))
    AND (last_error_code IS NULL OR (char_length(last_error_code) BETWEEN 1 AND 63
      AND last_error_code COLLATE "C" ~ '^[A-Z][A-Z0-9_]*$'))
  );

CREATE FUNCTION public.guard_owner_invitation_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  invitation record;
  organization_status public.organization_status;
  checked_at timestamptz := clock_timestamp();
  erasing boolean;
BEGIN
  -- Applications lock Organization, invitation, delivery in that order before conditional writes.
  -- These locks also serialize direct writers against revocation and Organization suspension.
  SELECT status INTO organization_status FROM public.organizations
    WHERE id = NEW.organization_id FOR SHARE;
  IF NOT FOUND THEN
    IF TG_OP = 'INSERT' THEN RETURN NEW; END IF; -- The foreign key rejects missing insert parents.
    RAISE EXCEPTION 'immutable delivery parent'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
  END IF;
  SELECT status, token_digest, expires_at, sent_at INTO invitation
    FROM public.organization_owner_invitations
    WHERE organization_id = NEW.organization_id AND id = NEW.owner_invitation_id FOR UPDATE;
  IF NOT FOUND THEN
    IF TG_OP = 'INSERT' THEN RETURN NEW; END IF;
    RAISE EXCEPTION 'immutable delivery parent'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
  END IF;
  checked_at := clock_timestamp(); -- Recheck after locks, not before a potentially blocked read.

  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'queued' OR NEW.attempt_count <> 0
      OR invitation.status <> 'pending_delivery' OR organization_status NOT IN ('pending', 'active')
      OR NEW.token_expires_at <= checked_at
    THEN
      RAISE EXCEPTION 'invalid delivery reservation'
        USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
    END IF;
    RETURN NEW;
  END IF;

  erasing := NEW.token_digest IS NULL AND NEW.token_ciphertext IS NULL
    AND NEW.token_initialization_vector IS NULL AND NEW.token_authentication_tag IS NULL
    AND NEW.token_encryption_key_id IS NULL AND NEW.token_encryption_version IS NULL
    AND NEW.token_erased_at IS NOT NULL
    AND (NEW.status IN ('confirmed', 'uncertain')
      OR (NEW.status = 'failed' AND NEW.next_attempt_at IS NULL));

  IF NEW.id IS DISTINCT FROM OLD.id
    OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
    OR NEW.owner_invitation_id IS DISTINCT FROM OLD.owner_invitation_id
    OR NEW.requested_by_platform_staff_id IS DISTINCT FROM OLD.requested_by_platform_staff_id
    OR NEW.provider_idempotency_key IS DISTINCT FROM OLD.provider_idempotency_key
    OR NEW.token_expires_at IS DISTINCT FROM OLD.token_expires_at
    OR NEW.max_attempts IS DISTINCT FROM OLD.max_attempts
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
    OR NEW.attempt_count < OLD.attempt_count
    OR (OLD.provider_message_id IS NOT NULL
      AND NEW.provider_message_id IS DISTINCT FROM OLD.provider_message_id)
    OR (OLD.token_erased_at IS NOT NULL AND NEW.token_erased_at IS DISTINCT FROM OLD.token_erased_at)
    OR ((NEW.token_digest IS DISTINCT FROM OLD.token_digest
      OR NEW.token_ciphertext IS DISTINCT FROM OLD.token_ciphertext
      OR NEW.token_initialization_vector IS DISTINCT FROM OLD.token_initialization_vector
      OR NEW.token_authentication_tag IS DISTINCT FROM OLD.token_authentication_tag
      OR NEW.token_encryption_key_id IS DISTINCT FROM OLD.token_encryption_key_id
      OR NEW.token_encryption_version IS DISTINCT FROM OLD.token_encryption_version) AND NOT erasing)
    OR OLD.status = 'confirmed'
    OR (OLD.status = 'failed' AND OLD.next_attempt_at IS NULL)
  THEN
    RAISE EXCEPTION 'immutable delivery reservation'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
  END IF;

  IF OLD.status = 'uncertain' AND NEW.status = 'uncertain' AND (
    OLD.token_digest IS NULL OR NEW.uncertain_at IS DISTINCT FROM OLD.uncertain_at
    OR NEW.last_error_code IS DISTINCT FROM OLD.last_error_code
    OR NEW.provider_message_id IS DISTINCT FROM OLD.provider_message_id
  ) THEN
    RAISE EXCEPTION 'uncertain cleanup must preserve outcome metadata'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
  END IF;

  IF NEW.status = 'processing' THEN
    IF OLD.status NOT IN ('queued', 'failed') OR OLD.next_attempt_at IS NULL
      OR OLD.next_attempt_at > checked_at OR OLD.attempt_count >= OLD.max_attempts
      OR OLD.token_digest IS NULL OR NEW.token_expires_at <= checked_at
      OR invitation.status <> 'pending_delivery' OR organization_status NOT IN ('pending', 'active')
      OR NEW.attempt_count <> OLD.attempt_count + 1
      OR NEW.lease_expires_at <= checked_at
      OR NEW.lease_acquired_at > checked_at + interval '1 second'
    THEN
      RAISE EXCEPTION 'delivery cannot be claimed'
        USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
    END IF;
  ELSE
    IF NEW.attempt_count <> OLD.attempt_count OR NOT (
      (OLD.status = 'queued' AND NEW.status = 'failed' AND NEW.next_attempt_at IS NULL)
      OR (OLD.status = 'processing' AND NEW.status IN ('confirmed', 'failed', 'uncertain'))
      OR (OLD.status = 'failed' AND NEW.status = 'failed' AND NEW.next_attempt_at IS NULL)
      OR (OLD.status = 'uncertain' AND NEW.status IN ('confirmed', 'failed'))
      OR (OLD.status = 'uncertain' AND NEW.status = 'uncertain' AND erasing)
    ) THEN
      RAISE EXCEPTION 'invalid delivery transition'
        USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
    END IF;
    IF OLD.status = 'processing' AND NEW.status <> 'uncertain'
      AND OLD.lease_expires_at <= checked_at
    THEN
      RAISE EXCEPTION 'expired delivery lease requires reconciliation'
        USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
    END IF;
  END IF;

  IF NEW.next_attempt_at IS NOT NULL AND NEW.status = 'failed'
    AND (invitation.status <> 'pending_delivery'
      OR organization_status NOT IN ('pending', 'active') OR NEW.token_expires_at <= checked_at)
  THEN
    RAISE EXCEPTION 'ineligible delivery cannot retry'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
  END IF;
  IF NEW.status = 'confirmed' AND (
    OLD.token_digest IS NULL OR invitation.status <> 'sent'
    OR organization_status NOT IN ('pending', 'active') OR NEW.token_expires_at <= checked_at
    OR invitation.token_digest IS DISTINCT FROM OLD.token_digest
    OR invitation.expires_at IS DISTINCT FROM OLD.token_expires_at
    OR invitation.sent_at IS DISTINCT FROM NEW.confirmed_at
  ) THEN
    RAISE EXCEPTION 'delivery confirmation requires matching sent invitation'
      USING ERRCODE = '23514', CONSTRAINT = 'owner_invitation_delivery_guard';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER owner_invitation_delivery_guard
BEFORE INSERT OR UPDATE ON public.organization_owner_invitation_deliveries
FOR EACH ROW EXECUTE FUNCTION public.guard_owner_invitation_delivery();

-- Preserve the original identity check and add terminal invitation protection.
CREATE OR REPLACE FUNCTION public.guard_organization_owner_invitation_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
    OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
    OR NEW.invited_email IS DISTINCT FROM OLD.invited_email
    OR NEW.invited_by_platform_staff_id IS DISTINCT FROM OLD.invited_by_platform_staff_id
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
    OR (OLD.status IN ('revoked', 'accepted') AND NEW IS DISTINCT FROM OLD)
    OR (OLD.status = 'sent' AND NEW.status = 'pending_delivery')
    OR (OLD.status = 'pending_delivery' AND NEW.status = 'accepted')
    OR (OLD.status = 'sent' AND NEW.status = 'sent' AND (
      NEW.token_digest IS DISTINCT FROM OLD.token_digest
      OR NEW.expires_at IS DISTINCT FROM OLD.expires_at OR NEW.sent_at IS DISTINCT FROM OLD.sent_at))
  THEN
    RAISE EXCEPTION 'invalid invitation identity or lifecycle change'
      USING ERRCODE = '23514', CONSTRAINT = 'organization_owner_invitation_identity_guard';
  END IF;
  RETURN NEW;
END;
$function$;

ALTER TABLE public.organization_ownership_audit_events
  DROP CONSTRAINT organization_ownership_audit_events_metadata_check,
  ADD CONSTRAINT organization_ownership_audit_events_metadata_check CHECK ((
    CASE action
      WHEN 'invitation_created' THEN previous_invitation_status IS NULL
        AND resulting_invitation_status = 'pending_delivery'
      WHEN 'invitation_revoked' THEN previous_invitation_status IN ('pending_delivery', 'sent')
        AND resulting_invitation_status = 'revoked'
      WHEN 'invitation_delivery_queued' THEN previous_invitation_status = 'pending_delivery'
        AND resulting_invitation_status = 'pending_delivery'
      ELSE false
    END
  ) IS TRUE);

REVOKE ALL ON TABLE public.organization_owner_invitation_deliveries FROM PUBLIC;
REVOKE ALL ON TYPE public.organization_owner_invitation_delivery_status FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_owner_invitation_delivery(),
  public.guard_organization_owner_invitation_identity() FROM PUBLIC;
COMMIT;
```

### Conditional updates, leases and reconciliation

Only a new `QUEUED` reservation with zero attempts may be inserted. Each claim increments attempts by
exactly one, clears prior known-failure metadata, and sets one lease (at most five minutes, ending no
later than token expiry). Applications obtain time from PostgreSQL, use short transactions, lock
Organization then invitation then delivery, and condition updates on status, attempt count and lease
owner. A cross-tenant parent mismatch remains a composite-foreign-key failure. SQL guard errors contain
no token or recipient. The trigger does not verify a caller's HTTP permission; the API must do so.

Do not call the provider inside a transaction. Recheck eligibility immediately before submission and
again before finalization. Finalization updates the pending invitation to SENT with the reservation's
digest/expiry, then confirms the still-owned live delivery lease and erases its recoverable material
in the same transaction. Roll back if either conditional update affects zero rows. Revocation keeps
its existing audit transaction; the forward invitation guard prevents revoked/accepted rows being
resurrected even by an independent SQL writer. A confirmed email cannot be unsent, but its token
becomes invalid when the invitation is revoked.

**Expired PROCESSING leases become UNCERTAIN, never QUEUED.** The worker may have submitted the email
before disappearing. No automatic retry of UNCERTAIN is permitted. Only known provider rejections
classified `PROVIDER_RATE_LIMITED` or `PROVIDER_REJECTED_RETRYABLE` may schedule a bounded retry,
retaining the same token and idempotency key. A timeout, lost response, malformed success response or
failed database finalization after provider acceptance is uncertain. Shutdown stops new claims and
settles in-flight work or leaves its lease for uncertain recovery; it must not reset leases to queued.

Manual reconciliation verifies the exact provider key/message, recipient and payload using protected
operator access, then rechecks the same unexpired reservation and invitation before finalization.
It cannot create a new token, enqueue again or reactivate a revoked invitation. A failed/expired
reservation may be terminally closed with erased secrets. UNCERTAIN may erase its envelope without
asserting provider success; retain its non-secret uncertainty record. Unknown provider outcomes remain
uncertain even after erasure. Retire old keys only after active envelopes and approved backup retention
have been reviewed. No exactly-once delivery guarantee is claimed.

### Effective privileges and deployment review

Portable migration SQL grants nothing to environment-specific roles. The normal API role needs only
SELECT/INSERT on delivery reservations for Phase B queueing; its ownership-audit access remains
SELECT/INSERT only. Prefer a separately provisioned platform worker role with SELECT on invitations,
organizations and delivery rows, plus column UPDATE for invitation `status`, `token_digest`, `sent_at`,
`expires_at`, `updated_at`, and delivery `status`, `attempt_count`, `next_attempt_at`, lease fields,
`claimed_by`, `provider_message_id`, `last_error_code`, token envelope/digest fields, outcome fields,
`token_erased_at`, `updated_at`. Do not grant modification of immutable reservation IDs/actor/key/expiry.
Row locking also requires PostgreSQL UPDATE privilege on at least one column of each locked relation;
review a minimal harmless `organizations.updated_at` column grant for that worker, not broad UPDATE.
Trigger functions use SECURITY INVOKER; callers need parent SELECT/locking privileges. Tenant roles
must not inherit any worker or platform role and receive no delivery-record grants.

Separately verify effective privileges, column ACLs, inherited memberships, table ownership,
default privileges and BYPASSRLS. A direct REVOKE cannot remove privileges inherited from another
role or PUBLIC. Do not assume role names mean restrictions are effective. Select the intended
database before reviewing role grants. These diagnostics expose no secrets:

```sql
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolbypassrls, rolinherit
FROM pg_catalog.pg_roles WHERE rolname IN ('gym_app', 'gym_migrator', 'gym_test');
SELECT member.rolname AS member, parent.rolname AS inherited_role
FROM pg_catalog.pg_auth_members membership
JOIN pg_catalog.pg_roles member ON member.oid = membership.member
JOIN pg_catalog.pg_roles parent ON parent.oid = membership.roleid
WHERE member.rolname IN ('gym_app', 'gym_migrator', 'gym_test');
SELECT c.relname, pg_get_userbyid(c.relowner) AS owner
FROM pg_catalog.pg_class c
WHERE c.oid IN ('public.organization_owner_invitation_deliveries'::regclass,
  'public.organization_ownership_audit_events'::regclass);
SELECT conname, convalidated FROM pg_catalog.pg_constraint
WHERE conrelid = 'public.organization_owner_invitation_deliveries'::regclass AND contype = 'c';
SELECT tgname, tgenabled FROM pg_catalog.pg_trigger
WHERE tgrelid = 'public.organization_owner_invitation_deliveries'::regclass AND NOT tgisinternal;
SELECT has_table_privilege('gym_app',
  'public.organization_owner_invitation_deliveries', 'DELETE,TRUNCATE,TRIGGER') AS unsafe_delivery,
  has_table_privilege('gym_app',
  'public.organization_ownership_audit_events', 'UPDATE,DELETE,TRUNCATE,TRIGGER') AS unsafe_audit,
  has_schema_privilege('gym_app', 'public', 'CREATE') AS unsafe_ddl;
-- All three must be false; inspect column ACLs and inherited memberships separately as well.
```

The existing `gym_test`-only grants above permit reserved-fixture cleanup; they are never runtime
grants. Existing rows must pass all six checks before the repair commits. A deployment acquires table
locks while validating constraints; schedule a reviewed window, stop sending workers, preserve backups
and use forward correction for any later issue. Never roll back by dropping integrity protections or
restoring a database over unrelated application data.

After the generated draft and grants are reviewed, target a marked disposable database and have the
human apply the reviewed migration, verify the constraints/triggers and test-only grants, then run:

```bash
cd /Users/dvniels/Desktop/projects/gym/api/db
npm run migration:test:deploy
npm run prisma:generate
npm run format:check
npm run lint
npm run typecheck
npm run test:unit
npm run test:integration
npm run build
```

For delivery-only verification after this repair is reviewed and deployed to the marked disposable
database, use `npm run test:integration -- --testPathPattern=organization-owner-invitation-delivery.integration`.
The complete integration command above also exercises Step 19 enrollment prerequisites, which still
need independent SQL hardening/review. A delivery-only pass is not a claim that those other suites or
the recipient identity flow are ready. Do not relax their prerequisite checks to hide that blocker.

Do not deploy to gym_dev/production or begin dependent API activation from this proposal alone. Step 21
Phase B follows the migration review, disposable verification and compatible package checkpoint. Its
remaining scope is the purpose-separated token/envelope services, disabled-by-default validated
configuration, send-invitation permission, protected 202 queue route, explicit worker entrypoint,
dedicated Resend adapter, minimal no-store public preview and API/HTTP tests. No owner account,
membership, OWNER assignment, tenant session, frontend or Step 22 work is included. Even after those
sources exist, a fixed acceptance origin is not evidence of an implemented/reviewed acceptance page;
delivery stays disabled until the actual destination and token handoff are independently approved.

No migration, database connection, generation, formatter, lint, typecheck, tests, build, provider call,
worker, server, deployment, package publication or Git write was executed by the agent. Existing SQL
and the Prisma schema are preserved; only this review proposal and focused integration expectations
are authored before the human-generated migration checkpoint.

## Engineering rules

All contributors and agents must read `AGENTS.md` and `.agents/README.md`. These rules prohibit agents
from executing installation, generation, validation, database, Git, or release commands.
