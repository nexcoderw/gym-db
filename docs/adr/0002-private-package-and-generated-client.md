# ADR 0002: Private ESM Package with Compiled Generated Client

- Status: Accepted
- Date: 2026-10-12

## Context

Prisma 7 requires an explicit client output and PostgreSQL driver adapter. Consumers must not depend on
this repository’s source tree or generate from duplicated schemas.

## Decision

Use Prisma 7 `prisma-client` with ESM output under ignored `src/generated/prisma`. Human release steps
generate the client, compile it with authored TypeScript into `dist`, and publish the result privately
to GitHub Packages as `@nexcoderw/gym-db`. The adapter and PostgreSQL driver are runtime dependencies;
Nest is a peer dependency.

## Consequences

Generation is mandatory before build and publication, while consumers install ready-to-run JavaScript
and declarations. Releases are larger than a schema-only package but are reproducible, isolated from
consumer source layout, and versioned with the schema contract.
