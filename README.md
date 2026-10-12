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
- `src/index.ts` is the sole supported public entry point.

See [package architecture](docs/architecture/package-architecture.md),
[database conventions](docs/database/schema-conventions.md),
[platform administrator identity](docs/database/platform-admin-identity.md), and the
[ADRs](docs/adr/).

## Responsibilities

This package owns models, relations, constraints, indexes, enums, migrations, client generation,
connection lifecycle, database configuration, tenant primitives, integrity tests, and migration
runbooks. `gym-api` owns transport, authentication, authorization decisions, business workflows,
email, billing orchestration, and user-facing DTOs. The API must not carry a schema or migrations.

## Prerequisites

- Node.js `^20.19.0`, `^22.12.0`, or `>=24.0.0`
- npm 10 or later
- PostgreSQL supported by the selected Prisma 7 release
- Separate disposable databases for development shadowing and integration tests
- GitHub Packages read/write tokens as appropriate

## Environment

Copy `.env.local.example` to `.env.local` and replace only with non-production credentials.

| Variable                         | Required by                | Description                                   |
| -------------------------------- | -------------------------- | --------------------------------------------- |
| `DATABASE_URL`                   | runtime and CLI fallback   | Runtime PostgreSQL application-role URL       |
| `DIRECT_DATABASE_URL`            | migration CLI when pooled  | Direct migration-role URL; preferred for DDL  |
| `SHADOW_DATABASE_URL`            | local migration generation | Disposable development shadow database        |
| `DATABASE_POOL_MAX`              | runtime, optional          | Positive per-process pool limit; default `10` |
| `DATABASE_CONNECTION_TIMEOUT_MS` | runtime, optional          | Positive connection timeout; default `10000`  |
| `TEST_DATABASE_URL`              | integration tests          | Disposable, migrated PostgreSQL test database |

Production secrets belong in the deployment secret manager. Never commit `.env` files or embed tokens
in `.npmrc`. PostgreSQL timestamps are UTC; user-facing business times use `Africa/Kigali`.

## Local development workflow

All commands in this repository are human-operated. From `api/db`:

```bash
npm install
npm run prisma:generate
npm run prisma:format
npm run prisma:validate
npm run format
npm run lint
npm run typecheck
npm run test:unit
TEST_DATABASE_URL='postgresql://...' npm run test:integration
npm run build
npm pack --dry-run
```

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

Never use `prisma db push` in production or edit a migration already applied. Full procedures are in
[migration runbook](docs/runbooks/migrations.md) and [recovery runbook](docs/runbooks/recovery.md).

## Versioning and publication

Use SemVer for the package. A backwards-compatible API/schema addition is normally minor; fixes are
patches; removal or incompatible client API requires a major version. Database rollout compatibility
can require expand-and-contract even when the package API change is minor. Published versions are
immutable.

GitHub Packages publication requires an npm token with `write:packages` (and repository access when
private). Consumers need `read:packages`. Use `npm login --scope=@nexcoderw --auth-type=legacy
--registry=https://npm.pkg.github.com`, never a committed token. See
[release runbook](docs/runbooks/releases.md).

## Testing and security

Unit tests cover configuration, module exports, tenant validation, parameterized context setup, and
fail-before-callback behavior. Integration tests require a disposable `TEST_DATABASE_URL` and verify
transaction-local context, success and rollback cleanup, sequential tenant replacement, and concurrent
tenant separation. They also verify platform identity uniqueness, restrictive relationships, explicit
RBAC assignments, suspension states, and rollback. The suite fails with an explicit configuration
error when `TEST_DATABASE_URL` is missing or matches `DATABASE_URL`; it never silently skips database
verification. Future tenant models must add cross-tenant denial tests under RLS.

Use distinct least-privilege runtime and migration roles, TLS outside trusted local development,
parameterized SQL, and synthetic examples (for example fictional Soho Gym branches in Kimihurura and
Remera). See [tenant isolation](docs/database/tenant-isolation.md).

## Troubleshooting

- **Generated client import missing:** run `npm run prisma:generate` after installing dependencies.
- **CLI uses a pooler:** set `DIRECT_DATABASE_URL` to a direct migration connection.
- **Shadow database matches the migration database:** provision a dedicated disposable shadow database
  and update `SHADOW_DATABASE_URL`. Prisma Migrate may reset it, so never reuse runtime or test data.
- **Migration deploy reports no migrations:** run the reviewed create-only workflow first; do not deploy
  until the generated SQL has been inspected and approved.
- **Integration suite requires configuration:** provide a disposable `TEST_DATABASE_URL` distinct from
  `DATABASE_URL` and apply migrations first. Missing or reused configuration fails the suite.
- **Process does not disconnect:** verify the API enabled Nest shutdown hooks.
- **GitHub Packages returns 401/403:** confirm scope registry, token scopes, SSO/repository access, and
  that the token is supplied through the user npm configuration rather than this repository.
- **Migration drift:** stop deployment; follow the migration and recovery runbooks. Do not use `db push`.

## Engineering rules

All contributors and agents must read `AGENTS.md` and `.agents/README.md`. These rules prohibit agents
from executing installation, generation, validation, database, Git, or release commands.
