# Formatting

## Purpose and scope

Keep formatting deterministic and ESLint-compatible.

## Mandatory engineering requirements

Use tabs in TypeScript/JavaScript, tab width 2, print width 100, single quotes, semicolons, trailing
commas, LF endings, and spaces where JSON/YAML/Markdown syntax expects them. Generated Prisma output
is excluded from formatting. ESLint and Prettier must not conflict.

## Forbidden patterns

No manual alignment with spaces in TypeScript, mixed line endings, formatting generated code, or
drive-by reformatting unrelated files.

## Correct example

Run `npm run format` only when the human workflow authorizes command execution, then inspect the diff.

## Common mistakes

Assuming tabs apply inside JSON, or enabling an ESLint style rule already owned by Prettier.

## Review checklist

- Configuration matches `.editorconfig` and `.prettierrc.json`.
- Formatting changes are intentional and scoped.
