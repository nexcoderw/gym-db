# Migration Runbook

## Prepare and review

From `api/db`, update `prisma/schema.prisma`, then have the human run:

```bash
npm run prisma:format
npm run prisma:validate
npm run migration:create -- --name descriptive_change_name
```

Do not apply the generated migration yet. Review every SQL statement for data loss, locks, table
rewrites, constraint validation, tenant integrity, index strategy, RLS effects, and compatibility with
currently deployed package/API versions. Add a migration comment or release note explaining rollback
limitations. High-risk changes require a verified backup and restore plan.

## Verify

Apply to an isolated development/test database under human control, then run generation, unit and
integration tests, type-checking, and build. Test upgrades from a representative prior schema, not only
a fresh database. Compare expected migration status and inspect query plans for high-volume changes.

## Production order

1. Confirm backup/restore and monitoring readiness.
2. Deploy an expansion migration using `npm run migration:deploy` and the migration role.
3. Verify migration status and application health.
4. Publish/install the compatible package and deploy API readers/writers.
5. Backfill in bounded, resumable batches when required.
6. Remove old readers/writers before a later contract migration.

Never use `db push`, automatic startup migration, or edited applied history. If an unexpected result
appears, stop and follow `recovery.md`.
