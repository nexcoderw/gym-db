# Testing

## Purpose and scope

Verify configuration, lifecycle, constraints, migrations, transactions, exports, and isolation.

## Mandatory engineering requirements

Keep fast unit tests separate from integration tests. Integration tests use a disposable PostgreSQL
database through `TEST_DATABASE_URL`, run migrations first, isolate state, and close connections.
Test both success and failure paths, tenant A versus tenant B, uniqueness/foreign keys, rollback, and
package exports. Never claim a check ran without captured human-provided results.

## Forbidden patterns

No production/shared databases, real personal data, order-dependent tests, mocked constraint tests,
blanket snapshots, or silent integration success when the database was not configured.

## Correct example

Insert fictional Soho Gym tenants in an isolated database and prove Kimihurura context cannot access
Remera records belonging to another organization.

## Common mistakes

Testing only Prisma validation instead of PostgreSQL enforcement, or leaving committed rows behind.

## Review checklist

- Unit and integration scope is appropriate; fixtures are fictional and deterministic.
- Isolation, cleanup, failures, and connection lifecycle are covered.
