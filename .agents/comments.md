# Comments and TSDoc

## Purpose and scope

Preserve non-obvious architectural, security, lifecycle, and integrity intent.

## Mandatory engineering requirements

Use TSDoc on public services, functions, and contracts where behavior is not self-evident. Explain why
a constraint, tenant boundary, transaction, or rollback limitation exists. Keep comments close to the
decision and update them with code.

## Forbidden patterns

No comments that restate syntax, disabled code blocks, TODOs without an owner/issue, credentials, or
misleading claims that a test or migration has run.

## Correct example

Document that transaction-local PostgreSQL settings prevent tenant context leaking through a pool.

## Common mistakes

Describing what a loop does instead of the invariant it protects, or leaving migration risk only in a
pull-request discussion.

## Review checklist

- Public contracts and non-obvious safety choices are documented.
- Comments remain accurate and reveal no sensitive values.
