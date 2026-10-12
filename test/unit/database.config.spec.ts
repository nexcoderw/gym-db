import { loadDatabaseConfig } from '../../src/config/database.config.js';

describe('loadDatabaseConfig', () => {
	it('validates and returns immutable defaults', () => {
		const config = loadDatabaseConfig({
			DATABASE_URL: 'postgresql://app:secret@localhost:5432/nexcode_gym',
		});

		expect(config).toEqual({
			databaseUrl: 'postgresql://app:secret@localhost:5432/nexcode_gym',
			poolMax: 10,
			connectionTimeoutMilliseconds: 10_000,
		});
		expect(Object.isFrozen(config)).toBe(true);
	});

	it('rejects a missing connection string', () => {
		expect(() => loadDatabaseConfig({})).toThrow('DATABASE_URL is required.');
	});

	it('rejects non-PostgreSQL protocols without exposing the URL', () => {
		const secret = 'do-not-log-this';
		expect(() => loadDatabaseConfig({ DATABASE_URL: `mysql://app:${secret}@localhost/gym` })).toThrow(
			'DATABASE_URL must use the postgresql: or postgres: protocol.',
		);

		try {
			loadDatabaseConfig({ DATABASE_URL: `mysql://app:${secret}@localhost/gym` });
		} catch (error: unknown) {
			expect(String(error)).not.toContain(secret);
		}
	});

	it('rejects invalid pool settings', () => {
		expect(() =>
			loadDatabaseConfig({
				DATABASE_URL: 'postgresql://localhost/gym',
				DATABASE_POOL_MAX: '0',
			}),
		).toThrow('DATABASE_POOL_MAX must be a positive integer.');
	});
});
