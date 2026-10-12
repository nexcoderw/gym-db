# Database Design

## Purpose and scope

Define durable PostgreSQL models and enforce integrity near the data.

## Mandatory engineering requirements

Use stable UUID identifiers for primary tenant entities, UTC timestamps, explicit nullability,
foreign keys and delete behavior, named indexes/constraints where supported, normalized data, and
tenant-leading compound indexes. Model RWF as exact whole-franc `BigInt` values; never floating point.
Map schema names deliberately and include `createdAt`/`updatedAt` consistently where lifecycle matters.

## Forbidden patterns

No orphanable relations, polymorphic foreign keys without enforcement, comma-separated lists,
ambiguous status strings, unbounded blobs, or cascade deletes without documented ownership.

## Correct example

An organization-scoped branch slug is unique on `(organizationId, slug)`, not globally unique.

## Common mistakes

Indexing a tenant-owned lookup without `organizationId`, storing RWF in `Float`, or using local time
in the database. `Africa/Kigali` belongs at display/scheduling boundaries, while storage stays UTC.

## Review checklist

- Keys, constraints, indexes, nullability, timestamps, and deletion semantics are explicit.
- Financial and tenant invariants are database-enforced where possible.
