# Prisma

## Purpose and scope

Govern the canonical schema, generated client, and safe query conventions.

## Mandatory engineering requirements

Use Prisma 7’s `prisma-client` generator with explicit output in `src/generated/prisma`, ESM, the
PostgreSQL connector, `prisma.config.ts`, and `@prisma/adapter-pg`. Commit schema and migrations; do not
commit generated client output. Use parameterized tagged queries for unavoidable SQL and transactions
for multi-record invariants.

## Forbidden patterns

No `$queryRawUnsafe`, `$executeRawUnsafe`, hand-edited generated files, schema copies in consumers,
implicit cascading, or runtime migration execution.

## Correct example

`transaction.$executeRaw\`SELECT set_config('app.current_organization_id', ${id}, true)\`` keeps the
value parameterized and transaction-local.

## Common mistakes

Using Prisma 6 datasource URL syntax with Prisma 7, constructing `PrismaClient` without a driver
adapter, or forgetting to regenerate after schema changes.

## Review checklist

- Generator, adapter, and package versions remain mutually compatible.
- Queries are tenant-scoped, parameterized, bounded, and transactional where needed.
