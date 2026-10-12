# Tenant Isolation Strategy

## Invariants

NEXCODE Platform contains Gym Organizations, which contain Gym Branches. Organization identity is
mandatory on every tenant-owned business row. Branch ownership never substitutes for organization
scope. Foreign keys and compound constraints should prevent associating a branch-owned row with a
branch from another organization.

## Application and database enforcement

`gym-api` establishes authorized context from trusted authentication, not request-supplied IDs.
Queries include organization scope even when another identifier appears globally unique.
`TenantTransactionService` provides transaction-local `app.current_organization_id` and
`app.current_branch_id` settings, safe under pooling because they end with the transaction.

When RLS is introduced, policies must read context with `current_setting(name, true)`, treat missing,
empty, or invalid context as denial, cover all commands, and be tested with the non-owner runtime role.
Owners commonly bypass RLS, so `FORCE ROW LEVEL SECURITY` and privileged bypass behavior require review.
RLS complements, not replaces, query scoping and API authorization.

## Transactions and privileged work

All related tenant writes and tenant context occur in one transaction. Never perform network calls in
that transaction. Platform support/reporting across organizations needs a separately named API,
least-privilege role, explicit authorization, audit event, bounded query, and a dedicated ADR—never an
optional organization argument.

## Verification

For each tenant model, integration tests create fictional tenant A and tenant B, then prove reads,
writes, nested relations, unique conflicts, and raw queries cannot cross the boundary. Run tests using
the same privilege shape as production.
