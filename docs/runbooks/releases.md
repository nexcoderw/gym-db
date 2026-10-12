# Package Release Runbook

## Preconditions

The reviewed schema/migrations, generated client, lockfile, tests, and compatibility plan must be
approved. Choose SemVer impact and update `package.json` with `npm version --no-git-tag-version` only
after the worktree is clean enough to inspect the version diff.

## Human-operated verification

From `api/db`:

```bash
npm install
npm run prisma:generate
npm run prisma:validate
npm run format:check
npm run lint
npm run typecheck
npm run test:unit
TEST_DATABASE_URL='postgresql://...' npm run test:integration
npm run build
npm pack --dry-run
```

Inspect the pack list for `dist/index.js`, declarations, and compiled generated Prisma client. It must
not contain `.env`, source secrets, tests, or schema paths required at consumer runtime.

## Authenticate and publish

Use a GitHub token with `write:packages` and repository access:

```bash
npm login --scope=@nexcoderw --auth-type=legacy --registry=https://npm.pkg.github.com
npm publish
```

Create and push the reviewed commit and immutable annotated `vX.Y.Z` tag separately. Never overwrite a
published version. Consumers authenticate with `read:packages`, install the exact version, review their
lockfile, test, and deploy in the compatibility order from the migration runbook.
