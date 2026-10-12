# Code Quality

## Purpose and scope

Keep the package small, cohesive, auditable, and safe to evolve.

## Mandatory engineering requirements

Prefer explicit dependencies, narrow public APIs, immutable inputs, single-purpose files, fail-fast
validation, and simple control flow. Remove dead code. Preserve backwards compatibility unless a
reviewed major release explicitly permits a break.

## Forbidden patterns

No speculative abstractions, hidden global state, circular imports, magic values, swallowed errors,
or business workflows disguised as database helpers.

## Correct example

A configuration parser validates required values once and returns a frozen typed object.

## Common mistakes

Adding a repository wrapper for every Prisma model without a concrete invariant, or exposing internal
tokens and adapters as public API.

## Review checklist

- Code has a clear reason to exist and tests cover its contract.
- The change does not enlarge the public API unnecessarily.
