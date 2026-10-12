# Folder Structure

## Purpose and scope

Make schema ownership, runtime code, tests, and operations easy to locate.

## Mandatory engineering requirements

Use `prisma/` for schema and migrations, `src/database/` for Nest lifecycle and transaction services,
`src/config/` for validation, `src/types/` for database contracts, `src/generated/` only for generated
Prisma output, and `test/unit/` and `test/integration/` for tests. Keep essential package guidance in
the root `README.md` and agent-only rules in `.agents/`; never create a repository-local `docs/`
directory. Public exports belong only in `src/index.ts`.

## Forbidden patterns

No controllers, generic catch-all utilities, hand-edited generated files, duplicate schemas, empty
folders, or deep nesting without a clear boundary.

## Correct example

A tenant transaction primitive lives in `src/database/tenant-transaction.service.ts`; its contract is
exported from `src/index.ts` and tested under `test/unit/`.

## Common mistakes

Putting runtime code in `prisma/`, importing private paths from the API, or creating a `common/`
directory filled with unrelated helpers.

## Review checklist

- Each file has one clear responsibility and a justified location.
- Generated and authored sources are visibly separated.
