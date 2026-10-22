#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

target_sha="${1:-}"
run_reference="${2:-manual}"

if [[ ! "$target_sha" =~ ^[0-9a-f]{40}$ ]]; then
	echo 'The deployment target must be a full Git commit SHA.' >&2
	exit 2
fi

if [[ ! "$run_reference" =~ ^[A-Za-z0-9._-]+$ ]]; then
	echo 'The deployment run reference contains unsupported characters.' >&2
	exit 2
fi

if [[ "$(id -un)" != 'mucyora' ]]; then
	echo 'Run this deployment as the mucyora production user.' >&2
	exit 2
fi

application_root='/var/www/mucyora'
live_repository="$application_root/api/db"
releases_root="$application_root/releases"
component_releases="$releases_root/db"
release_id="$(date -u +%Y%m%dT%H%M%SZ)-${target_sha:0:12}-$run_reference"
release_directory="$component_releases/$release_id"
staged_repository="$release_directory/source"
rollback_directory="$release_directory/rollback"
pg_dump_binary="${PG_DUMP_BINARY:-/usr/lib/postgresql/18/bin/pg_dump}"
old_commit=''
promotion_complete=0

install -d -m 750 "$component_releases"
exec 9>"$application_root/.production-deployment.lock"
flock -w 900 9

if [[ ! -x "$pg_dump_binary" ]]; then
	echo "PostgreSQL 18 client is required at $pg_dump_binary." >&2
	echo 'Install postgresql-client-18 from the official PostgreSQL APT repository.' >&2
	exit 1
fi

cleanup_release_history() {
	local candidate
	local cleanup_status=0

	for candidate in "$component_releases"/*; do
		[[ -d "$candidate" && "$candidate" != "$release_directory" ]] || continue
		if ! rm -rf -- "$candidate"; then
			echo "Unable to remove previous database release: $candidate" >&2
			cleanup_status=1
		fi
	done

	for candidate in "$releases_root"/*; do
		[[ -d "$candidate" ]] || continue
		case "$(basename "$candidate")" in
			db | api | manager) ;;
			*)
				if ! rm -rf -- "$candidate"; then
					echo "Unable to remove legacy release: $candidate" >&2
					cleanup_status=1
				fi
				;;
		esac
	done

	if ! git -C "$live_repository" worktree prune; then
		echo 'Unable to prune database deployment worktrees.' >&2
		cleanup_status=1
	fi

	return "$cleanup_status"
}

restore_previous_runtime() {
	if [[ -d "$rollback_directory/dist" ]]; then
		[[ ! -e "$live_repository/dist" ]] || mv "$live_repository/dist" "$release_directory/failed-dist"
		mv "$rollback_directory/dist" "$live_repository/dist"
	fi

	if [[ -d "$rollback_directory/node_modules" ]]; then
		[[ ! -e "$live_repository/node_modules" ]] ||
			mv "$live_repository/node_modules" "$release_directory/failed-node-modules"
		mv "$rollback_directory/node_modules" "$live_repository/node_modules"
	fi

	if [[ -n "$old_commit" ]]; then
		git -C "$live_repository" checkout --detach "$old_commit"
	fi
}

on_exit() {
	local status=$?

	if ((status != 0)); then
		restore_previous_runtime || true
		rm -rf -- "$release_directory"
		git -C "$live_repository" worktree prune || true
	elif ((promotion_complete == 1)); then
		if ! cleanup_release_history; then
			echo 'Database deployment succeeded, but release cleanup needs attention.' >&2
		fi
	fi

	return "$status"
}
trap on_exit EXIT

if [[ -n "$(git -C "$live_repository" status --porcelain)" ]]; then
	echo 'The production database repository contains uncommitted files.' >&2
	exit 1
fi

git -C "$live_repository" fetch --prune origin main
git -C "$live_repository" cat-file -e "$target_sha^{commit}"
git -C "$live_repository" merge-base --is-ancestor "$target_sha" origin/main
old_commit="$(git -C "$live_repository" rev-parse HEAD)"

install -d -m 750 "$release_directory"
git -C "$live_repository" worktree add --detach "$staged_repository" "$target_sha"
install -m 600 "$live_repository/.env.production" "$staged_repository/.env.production"

(
	cd "$staged_repository"
	npx --yes npm@10.8.2 ci --include=dev
	NODE_ENV=production npm run prisma:generate
	npm run format:check
	npm run lint
	npm run typecheck
	npm run test:unit
	npm run build
)

dump_path="$release_directory/pre-migration.dump"
DUMP_PATH="$dump_path" PG_DUMP_BINARY="$pg_dump_binary" \
	node --env-file="$staged_repository/.env.production" --input-type=module -e '
	import { spawnSync } from "node:child_process";
	const databaseUrl = process.env.DATABASE_URL;
	const dumpPath = process.env.DUMP_PATH;
	const pgDumpBinary = process.env.PG_DUMP_BINARY;
	if (!databaseUrl || !dumpPath || !pgDumpBinary) process.exit(2);
	const target = new URL(databaseUrl);
	if (!["postgres:", "postgresql:"].includes(target.protocol)) process.exit(2);
	const databaseName = decodeURIComponent(target.pathname.replace(/^\//u, ""));
	if (!target.hostname || !target.username || !databaseName) process.exit(2);
	const pgEnvironment = {
		...process.env,
		PGHOST: target.hostname,
		PGPORT: target.port || "5432",
		PGUSER: decodeURIComponent(target.username),
		PGPASSWORD: decodeURIComponent(target.password),
		PGDATABASE: databaseName,
	};
	const connectionOptions = {
		sslmode: "PGSSLMODE",
		channel_binding: "PGCHANNELBINDING",
		connect_timeout: "PGCONNECT_TIMEOUT",
		application_name: "PGAPPNAME",
	};
	for (const [parameter, environmentName] of Object.entries(connectionOptions)) {
		const value = target.searchParams.get(parameter);
		if (value) pgEnvironment[environmentName] = value;
	}
	const sslMode = target.searchParams.get("sslmode");
	const sslRootCertificate = target.searchParams.get("sslrootcert");
	if (sslRootCertificate) {
		pgEnvironment.PGSSLROOTCERT = sslRootCertificate;
	} else if (["verify-ca", "verify-full"].includes(sslMode)) {
		pgEnvironment.PGSSLROOTCERT = "system";
	}
	const result = spawnSync(
		pgDumpBinary,
		["--format=custom", "--no-owner", "--no-privileges", "--file", dumpPath],
		{ env: pgEnvironment, stdio: "inherit" },
	);
	process.exit(result.status ?? 1);
'
chmod 600 "$dump_path"

(
	cd "$staged_repository"
	NODE_ENV=production npm run migration:status
	NODE_ENV=production npm run migration:deploy
	NODE_ENV=production npm run migration:status
)

cp -a "$staged_repository/dist" "$live_repository/dist.next-$release_id"
cp -a "$staged_repository/node_modules" "$live_repository/node_modules.next-$release_id"
git -C "$live_repository" checkout --detach "$target_sha"

install -d -m 750 "$rollback_directory"
mv "$live_repository/dist" "$rollback_directory/dist"
mv "$live_repository/node_modules" "$rollback_directory/node_modules"
mv "$live_repository/dist.next-$release_id" "$live_repository/dist"
mv "$live_repository/node_modules.next-$release_id" "$live_repository/node_modules"

node --input-type=module -e "await import('file://$live_repository/dist/index.js')"
promotion_complete=1

printf 'Database package deployed at %s\n' "$target_sha"
