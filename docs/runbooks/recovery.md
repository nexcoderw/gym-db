# Database Recovery Runbook

## Immediate response

Stop the rollout, preserve logs and migration output without credentials/personal data, notify the
database/API owners, and prevent additional incompatible writers. Do not edit applied migration
history, run `db push`, or improvise destructive SQL.

## Assess

Record the migration name, package/API versions, affected environment, start/end time, PostgreSQL
error, lock state, row impact, and backup recovery point. Determine whether the failed migration rolled
back transactionally or left partial non-transactional effects. Check migration status read-only.

## Recover

Prefer a reviewed forward-fix migration. Roll back application code only when the expanded schema is
backwards-compatible. Restore a backup only with explicit incident approval and a known recovery point,
accounting for writes after that point. Prisma migration reconciliation commands require a written
plan and human execution.

## Close

Verify schema state, constraints, representative tenant isolation, API health, and monitoring. Record
the incident timeline, data impact, commands, evidence, and preventive actions. Update this runbook and
tests before resuming the rollout.
