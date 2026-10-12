# Privacy

## Purpose and scope

Minimize and protect personal data throughout its lifecycle.

## Mandatory engineering requirements

Collect only required fields, classify sensitive data, document purpose and retention, restrict access
by tenant and role, encrypt in transit and at rest, support reviewed deletion/anonymization workflows,
and consider Rwandan data protection and contractual residency requirements with legal/security owners.
Use synthetic data in development and tests. Audit privileged access without logging sensitive values.

## Forbidden patterns

No real customer exports in tests, secrets or personal data in logs/migration comments, indefinite
retention by default, analytics copies without governance, or destructive privacy workflows without
audit and authorization.

## Correct example

Fictional member records use reserved example domains and documented retention instead of copied
production profiles.

## Common mistakes

Treating soft deletion as legal erasure, retaining backups forever, or exposing personal fields in
wide default selects.

## Review checklist

- Purpose, minimization, retention, residency, access, deletion, backup, and audit impacts were reviewed.
- Test and documentation examples are entirely fictional.
