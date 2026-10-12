# ADR 0003: Transaction-Scoped Tenant Context

- Status: Accepted
- Date: 2026-10-12

## Context

Connection pooling makes session-level tenant settings unsafe: a setting can leak to another request.
Prisma alone does not enforce tenant isolation, while future PostgreSQL RLS needs trusted context.

## Decision

Provide `TenantTransactionService` to validate UUID context and call PostgreSQL `set_config` with local
scope inside the same transaction as tenant queries. Organization context is mandatory; absent branch
context becomes an empty setting that future policies must treat as no branch. Policies fail closed.

## Consequences

RLS-aware work must remain inside the supplied callback. The API still authenticates/authorizes and
queries still include tenant scope. Integration tests must use production-like non-owner privileges.
