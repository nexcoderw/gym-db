const POSTGRES_PROTOCOLS = new Set(['postgres:', 'postgresql:']);

/** Runtime settings accepted by the database package. */
export interface DatabaseConfig {
	/** PostgreSQL connection string used by the application role. */
	readonly databaseUrl: string;
	/** Maximum number of connections in this process's pool. */
	readonly poolMax: number;
	/** Maximum time allowed to establish a pool connection. */
	readonly connectionTimeoutMilliseconds: number;
}

const DEFAULT_POOL_MAX = 10;
const DEFAULT_CONNECTION_TIMEOUT_MILLISECONDS = 10_000;

function parsePositiveInteger(value: string | undefined, fallback: number, name: string): number {
	if (value === undefined) {
		return fallback;
	}

	const parsed = Number(value);
	if (!Number.isSafeInteger(parsed) || parsed <= 0) {
		throw new Error(`${name} must be a positive integer.`);
	}

	return parsed;
}

/**
 * Validates database environment variables without ever including credentials in an error.
 * The API should call this during bootstrap and fail before accepting traffic.
 */
export function loadDatabaseConfig(environment: NodeJS.ProcessEnv = process.env): DatabaseConfig {
	const databaseUrl = environment['DATABASE_URL'];
	if (databaseUrl === undefined || databaseUrl.trim() === '') {
		throw new Error('DATABASE_URL is required.');
	}

	let parsedUrl: URL;
	try {
		parsedUrl = new URL(databaseUrl);
	} catch {
		throw new Error('DATABASE_URL must be a valid PostgreSQL connection URL.');
	}

	if (!POSTGRES_PROTOCOLS.has(parsedUrl.protocol)) {
		throw new Error('DATABASE_URL must use the postgresql: or postgres: protocol.');
	}

	return Object.freeze({
		databaseUrl,
		poolMax: parsePositiveInteger(
			environment['DATABASE_POOL_MAX'],
			DEFAULT_POOL_MAX,
			'DATABASE_POOL_MAX',
		),
		connectionTimeoutMilliseconds: parsePositiveInteger(
			environment['DATABASE_CONNECTION_TIMEOUT_MS'],
			DEFAULT_CONNECTION_TIMEOUT_MILLISECONDS,
			'DATABASE_CONNECTION_TIMEOUT_MS',
		),
	});
}
