# Package Release Runbook

## Preconditions

The reviewed schema/migrations, generated client, lockfile, tests, and compatibility plan must be
approved. Choose SemVer impact and update `package.json` with `npm version --no-git-tag-version` only
after the worktree is clean enough to inspect the version diff.

## Human-operated verification

From `api/db`:

```bash
npm install
set -a
source .env.local
set +a
npm run prisma:generate
npm run prisma:validate
npm run format:check
npm run lint
npm run typecheck
npm run test:unit
npm run test:integration
npm run build
npm pack --dry-run
```

Provision and verify the disposable target through the
[secure integration-test runbook](integration-tests.md) before release verification. A distinct URL
without the required database marker and restricted role is insufficient.

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
