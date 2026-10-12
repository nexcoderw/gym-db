import * as databasePackage from '../../src/index.js';

describe('public package exports', () => {
	it('exposes only the supported database API', () => {
		expect(databasePackage).toEqual(
			expect.objectContaining({
				DatabaseModule: expect.any(Function),
				PrismaClient: expect.any(Function),
				PrismaService: expect.any(Function),
				TenantTransactionService: expect.any(Function),
				loadDatabaseConfig: expect.any(Function),
			}),
		);
	});
});
