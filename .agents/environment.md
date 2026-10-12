# Environment

## Purpose and scope

Keep local, test, staging, and production configuration explicit and isolated.

## Mandatory engineering requirements

Runtime requires `DATABASE_URL`; migration commands may use `DIRECT_DATABASE_URL`, and development may
use `SHADOW_DATABASE_URL`. Tests require a disposable `TEST_DATABASE_URL`. Validate at startup, use
`.env.example` only for fake examples, and keep production values in managed secrets. Use UTC database
time and `Africa/Kigali` only for business presentation/scheduling.

## Forbidden patterns

No defaults that connect to shared or production databases, checked-in `.env`, environment guessing,
or reusing a production database as a shadow/test database.

## Correct example

Local Soho Gym examples use fake credentials and an isolated `nexcode_gym_test` database.

## Common mistakes

Using a pooled URL for DDL, relying on Node to auto-load `.env`, or silently falling back after a
missing variable.

## Review checklist

- Each variable’s consumer and environment are documented.
- Missing or invalid required settings fail before traffic is accepted.
