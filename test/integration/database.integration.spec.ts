import { Test, type TestingModule } from '@nestjs/testing';

import { DatabaseModule } from '../../src/database/database.module.js';
import { PrismaService } from '../../src/database/prisma.service.js';
import { TenantTransactionService } from '../../src/database/tenant-transaction.service.js';

const testDatabaseUrl = process.env.TEST_DATABASE_URL;
const describeWithDatabase = testDatabaseUrl === undefined ? describe.skip : describe;

describeWithDatabase('database integration', () => {
	let module: TestingModule;
	let prisma: PrismaService;

	beforeAll(async () => {
		module = await Test.createTestingModule({
			imports: [
				DatabaseModule.forRoot({
					databaseUrl: testDatabaseUrl ?? '',
					poolMax: 2,
					connectionTimeoutMilliseconds: 5_000,
				}),
			],
		}).compile();
		await module.init();
		prisma = module.get(PrismaService);
	});

	afterAll(async () => {
		await module.close();
	});

	it('connects to an isolated PostgreSQL test database', async () => {
		await expect(prisma.$queryRaw`SELECT 1`).resolves.toEqual([{ '?column?': 1 }]);
	});

	it('keeps tenant settings local to their transaction', async () => {
		const tenantTransactions = module.get(TenantTransactionService);
		const organizationId = '11111111-1111-4111-8111-111111111111';

		await expect(
			tenantTransactions.run({ organizationId }, async (transaction) => {
				return transaction.$queryRaw<{ organization_id: string }[]>`
					SELECT current_setting('app.current_organization_id', true) AS organization_id
				`;
			}),
		).resolves.toEqual([{ organization_id: organizationId }]);

		const outsideTransaction = await prisma.$queryRaw<{ organization_id: string | null }[]>`
				SELECT current_setting('app.current_organization_id', true) AS organization_id
			`;
		expect(outsideTransaction[0]?.organization_id).not.toBe(organizationId);
	});
});
