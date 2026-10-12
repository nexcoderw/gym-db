import { Test } from '@nestjs/testing';

import { PrismaService } from '../../src/database/prisma.service.js';
import { TenantTransactionService } from '../../src/database/tenant-transaction.service.js';

describe('TenantTransactionService', () => {
	it('rejects invalid tenant identifiers before opening a transaction', async () => {
		const transaction = jest.fn();
		const module = await Test.createTestingModule({
			providers: [
				TenantTransactionService,
				{ provide: PrismaService, useValue: { $transaction: transaction } },
			],
		}).compile();
		const service = module.get(TenantTransactionService);

		await expect(
			service.run({ organizationId: 'not-a-uuid' }, async () => undefined),
		).rejects.toThrow('organizationId must be a valid UUID.');
		expect(transaction).not.toHaveBeenCalled();
	});

	it('sets tenant context before invoking the operation', async () => {
		const executeRaw = jest.fn().mockResolvedValue(1);
		const transactionClient = { $executeRaw: executeRaw };
		const transaction = jest.fn(async (callback: (client: typeof transactionClient) => unknown) =>
			callback(transactionClient),
		);
		const module = await Test.createTestingModule({
			providers: [
				TenantTransactionService,
				{ provide: PrismaService, useValue: { $transaction: transaction } },
			],
		}).compile();
		const service = module.get(TenantTransactionService);
		const operation = jest.fn().mockResolvedValue('complete');

		await expect(
			service.run(
				{
					organizationId: '11111111-1111-4111-8111-111111111111',
					branchId: '22222222-2222-4222-8222-222222222222',
				},
				operation,
			),
		).resolves.toBe('complete');
		expect(executeRaw).toHaveBeenCalledTimes(2);
		expect(operation).toHaveBeenCalledWith(transactionClient);
	});
});
