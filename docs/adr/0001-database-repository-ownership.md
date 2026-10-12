# ADR 0001: Exclusive Database Repository Ownership

- Status: Accepted
- Date: 2026-10-12

## Context

Multiple services changing a shared schema would create migration ordering, compatibility, and audit
risk. The API still needs typed, lifecycle-managed access without owning schema files.

## Decision

`gym-db` exclusively owns Prisma schema, migrations, generated client configuration, database
integrity primitives, and related runbooks. `gym-api` consumes an immutable package version and owns
HTTP and business behavior. No consumer carries a schema copy or runs schema synchronization.

## Consequences

Database changes require a coordinated package release and deployment order. This adds review steps
but provides one auditable migration chain, explicit compatibility, and reusable types.
