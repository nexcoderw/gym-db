# TypeScript

## Purpose and scope

Maintain strict, consumable ESM types for NestJS and Prisma callers.

## Mandatory engineering requirements

Keep `strict` and NodeNext resolution enabled. Use `unknown` with narrowing, `import type`, readonly
contracts, explicit public return types, `.js` extensions in relative source imports, and exhaustive
handling for unions. Export only from `src/index.ts`.

## Forbidden patterns

No `any`, unchecked assertions, `@ts-ignore`, non-null assertions for environment values, CommonJS
runtime imports, or consumer imports into `src/` internals.

## Correct example

`catch (error: unknown)` narrows the value before reading error-specific properties.

## Common mistakes

Assuming generated nullable fields are present, or exporting implementation types by accident through
a wildcard barrel.

## Review checklist

- Strict compilation should succeed after Prisma generation.
- Runtime imports and declaration output work under Node ESM.
