# Platform Administrator Identity and Authorization

## Scope and trust boundary

`User` is the reusable global identity for people who may later interact with NEXCODE or one or more
gyms. Creating a user does not create a `PlatformStaff` record, assign a role, or grant a permission.
Platform authorization must fail closed unless all of these future API checks succeed:

1. The request has an authenticated `User` whose status is `ACTIVE`.
2. The user has a `PlatformStaff` record whose status is `ACTIVE`.
3. The staff record has an explicitly assigned role with the required permission.
4. Required MFA and any operation-specific controls have succeeded.

Login proves identity only. It never proves authorization to operate `admin.gym.rw`. Platform tables
are global NEXCODE data and intentionally have no gym `organizationId` or tenant RLS context.

## Relationship diagram

```text
User ──0..1── PasswordCredential
  │
  └──0..1── PlatformStaff ──0..*── PlatformStaffRole ──1── PlatformRole
                                                               │
                                                               └──0..*── PlatformRolePermission
                                                                                 │
                                                                                 └──1── PlatformPermission
```

The join tables use composite primary keys, so a staff-role or role-permission relationship cannot be
duplicated. Reverse-side indexes support role membership and permission assignment lookups.

Role and permission keys also use `citext` uniqueness to prevent case-variant authorization keys. The
future API must accept only canonical lowercase dot-separated keys; database uniqueness is defense in
depth against concurrent or non-API writes.

## Models and database guarantees

- `User` stores only global identity fields, verification time, and a controlled account status.
- `PasswordCredential` stores one password hash per user, separate from ordinary identity reads.
- `PlatformStaff` is an explicit platform-access assignment with pending, active, suspended, and
  revoked states. It is unique per user.
- `PlatformRole` has a stable unique key. `isSystem` identifies built-in roles but does not itself
  grant access or bypass permission checks.
- `PlatformPermission` has a stable unique capability key. Absence of a mapping means denial.
- `PlatformStaffRole` and `PlatformRolePermission` record explicit assignments.

Every primary and foreign key is PostgreSQL `uuid`. Security-sensitive foreign keys use `RESTRICT` for
both deletion and identifier updates. Revocation therefore uses statuses and explicit relationship
removal rather than accidental cascading deletion. Destructive privacy or retention work must follow
a separately reviewed, audited procedure.

## Email normalization and uniqueness

`User.email` uses PostgreSQL `citext` with a unique constraint, so case variants such as
`aline.uwase@example.com` and `ALINE.UWASE@EXAMPLE.COM` cannot become separate identities. The future
API must still trim surrounding whitespace, validate length and syntax, and store a canonical lowercase
form after Unicode normalization. Database case-insensitive uniqueness is the final concurrency-safe
control and does not replace application validation.

The generated migration must enable `citext` before creating `users`:

```sql
CREATE EXTENSION IF NOT EXISTS citext;
```

The migration SQL must be reviewed before application because PostgreSQL extensions require migration
role privileges and must also be available to the shadow and test databases.

## Credential lifecycle

Only an approved application-layer password-hashing implementation may populate `passwordHash`.
Plaintext passwords, access tokens, sessions, MFA secrets, and recovery codes do not belong in these
tables. Password changes replace the encoded hash and update `passwordChangedAt`; logs, errors,
fixtures, analytics, and convenience projections must never expose credential material.

Password policy, hashing parameters, rehashing, breach response, reset flows, and credential retention
remain deferred to the authentication implementation. A credential row is not proof of an active
account or platform access.

## Suspension, revocation, and bootstrap

Suspending `User` disables the identity at the future API authorization boundary. Suspending or
revoking `PlatformStaff` removes platform eligibility without deleting the user. Future authorization
must evaluate both states on every privileged request and must not rely only on cached role claims.

Ordinary migrations create no users, staff records, roles, permissions, or assignments. The first
platform owner must be provisioned later through a separate human-controlled bootstrap procedure with
identity verification, required MFA, dual control, short-lived credentials, and an immutable audit
record. The first registered account must never be promoted automatically.

## Database roles and tenant separation

Production should use distinct least-privilege roles:

- A migration role owns schema changes and extension activation but is never used by runtime traffic.
- A platform identity/authorization role receives only the operations required on identity, credential,
  staff, role, and permission tables.
- A gym tenant role receives no direct privileges on password credentials or platform RBAC tables.
- A bounded read-only operations role excludes credential hashes and requires audited access.

The package currently exposes one configured Prisma client and does not create PostgreSQL grants.
Production role grants and separate connection boundaries must be reviewed before platform or gym API
traffic is enabled. Sharing this package does not authorize a tenant request to query platform data.

## Migration, release, and recovery

This is an additive schema change, but the generated migration requires explicit `citext` activation
and review of every table, enum, unique constraint, index, and restrictive foreign key. Apply it first
to a disposable migrated PostgreSQL database, regenerate Prisma Client, and run the full unit and
integration suites before publishing a compatible package version.

Rolling the package back is safe while no deployed API requires the new models. Reversing the database
migration after identities or assignments exist is destructive and must not be used as routine
recovery; prefer a reviewed forward fix and preserve security and audit records.

## Explicitly deferred work

This foundation does not implement authentication services, password verification, sessions, OAuth,
JWTs, MFA, HTTP endpoints, effective-permission caching, privileged-operation audit records, platform
role seed data, or gym organization membership. Those controls require later reviewed steps in the
appropriate repository.
