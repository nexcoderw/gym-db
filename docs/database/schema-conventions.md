# Schema Conventions

## Identity and naming

- Use stable UUID primary identifiers for organizations, branches, and tenant-owned entities.
- Use singular PascalCase Prisma models and explicit snake_case mappings when database names differ.
- Every tenant record has `organizationId`; branch-owned records also have a branch relation whose
  organization is enforceably consistent.
- Scoped names/slugs use compound uniqueness such as `(organizationId, slug)`.

## Integrity

Declare nullability, relation actions, unique rules, checks, and indexes intentionally. Put
`organizationId` first in common tenant query indexes. Cascades are permitted only for true aggregate
ownership with reviewed deletion impact. Store instants in UTC. Use exact `BigInt` whole francs for RWF
amounts and convert through bigint/string-safe application boundaries—never JavaScript floating point.

## Lifecycle

Use consistent `createdAt` and `updatedAt` fields where record lifecycle matters. A nullable deletion
timestamp is not, by itself, privacy erasure. Status fields should use reviewed enums when their state
space is closed and migrations account for safe enum evolution.

## Example

Fictional Soho Gym may own Kimihurura and Remera branches. A branch slug is unique within Soho Gym,
not necessarily across every NEXCODE tenant. No example may use real member data.
