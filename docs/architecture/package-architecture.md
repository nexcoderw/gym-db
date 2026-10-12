# Package Architecture

## Boundary

`gym-db` is a compiled ESM library. `gym-api` imports only `@nexcoderw/gym-db`; deep imports are not a
contract. There is no bootstrap file, listening socket, controller, or deployable web process.

```text
gym-api authentication/authorization
            |
            v
DatabaseModule -> TenantTransactionService -> PrismaService -> adapter-pg -> PostgreSQL
                                              |
                                              v
                                  generated Prisma Client
                                              ^
                                              |
                               schema + reviewed migrations
```

## Client generation and packaging

Prisma 7 requires an explicit `prisma-client` output and a driver adapter. Generation writes TypeScript
to `src/generated/prisma`; Git ignores it so schema and migrations remain the reviewable source. The
human release workflow generates first, TypeScript compiles generated and authored sources together,
and npm publishes `dist`. Consumers receive JavaScript and declarations and do not need this repository,
its schema, or Prisma generation.

`@prisma/client`, `@prisma/adapter-pg`, and `pg` are runtime dependencies. Nest, RxJS, and
`reflect-metadata` are peers so the API owns one compatible Nest runtime.

## Lifecycle and configuration

The API calls `loadDatabaseConfig` before accepting traffic. `PrismaService` establishes its pool in
Nest module initialization and disconnects on module destruction. `gym-api` must enable shutdown hooks.
One module registration and one client per process prevents uncontrolled pool multiplication.

## Tenant boundary

The API authenticates and authorizes tenant identity. The database package validates identifier shape
and offers a transaction boundary using PostgreSQL `set_config(..., true)`. Future RLS may read this
context, but every Prisma query remains deliberately tenant-scoped unless reviewed policy proves
otherwise. Privileged cross-tenant operations require a separate design and ADR.
