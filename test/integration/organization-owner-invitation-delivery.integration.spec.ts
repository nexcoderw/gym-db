import { createHash, randomUUID } from 'node:crypto';

import { jest } from '@jest/globals';
import { Test, type TestingModule } from '@nestjs/testing';

import { DatabaseModule } from '../../src/database/database.module.js';
import { PrismaService } from '../../src/database/prisma.service.js';
import {
	OrganizationOwnerInvitationDeliveryStatus,
	OrganizationOwnerInvitationStatus,
	OrganizationOwnershipAuditAction,
	OrganizationStatus,
	PlatformStaffStatus,
	UserStatus,
	type Prisma,
} from '../../src/index.js';
import { OrganizationOwnerInvitationDeliveryTestFixtures } from './organization-owner-invitation-delivery-test-fixtures.js';
import { OrganizationOwnerInvitationTestFixtures } from './organization-owner-invitation-test-fixtures.js';
import { OrganizationTestFixtures } from './organization-test-fixtures.js';
import { PlatformAdminTestFixtures } from './platform-admin-test-fixtures.js';
import {
	loadTestDatabaseSafetyConfig,
	verifyTestDatabaseSafety,
	verifyTestTablePrivileges,
	type VerifiedTestDatabase,
} from './test-database-safety.js';

const safety = loadTestDatabaseSafetyConfig();
const transactionOptions = { maxWait: 10_000, timeout: 20_000 } as const;
const requiredChecks = [
	'organization_owner_invitation_deliveries_lifecycle_check',
	'organization_owner_invitation_deliveries_lease_check',
	'organization_owner_invitation_deliveries_retry_check',
	'organization_owner_invitation_deliveries_token_material_check',
	'organization_owner_invitation_deliveries_timestamp_order_check',
	'organization_owner_invitation_deliveries_bounded_text_check',
];

jest.setTimeout(60_000);

describe('organization owner invitation delivery foundation', () => {
	let module: TestingModule | undefined;
	let prisma: PrismaService;
	let verified: VerifiedTestDatabase | undefined;
	let organizations: OrganizationTestFixtures;
	let identities: PlatformAdminTestFixtures;
	let invitations: OrganizationOwnerInvitationTestFixtures;
	let deliveries: OrganizationOwnerInvitationDeliveryTestFixtures;
	const additionalDeliveryFixtures: OrganizationOwnerInvitationDeliveryTestFixtures[] = [];

	beforeAll(async () => {
		module = await Test.createTestingModule({
			imports: [
				DatabaseModule.forRoot({
					databaseUrl: safety.databaseUrl,
					poolMax: 4,
					connectionTimeoutMilliseconds: 10_000,
				}),
			],
		}).compile();
		await module.init();
		prisma = module.get(PrismaService);
		const safe = await verifyTestDatabaseSafety(prisma, safety);
		const [table] = await prisma.$queryRaw<{ name: string | null }[]>`
			SELECT to_regclass('public.organization_owner_invitation_deliveries')::text AS name
		`;
		const checks = await prisma.$queryRaw<{ name: string }[]>`
			SELECT conname AS name FROM pg_catalog.pg_constraint
			WHERE conrelid = to_regclass('public.organization_owner_invitation_deliveries')
				AND contype = 'c' AND convalidated
		`;
		const indexes = await prisma.$queryRaw<{ name: string }[]>`
			SELECT indexname AS name FROM pg_catalog.pg_indexes
			WHERE schemaname = 'public'
				AND tablename = 'organization_owner_invitation_deliveries'
		`;
		if (
			table?.name === null ||
			table === undefined ||
			requiredChecks.some((name) => !checks.some((check) => check.name === name)) ||
			!indexes.some(
				({ name }) => name === 'owner_invitation_deliveries_org_invitation_key',
			) ||
			!indexes.some(
				({ name }) => name === 'organization_owner_invitation_deliveries_worker_claim_idx',
			)
		) {
			throw new Error(
				'Owner invitation delivery prerequisites are missing: approve and apply the Step 18 ' +
					'migration, lifecycle constraints, indexes and grants before integration tests.',
			);
		}
		await verifyTestTablePrivileges(prisma, [
			{
				tableName: 'organization_owner_invitation_deliveries',
				privileges: ['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
			},
		]);
		verified = safe;
	});

	beforeEach(() => {
		organizations = new OrganizationTestFixtures();
		identities = new PlatformAdminTestFixtures();
		invitations = new OrganizationOwnerInvitationTestFixtures();
		deliveries = new OrganizationOwnerInvitationDeliveryTestFixtures();
		additionalDeliveryFixtures.length = 0;
	});

	afterEach(async () => {
		if (verified === undefined) return;
		for (const fixtures of [...additionalDeliveryFixtures, deliveries]) {
			await fixtures.cleanup(prisma, verified);
		}
		await invitations.cleanup(prisma, verified);
		await organizations.cleanup(prisma, verified);
		await identities.cleanup(prisma, verified);
	});

	afterAll(async () => {
		await module?.close();
	});

	function requireVerified(): VerifiedTestDatabase {
		if (verified === undefined) throw new Error('Invitation delivery test database is not verified.');
		return verified;
	}

	async function createOrganization(name = 'Kigali Strength Club'): Promise<string> {
		const fixture = organizations.reserve(requireVerified());
		await prisma.organization.create({
			data: { ...fixture, name, status: OrganizationStatus.ACTIVE, activatedAt: new Date() },
		});
		return fixture.id;
	}

	async function createActor(): Promise<string> {
		const userId = identities.reserveUserId();
		const actorId = identities.reservePlatformStaffId();
		await prisma.user.create({
			data: {
				id: userId,
				email: `delivery-actor-${userId}@example.com`,
				displayName: 'Aline Uwase',
				status: UserStatus.ACTIVE,
				emailVerifiedAt: new Date(),
				platformStaff: { create: { id: actorId, status: PlatformStaffStatus.ACTIVE } },
			},
		});
		return actorId;
	}

	async function createInvitation(organizationId: string, actorId: string): Promise<string> {
		const invitationId = invitations.reserveInvitationId(requireVerified());
		await prisma.organizationOwnerInvitation.create({
			data: {
				id: invitationId,
				organizationId,
				invitedEmail: `future-owner-${invitationId}@example.com`,
				invitedDisplayName: 'Future Gym Owner',
				invitedByPlatformStaffId: actorId,
			},
		});
		return invitationId;
	}

	function deliveryData(
		organizationId: string,
		ownerInvitationId: string,
		requestedByPlatformStaffId: string,
	): Prisma.OrganizationOwnerInvitationDeliveryUncheckedCreateInput & { readonly id: string } {
		const id = deliveries.reserveDeliveryId(requireVerified());
		return {
			id,
			organizationId,
			ownerInvitationId,
			requestedByPlatformStaffId,
			nextAttemptAt: new Date(),
			providerIdempotencyKey: `owner-invitation-delivery:${id}`,
			tokenDigest: createHash('sha256').update(`fictional-token:${id}`).digest('hex'),
			tokenCiphertext: Buffer.from(`encrypted-fixture-${id}`),
			tokenInitializationVector: Buffer.alloc(12, 1),
			tokenAuthenticationTag: Buffer.alloc(16, 2),
			tokenEncryptionKeyId: 'test-key-2026-10',
			tokenEncryptionVersion: 1,
			tokenExpiresAt: new Date(Date.now() + 24 * 60 * 60 * 1_000),
		};
	}

	function queuedAuditData(
		organizationId: string,
		ownerInvitationId: string,
		actorId: string,
	): Prisma.OrganizationOwnershipAuditEventUncheckedCreateInput & { readonly id: string } {
		return {
			id: invitations.reserveAuditEventId(requireVerified()),
			organizationId,
			ownerInvitationId,
			actorPlatformStaffId: actorId,
			action: OrganizationOwnershipAuditAction.INVITATION_DELIVERY_QUEUED,
			requestId: randomUUID(),
			previousInvitationStatus: OrganizationOwnerInvitationStatus.PENDING_DELIVERY,
			resultingInvitationStatus: OrganizationOwnerInvitationStatus.PENDING_DELIVERY,
			occurredAt: new Date(),
		};
	}

	it('persists one organization-scoped queued reservation and its administrator audit atomically', async () => {
		const organizationId = await createOrganization();
		const actorId = await createActor();
		const invitationId = await createInvitation(organizationId, actorId);
		const delivery = deliveryData(organizationId, invitationId, actorId);

		await prisma.$transaction(async (transaction) => {
			await transaction.organizationOwnerInvitationDelivery.create({ data: delivery });
			await transaction.organizationOwnershipAuditEvent.create({
				data: queuedAuditData(organizationId, invitationId, actorId),
			});
		}, transactionOptions);

		expect(
			await prisma.organizationOwnerInvitationDelivery.findUniqueOrThrow({
				where: { id: delivery.id },
			}),
		).toMatchObject({
			organizationId,
			ownerInvitationId: invitationId,
			requestedByPlatformStaffId: actorId,
			status: OrganizationOwnerInvitationDeliveryStatus.QUEUED,
			attemptCount: 0,
			maxAttempts: 3,
			providerMessageId: null,
			lastErrorCode: null,
		});
		expect(
			await prisma.organizationOwnerInvitation.findUniqueOrThrow({ where: { id: invitationId } }),
		).toMatchObject({ status: OrganizationOwnerInvitationStatus.PENDING_DELIVERY });
		expect(await prisma.organizationMembership.count({ where: { organizationId } })).toBe(0);
		expect(await prisma.organizationRole.count({ where: { organizationId } })).toBe(0);
	});

	it('rejects cross-organization delivery links and duplicate invitation reservations', async () => {
		const organizationId = await createOrganization();
		const otherOrganizationId = await createOrganization('Nyamirambo Fitness');
		const actorId = await createActor();
		const invitationId = await createInvitation(organizationId, actorId);

		await expect(
			prisma.organizationOwnerInvitationDelivery.create({
				data: deliveryData(otherOrganizationId, invitationId, actorId),
			}),
		).rejects.toMatchObject({ code: 'P2003' });

		const first = deliveryData(organizationId, invitationId, actorId);
		await prisma.organizationOwnerInvitationDelivery.create({ data: first });
		await expect(
			prisma.organizationOwnerInvitationDelivery.create({
				data: deliveryData(organizationId, invitationId, actorId),
			}),
		).rejects.toMatchObject({ code: 'P2002' });
	});

	it('allows exactly one concurrent worker to claim a queued delivery', async () => {
		const organizationId = await createOrganization();
		const actorId = await createActor();
		const invitationId = await createInvitation(organizationId, actorId);
		const delivery = deliveryData(organizationId, invitationId, actorId);
		await prisma.organizationOwnerInvitationDelivery.create({ data: delivery });
		const claimedAt = new Date();

		const claims = await Promise.all(
			['worker-a', 'worker-b'].map((claimedBy) =>
				prisma.organizationOwnerInvitationDelivery.updateMany({
					where: {
						id: delivery.id,
						status: OrganizationOwnerInvitationDeliveryStatus.QUEUED,
						nextAttemptAt: { lte: claimedAt },
						attemptCount: { lt: 3 },
					},
					data: {
						status: OrganizationOwnerInvitationDeliveryStatus.PROCESSING,
						attemptCount: { increment: 1 },
						nextAttemptAt: null,
						leaseAcquiredAt: claimedAt,
						leaseExpiresAt: new Date(claimedAt.getTime() + 60_000),
						claimedBy,
					},
				}),
			),
		);

		expect(claims.reduce((sum, claim) => sum + claim.count, 0)).toBe(1);
		expect(
			await prisma.organizationOwnerInvitationDelivery.findUniqueOrThrow({
				where: { id: delivery.id },
			}),
		).toMatchObject({
			status: OrganizationOwnerInvitationDeliveryStatus.PROCESSING,
			attemptCount: 1,
		});
	});

	it('recovers an expired worker lease without resetting the bounded attempt count', async () => {
		const organizationId = await createOrganization();
		const actorId = await createActor();
		const invitationId = await createInvitation(organizationId, actorId);
		const now = new Date();
		const delivery = deliveryData(organizationId, invitationId, actorId);
		await prisma.organizationOwnerInvitationDelivery.create({
			data: {
				...delivery,
				status: OrganizationOwnerInvitationDeliveryStatus.PROCESSING,
				attemptCount: 1,
				nextAttemptAt: null,
				leaseAcquiredAt: new Date(now.getTime() - 120_000),
				leaseExpiresAt: new Date(now.getTime() - 60_000),
				claimedBy: 'expired-worker',
			},
		});

		const recovered = await prisma.organizationOwnerInvitationDelivery.updateMany({
			where: {
				id: delivery.id,
				status: OrganizationOwnerInvitationDeliveryStatus.PROCESSING,
				leaseExpiresAt: { lt: now },
				attemptCount: { lt: 3 },
			},
			data: {
				status: OrganizationOwnerInvitationDeliveryStatus.QUEUED,
				nextAttemptAt: now,
				leaseAcquiredAt: null,
				leaseExpiresAt: null,
				claimedBy: null,
			},
		});

		expect(recovered.count).toBe(1);
		expect(
			await prisma.organizationOwnerInvitationDelivery.findUniqueOrThrow({
				where: { id: delivery.id },
			}),
		).toMatchObject({
			status: OrganizationOwnerInvitationDeliveryStatus.QUEUED,
			attemptCount: 1,
			leaseAcquiredAt: null,
			leaseExpiresAt: null,
			claimedBy: null,
		});
	});

	it('finalizes provider acceptance with the invitation transition and encrypted-token erasure', async () => {
		const organizationId = await createOrganization();
		const actorId = await createActor();
		const invitationId = await createInvitation(organizationId, actorId);
		const delivery = deliveryData(organizationId, invitationId, actorId);
		if (delivery.tokenDigest === null || delivery.tokenDigest === undefined) {
			throw new Error('The delivery fixture must contain a token digest.');
		}
		const tokenDigest = delivery.tokenDigest;
		const claimedAt = new Date(Date.now() + 1_000);
		const sentAt = new Date(claimedAt.getTime() + 1_000);
		await prisma.organizationOwnerInvitationDelivery.create({
			data: {
				...delivery,
				status: OrganizationOwnerInvitationDeliveryStatus.PROCESSING,
				attemptCount: 1,
				nextAttemptAt: null,
				leaseAcquiredAt: claimedAt,
				leaseExpiresAt: new Date(claimedAt.getTime() + 60_000),
				claimedBy: 'confirmation-worker',
			},
		});

		await prisma.$transaction(async (transaction) => {
			const transitioned = await transaction.organizationOwnerInvitation.updateMany({
				where: {
					id: invitationId,
					organizationId,
					status: OrganizationOwnerInvitationStatus.PENDING_DELIVERY,
				},
				data: {
					status: OrganizationOwnerInvitationStatus.SENT,
					tokenDigest,
					sentAt,
					expiresAt: delivery.tokenExpiresAt,
				},
			});
			if (transitioned.count !== 1) throw new Error('Invitation is no longer delivery eligible.');
			await transaction.organizationOwnerInvitationDelivery.update({
				where: { id: delivery.id },
				data: {
					status: OrganizationOwnerInvitationDeliveryStatus.CONFIRMED,
					providerMessageId: `resend-${delivery.id}`,
					confirmedAt: sentAt,
					nextAttemptAt: null,
					leaseAcquiredAt: null,
					leaseExpiresAt: null,
					claimedBy: null,
					tokenCiphertext: null,
					tokenInitializationVector: null,
					tokenAuthenticationTag: null,
					tokenEncryptionKeyId: null,
					tokenEncryptionVersion: null,
					tokenDigest: null,
					tokenErasedAt: sentAt,
				},
			});
		}, transactionOptions);

		expect(
			await prisma.organizationOwnerInvitation.findUniqueOrThrow({ where: { id: invitationId } }),
		).toMatchObject({
			status: OrganizationOwnerInvitationStatus.SENT,
			tokenDigest,
		});
		expect(
			await prisma.organizationOwnerInvitationDelivery.findUniqueOrThrow({
				where: { id: delivery.id },
			}),
		).toMatchObject({
			status: OrganizationOwnerInvitationDeliveryStatus.CONFIRMED,
			tokenCiphertext: null,
			tokenInitializationVector: null,
			tokenAuthenticationTag: null,
			tokenEncryptionKeyId: null,
			tokenEncryptionVersion: null,
			tokenDigest: null,
		});
	});

	it('prevents a revoked invitation from being finalized after a worker claim', async () => {
		const organizationId = await createOrganization();
		const actorId = await createActor();
		const invitationId = await createInvitation(organizationId, actorId);
		const delivery = deliveryData(organizationId, invitationId, actorId);
		const now = new Date(Date.now() + 1_000);
		await prisma.organizationOwnerInvitationDelivery.create({
			data: {
				...delivery,
				status: OrganizationOwnerInvitationDeliveryStatus.PROCESSING,
				attemptCount: 1,
				nextAttemptAt: null,
				leaseAcquiredAt: now,
				leaseExpiresAt: new Date(now.getTime() + 60_000),
				claimedBy: 'revocation-race-worker',
			},
		});
		await prisma.organizationOwnerInvitation.update({
			where: { id: invitationId },
			data: { status: OrganizationOwnerInvitationStatus.REVOKED, revokedAt: now },
		});

		const transitioned = await prisma.organizationOwnerInvitation.updateMany({
			where: {
				id: invitationId,
				organizationId,
				status: OrganizationOwnerInvitationStatus.PENDING_DELIVERY,
			},
			data: {
				status: OrganizationOwnerInvitationStatus.SENT,
				tokenDigest: delivery.tokenDigest,
				sentAt: now,
				expiresAt: delivery.tokenExpiresAt,
			},
		});
		expect(transitioned.count).toBe(0);

		await prisma.organizationOwnerInvitationDelivery.update({
			where: { id: delivery.id },
			data: {
				status: OrganizationOwnerInvitationDeliveryStatus.UNCERTAIN,
				uncertainAt: now,
				lastErrorCode: 'INVITATION_NO_LONGER_ELIGIBLE',
				leaseAcquiredAt: null,
				leaseExpiresAt: null,
				claimedBy: null,
			},
		});
		expect(
			await prisma.organizationOwnerInvitation.findUniqueOrThrow({ where: { id: invitationId } }),
		).toMatchObject({
			status: OrganizationOwnerInvitationStatus.REVOKED,
			tokenDigest: null,
		});
	});

	it('records retryable failure and uncertain provider outcomes without blind resend', async () => {
		const organizationId = await createOrganization();
		const actorId = await createActor();
		const invitationId = await createInvitation(organizationId, actorId);
		const failed = deliveryData(organizationId, invitationId, actorId);
		const failedAt = new Date(Date.now() + 1_000);
		await prisma.organizationOwnerInvitationDelivery.create({
			data: {
				...failed,
				status: OrganizationOwnerInvitationDeliveryStatus.FAILED,
				attemptCount: 1,
				failedAt,
				lastErrorCode: 'PROVIDER_REJECTED',
				nextAttemptAt: new Date(failedAt.getTime() + 60_000),
			},
		});
		expect(
			await prisma.organizationOwnerInvitationDelivery.findUniqueOrThrow({
				where: { id: failed.id },
			}),
		).toMatchObject({
			status: OrganizationOwnerInvitationDeliveryStatus.FAILED,
			attemptCount: 1,
			lastErrorCode: 'PROVIDER_REJECTED',
		});

		const uncertainInvitationId = await createInvitation(organizationId, actorId);
		const uncertain = deliveryData(organizationId, uncertainInvitationId, actorId);
		await prisma.organizationOwnerInvitationDelivery.create({
			data: {
				...uncertain,
				status: OrganizationOwnerInvitationDeliveryStatus.UNCERTAIN,
				attemptCount: 1,
				uncertainAt: new Date(Date.now() + 1_000),
				lastErrorCode: 'PROVIDER_TIMEOUT',
				nextAttemptAt: null,
			},
		});
		expect(
			await prisma.organizationOwnerInvitationDelivery.findUniqueOrThrow({
				where: { id: uncertain.id },
			}),
		).toMatchObject({
			status: OrganizationOwnerInvitationDeliveryStatus.UNCERTAIN,
			nextAttemptAt: null,
			lastErrorCode: 'PROVIDER_TIMEOUT',
		});
	});

	it('rejects incomplete encrypted material and impossible lifecycle metadata', async () => {
		const organizationId = await createOrganization();
		const actorId = await createActor();
		const invitationId = await createInvitation(organizationId, actorId);
		const data = deliveryData(organizationId, invitationId, actorId);

		await expect(
			prisma.organizationOwnerInvitationDelivery.create({
				data: { ...data, tokenAuthenticationTag: null },
			}),
		).rejects.toThrow('organization_owner_invitation_deliveries_token_material_check');
		await expect(
			prisma.organizationOwnerInvitationDelivery.create({
				data: {
					...deliveryData(organizationId, invitationId, actorId),
					status: OrganizationOwnerInvitationDeliveryStatus.CONFIRMED,
					providerMessageId: null,
					confirmedAt: null,
				},
			}),
		).rejects.toThrow('organization_owner_invitation_deliveries_lifecycle_check');
	});

	it('rolls back delivery preparation when its required administrator audit fails', async () => {
		const organizationId = await createOrganization();
		const actorId = await createActor();
		const invitationId = await createInvitation(organizationId, actorId);
		const delivery = deliveryData(organizationId, invitationId, actorId);

		await expect(
			prisma.$transaction(async (transaction) => {
				await transaction.organizationOwnerInvitationDelivery.create({ data: delivery });
				await transaction.organizationOwnershipAuditEvent.create({
					data: {
						...queuedAuditData(organizationId, invitationId, actorId),
						requestId: 'invalid request id',
					},
				});
			}, transactionOptions),
		).rejects.toThrow();

		expect(
			await prisma.organizationOwnerInvitationDelivery.findUnique({
				where: { id: delivery.id },
			}),
		).toBeNull();
	});

	it('keeps delivery persistence unavailable through PUBLIC', async () => {
		const grants = await prisma.$queryRaw<{ count: number }[]>`
			SELECT count(*)::integer AS count FROM pg_catalog.pg_class AS relation
			CROSS JOIN LATERAL aclexplode(
				coalesce(relation.relacl, acldefault('r', relation.relowner))
			) AS grant_entry
			WHERE relation.oid = 'public.organization_owner_invitation_deliveries'::regclass
				AND grant_entry.grantee = 0
		`;
		expect(grants).toEqual([{ count: 0 }]);
	});

	it('cleans only reserved delivery rows and preserves an unrelated sentinel', async () => {
		const organizationId = await createOrganization();
		const actorId = await createActor();
		const invitationId = await createInvitation(organizationId, actorId);
		const tracked = deliveryData(organizationId, invitationId, actorId);
		await prisma.organizationOwnerInvitationDelivery.create({ data: tracked });

		const sentinelOrganizationId = await createOrganization('Remera Training Centre');
		const sentinelInvitationId = await createInvitation(sentinelOrganizationId, actorId);
		const sentinelFixtures = new OrganizationOwnerInvitationDeliveryTestFixtures();
		additionalDeliveryFixtures.push(sentinelFixtures);
		const sentinelId = sentinelFixtures.reserveDeliveryId(requireVerified());
		await prisma.organizationOwnerInvitationDelivery.create({
			data: {
				...deliveryData(sentinelOrganizationId, sentinelInvitationId, actorId),
				id: sentinelId,
				providerIdempotencyKey: `owner-invitation-delivery:${sentinelId}`,
				tokenDigest: createHash('sha256')
					.update(`fictional-token:${sentinelId}`)
					.digest('hex'),
			},
		});

		await deliveries.cleanup(prisma, requireVerified());
		expect(
			await prisma.organizationOwnerInvitationDelivery.findUnique({
				where: { id: sentinelId },
			}),
		).not.toBeNull();
	});
});
