import { Injectable } from '@nestjs/common';

import type { Prisma } from '../generated/prisma/client.js';
import type { TenantContext } from '../types/tenant-context.js';
import { PrismaService } from './prisma.service.js';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

export type TenantTransactionCallback<TResult> = (
	transaction: Prisma.TransactionClient,
) => Promise<TResult>;

/**
 * Runs tenant-owned operations in a transaction with PostgreSQL session context set locally.
 * The API must authenticate and authorize the organization and optional branch before calling this
 * service; UUID validation verifies identifier shape, not access. The operation starts only after
 * both settings are initialized. Future RLS policies must read them with
 * `current_setting(name, true)` and deny access when organization context is absent.
 *
 * PostgreSQL clears these transaction-local values on commit or rollback, preventing pooled
 * connections from carrying tenant context into later transactions.
 */
@Injectable()
export class TenantTransactionService {
	constructor(private readonly prisma: PrismaService) {}

	async run<TResult>(
		context: TenantContext,
		operation: TenantTransactionCallback<TResult>,
	): Promise<TResult> {
		this.assertUuid(context.organizationId, 'organizationId');
		if (context.branchId !== undefined) {
			this.assertUuid(context.branchId, 'branchId');
		}

		return this.prisma.$transaction(async (transaction) => {
			await transaction.$queryRaw`
				SELECT set_config('app.current_organization_id', ${context.organizationId}, true)
			`;
			await transaction.$queryRaw`
				SELECT set_config('app.current_branch_id', ${context.branchId ?? ''}, true)
			`;

			return operation(transaction);
		});
	}

	private assertUuid(value: string, field: keyof TenantContext): void {
		if (!UUID_PATTERN.test(value)) {
			throw new Error(`${field} must be a valid UUID.`);
		}
	}
}
