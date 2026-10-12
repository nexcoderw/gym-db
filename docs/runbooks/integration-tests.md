# Secure integration-test database runbook

## Purpose

Prepare and operate a disposable PostgreSQL target for `@nexcoderw/gym-db` integration tests without
risking shared development, staging, or production data. Run every command from `api/db` unless the
step explicitly uses the database provider's administrative console.

Different connection strings do not prove database isolation. Pooler and direct URLs, DNS aliases,
different users, and different query parameters can still reach the same PostgreSQL database. The
suite therefore combines conservative URL checks with verification of the connected database, its
role privileges, and a unique human-provisioned marker.

## Provision the disposable target

1. Create a dedicated disposable database or provider branch that contains no production-derived
   data. Do not clone a marked test target without assigning the clone a new marker.
2. Generate a unique UUID for this database and store it as `TEST_DATABASE_MARKER` in the ignored
   `.env.local` file.
3. As the test database owner, set the database comment in the provider SQL console. Replace the
   database identifier and UUID deliberately:

   ```sql
   COMMENT ON DATABASE nexcode_gym_test IS
     'nexcode-gym:disposable-integration-test:00000000-0000-4000-8000-000000000000';
   ```

   The test suite never creates or repairs this marker. A missing or mismatched marker stops the suite
   before any test write or cleanup.
4. Create a dedicated login role such as `gym_test` using a provider-managed password. It must have
   `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`, `NOREPLICATION`, and `NOBYPASSRLS`. Revoke database and
   schema creation privileges. Grant only connection, schema usage, and the DML needed by tests:

   ```sql
   REVOKE CREATE ON DATABASE nexcode_gym_test FROM gym_test;
   REVOKE CREATE ON SCHEMA public FROM gym_test;
   GRANT CONNECT ON DATABASE nexcode_gym_test TO gym_test;
   GRANT USAGE ON SCHEMA public TO gym_test;
   GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO gym_test;
   ALTER DEFAULT PRIVILEGES FOR ROLE gym_migrator IN SCHEMA public
     GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO gym_test;
   ```

   Replace both role names with the provisioned test and migration roles. Never grant ownership or
   migration privileges to the test role.
5. Set `TEST_DATABASE_URL` to the restricted role connection. Keep the separate owner/migration
   connection in `TEST_MIGRATION_DATABASE_URL`; integration tests do not read that variable.

## Apply reviewed migrations

Load the ignored local environment, then explicitly direct Prisma to the disposable test target's
migration credential:

```bash
set -a
source .env.local
set +a

DATABASE_URL="$TEST_MIGRATION_DATABASE_URL" \
DIRECT_DATABASE_URL="$TEST_MIGRATION_DATABASE_URL" \
npm run migration:deploy
```

Only reviewed committed migrations may be deployed. Do not use `prisma db push`, and do not use the
restricted test runner credential for DDL.

## Verify and run

```bash
npm run prisma:generate
npm run format:check
npm run lint
npm run typecheck
npm run test:unit
npm run test:integration
npm run build
```

The integration guard checks all of the following before any suite writes:

- `TEST_DATABASE_URL` and `TEST_DATABASE_MARKER` are present and valid.
- The test target does not match configured runtime, migration, or shadow targets after common pooler
  hostname normalization.
- Obvious production labels and PostgreSQL administrative databases are rejected.
- The test username differs from configured runtime, migration, and shadow users.
- `current_database()` and `current_user` match the URL.
- The database comment contains the exact unique marker.
- The connected role cannot create databases, roles, schemas, or objects in `public`, replicate,
  bypass row-level security, or act as a superuser.

Fixture teardown deletes only UUIDs reserved by the current test. It is foreign-key ordered,
repeatable, and safe when fixture setup stops partway through. It never assumes ownership of every row
in a table.

## Failure and recovery

- Treat any guard failure as a provisioning error. Do not weaken or bypass the check.
- If the marker is missing, confirm the target is disposable before setting it through an
  administrator-controlled console.
- If privilege verification fails, revoke the reported administrative capability or create a new
  restricted role. Do not grant more privileges to make a test pass.
- If a test process is interrupted, rerun the suite. Run-scoped values prevent stale fixtures from
  colliding, and subsequent scoped cleanup removes only fixtures known to that run.
- Retire a test database by revoking its test credentials first, then deleting the disposable target
  through the provider's reviewed administrative workflow.

URL and naming checks remain heuristics: proxies, aliases, branch cloning, or a copied marker can make
different configurations appear safe. The unique marker, restricted role, provider-level isolation,
and prohibition on production-derived data must all be maintained together.
