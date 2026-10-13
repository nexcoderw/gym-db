import { randomUUID } from 'node:crypto';

import type { PrismaService } from '../../src/database/prisma.service.js';
import { assertTestDatabaseWasVerified, type VerifiedTestDatabase } from './test-database-safety.js';

interface OrganizationAuditFixture {
	readonly id: string;
	readonly organizationId: string;
	readonly actorPlatformStaffId: string;
}

interface AuthorizationAuditFixture {
	readonly id: string;
	readonly targetPlatformStaffId: string;
	readonly targetPlatformRoleId: string;
	readonly correlationId: string;
}

/** Audit cleanup is separately granted ONLY in the independently marked disposable database. */
export class AuditTestFixtures {
	readonly #organizationEvents: OrganizationAuditFixture[] = [];
	readonly #authorizationEvents: AuthorizationAuditFixture[] = [];

	reserveOrganizationEvent(
		verified: VerifiedTestDatabase,
		organizationId: string,
		actorPlatformStaffId: string,
	): OrganizationAuditFixture {
		assertTestDatabaseWasVerified(verified);
		const fixture = { id: randomUUID(), organizationId, actorPlatformStaffId };
		this.#organizationEvents.push(fixture);
		return fixture;
	}

	reserveAuthorizationEvent(
		verified: VerifiedTestDatabase,
		targetPlatformStaffId: string,
		targetPlatformRoleId: string,
	): AuthorizationAuditFixture {
		assertTestDatabaseWasVerified(verified);
		const fixture = {
			id: randomUUID(),
			targetPlatformStaffId,
			targetPlatformRoleId,
			correlationId: randomUUID(),
		};
		this.#authorizationEvents.push(fixture);
		return fixture;
	}

	async cleanup(prisma: PrismaService, verified: VerifiedTestDatabase): Promise<void> {
		assertTestDatabaseWasVerified(verified);
		await prisma.$transaction(
			async (transaction) => {
				if (this.#organizationEvents.length > 0) {
					await transaction.organizationAuditEvent.deleteMany({
						where: { OR: this.#organizationEvents.map((fixture) => ({ ...fixture })) },
					});
				}
				if (this.#authorizationEvents.length > 0) {
					await transaction.platformAuthorizationAuditEvent.deleteMany({
						where: { OR: this.#authorizationEvents.map((fixture) => ({ ...fixture })) },
					});
				}
			},
			{ maxWait: 10_000, timeout: 15_000 },
		);
		this.#organizationEvents.length = 0;
		this.#authorizationEvents.length = 0;
	}
}
