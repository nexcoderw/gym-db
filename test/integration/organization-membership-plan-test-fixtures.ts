import { randomUUID } from 'node:crypto';

import type { PrismaService } from '../../src/database/prisma.service.js';
import {
	assertTestDatabaseWasVerified,
	type VerifiedTestDatabase,
} from './test-database-safety.js';

/** Tracks only membership plans reserved by one test run. */
export class OrganizationMembershipPlanTestFixtures {
	readonly #ids = new Set<string>();

	reserveId(verifiedDatabase: VerifiedTestDatabase): string {
		assertTestDatabaseWasVerified(verifiedDatabase);
		const id = randomUUID();
		this.#ids.add(id);
		return id;
	}

	async cleanup(prisma: PrismaService, verifiedDatabase: VerifiedTestDatabase): Promise<void> {
		assertTestDatabaseWasVerified(verifiedDatabase);
		if (this.#ids.size === 0) return;
		await prisma.organizationMembershipPlan.deleteMany({
			where: { id: { in: [...this.#ids] } },
		});
		this.#ids.clear();
	}
}
