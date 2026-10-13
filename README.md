# @nexcoderw/gym-db

Private database foundation for NEXCODE Gym Management SaaS. This repository is the only source of
truth for PostgreSQL schema, migrations, generated Prisma Client, and reusable NestJS database access.
It is a package consumed by `gym-api`; it is not a public server and contains no controllers.

## Architecture

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

| Local file              | Consumer                                                | Contents                                                                                                 |
| ----------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `.env.local`            | Application runtime; integration-test target comparison | Runtime `DATABASE_URL` only                                                                              |
| `.env.migrations.local` | Prisma CLI                                              | `DIRECT_DATABASE_URL`, CLI fallback `DATABASE_URL`, `SHADOW_DATABASE_URL`, `TEST_MIGRATION_DATABASE_URL` |
| `.env.test.local`       | `npm run test:integration`                              | Restricted `TEST_DATABASE_URL`, marker, password-free migration/shadow reference URLs                    |

Matching `.example` files are tracked; real files must stay ignored and mode `600`. Do not source
these files in a shell: Node/dotenv parse URL query strings and password characters as data.
Never load `.env.migrations.local` into Jest or an application. Reference-only URLs in `.env.test.local`
retain the real migration/shadow host, port, database and username, but contain no password. Update
those references if you change a migration target; they preserve the existing isolation comparisons.

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

## Engineering rules

All contributors and agents must read `AGENTS.md` and `.agents/README.md`. These rules prohibit agents
from executing installation, generation, validation, database, Git, or release commands.
