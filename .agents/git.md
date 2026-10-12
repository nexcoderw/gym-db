# Git Workflow

**Purpose:** Keep CareBasket's history clean, reviewable, and free of secrets, with the developer in full control of every Git write.
**Applies to:** The end of every task, and anything that decides what may be committed.
**Related:** [workflow.md](workflow.md), [security.md § 10](security.md#10-secret-management), [submission.md](submission.md)
**Last reviewed:** 2026-10-09

---

## 1. Agent rules

- Agents **never** run Git write commands: `add`, `commit`, `push`, `pull`, `merge`, `rebase`, `reset`, `restore`, `checkout -- <path>`, `stash`, `tag`, `cherry-pick`, `clean`, or branch creation and deletion ([workflow.md § 1.1](workflow.md#11-agents-must-not-execute)).
- Agents may run read-only commands (`git status`, `git diff`, `git log`, `git show`) to understand the working tree.
- At the end of each task, agents list **one commit message per changed file** and show the exact commands for the developer to run: one `git add <file>` and `git commit` pair per file, in the order defined in §2. For example:

```bash
git add src/features/checkout/server/service.ts
git commit -m "feat(checkout): capture and verify PayPal sandbox orders"

git add src/features/checkout/server/service.test.ts
git commit -m "test(checkout): cover capture verification failures"
```

## 2. Changes

- **One file per commit.** Every changed file gets its own commit with its own message that describes that file's change. This is the developer's standing rule.
- **Order commits by dependency:** a file comes before the files that import, test, or link to it (for example, a new rule document before the index that links to it; a stylesheet before the test that reads it; `schema.prisma` before its migration; `package.json` before `package-lock.json`).
- No unrelated edits: no drive-by reformatting, renames, or dependency bumps.
- Rule files (`.agents/`) are committed before or after code files, never interleaved with them.

## 3. Commit messages

Format: `type(scope): summary`

- `type`: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `style`, `perf`
- `scope`: a feature or area (`auth`, `devices`, `requests`, `assistant`, `checkout`, `catalog`, `ui`, `db`, `rules`)
- `summary`: imperative, lowercase, no trailing period, at most 72 characters
- Add a body only when the reason is not obvious from the summary.

Examples: `feat(devices): add adult approval for pairing codes`, `fix(checkout): reject capture when amount differs`, `docs(rules): establish agent engineering rules`.

## 4. What may be committed

| Commit | Do not commit |
| --- | --- |
| Source, tests, styles, docs | `.env`, `.env.local`, any file with secret values |
| `prisma/schema.prisma`, `prisma/migrations/**`, `prisma/seed.ts` | `src/generated/**` (Prisma Client output) |
| `package.json` and `package-lock.json` in consecutive commits, when dependencies change | `node_modules/`, `.next/`, `coverage/`, build output |
| `.env.local.example` and `.env.production.example` with names, non-secret defaults, and placeholders only | Screenshots or exports containing personal data or credentials |
| Curated product images in `public/products/` with `ATTRIBUTION.md`, and `prisma/catalog/catalog.us.json` (ODbL) | Large binaries, videos, raw design files, audio recordings, catalog candidate reports, raw API dumps |
| `LICENSE`, `README.md` | Editor and OS files (`.DS_Store`, local IDE settings) |

Notes:

- `.gitignore` ignores `.env*` but allows only `.env.local.example` and `.env.production.example`. These templates never contain credentials or environment-specific secret values.
- `package-lock.json` changes only through the developer's npm commands and is committed right after the matching `package.json` commit.
- The `.agents/skills/`, `.claude/skills/`, and `.windsurf/skills/` directories and `skills-lock.json` are agent tooling; committing them is the developer's choice.

## 5. Branches and history

- `main` stays demonstrable. Work on short-lived branches named `type/short-description` (for example `feat/device-pairing`) when the developer wants a branch.
- No force pushes to `main` or any shared branch. No history rewriting after pushing.
- No destructive commands (`reset --hard`, `clean -fd`, `push --force`) without the developer's own decision.

## 6. Secrets in Git

- Before committing, the developer checks `git diff --staged` for keys, tokens, connection strings, and personal data.
- If a secret is ever committed, rotate it at the provider immediately. Removing it from history is not enough once it has been pushed.
- The repository will be public for the hackathon ([hackathon.md](hackathon.md)). Treat every commit as public.

## 7. Acceptance criteria

- [ ] Every changed file has its own suggested commit, in dependency order (§2).
- [ ] Every suggested message follows §3.
- [ ] No ignored, generated, or secret files are included.
- [ ] The agent performed no Git writes.
