import { randomUUID } from 'node:crypto';

import type { PrismaService } from '../../src/database/prisma.service.js';
import {
	assertTestDatabaseWasVerified,
	type VerifiedTestDatabase,
} from './test-database-safety.js';

/** Reserves child UUIDs before writes; cleanup requires the independently verified test database. */
export class OwnerEnrollmentTestFixtures {
	readonly #challengeIds = new Set<string>();
	readonly #auditIds = new Set<string>();

	reserveChallengeId(verified: VerifiedTestDatabase): string {
		assertTestDatabaseWasVerified(verified);
		const id = randomUUID();
		this.#challengeIds.add(id);
		return id;
	}

	reserveAuditId(verified: VerifiedTestDatabase): string {
		assertTestDatabaseWasVerified(verified);
		const id = randomUUID();
		this.#auditIds.add(id);
		return id;
	}

	async cleanup(prisma: PrismaService, verified: VerifiedTestDatabase): Promise<void> {
		assertTestDatabaseWasVerified(verified);
		if (this.#auditIds.size === 0 && this.#challengeIds.size === 0) return;
		await prisma.$transaction(
			async (transaction) => {
				if (this.#auditIds.size > 0) {
					await transaction.organizationOwnerAcceptanceAuditEvent.deleteMany({
						where: { id: { in: [...this.#auditIds] } },
					});
				}
				if (this.#challengeIds.size > 0) {
					await transaction.organizationOwnerEnrollmentChallenge.deleteMany({
						where: { id: { in: [...this.#challengeIds] } },
					});
				}
			},
			{ maxWait: 10_000, timeout: 20_000 },
		);
		this.#auditIds.clear();
		this.#challengeIds.clear();
	}
}
