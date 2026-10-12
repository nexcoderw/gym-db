# Mandatory Claude Code Instructions

Before changing this repository, read `.agents/README.md` and all linked rules relevant to the task.
Those database-specific rules are mandatory; do not rely on automatic rule discovery.

The repository is a private NestJS-compatible database library, not an HTTP application. It alone
owns Prisma schema and migration history. Never run dependency installation, generation, formatting,
linting, tests, builds, database commands, Git writes, or publication. Give those commands to the
human developer. The authoritative workflow and restrictions are in `.agents/agent-workflow.md`.
