import * as databasePackage from '../../src/index.js';

describe('public package exports', () => {
	it('exposes only the supported database API', () => {
		expect(typeof databasePackage.DatabaseModule).toBe('function');
		expect(typeof databasePackage.PrismaClient).toBe('function');
		expect(typeof databasePackage.PrismaService).toBe('function');
		expect(typeof databasePackage.TenantTransactionService).toBe('function');
		expect(typeof databasePackage.loadDatabaseConfig).toBe('function');
	});
});
