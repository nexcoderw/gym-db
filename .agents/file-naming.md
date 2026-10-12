# File Naming

## Purpose and scope

Give database artifacts predictable, searchable names.

## Mandatory engineering requirements

Use kebab-case filenames, Nest suffixes (`.module.ts`, `.service.ts`), `.spec.ts` tests, descriptive
Markdown names, PascalCase TypeScript types, camelCase values, singular PascalCase Prisma models, and
snake_case database mappings. Prisma-generated migration directories retain their timestamp prefix and
a descriptive snake_case suffix.

## Forbidden patterns

No `utils.ts`, `helpers.ts`, `temp.ts`, ambiguous abbreviations, people’s names, or renaming applied
migration directories.

## Correct example

`20261012143000_add_organization_tenant_key/` and `tenant-transaction.service.ts`.

## Common mistakes

Using plural model names, encoding version numbers in source filenames, or mixing casing styles.

## Review checklist

- Names describe behavior or data and follow the conventions above.
- A migration name states the database action and subject.
