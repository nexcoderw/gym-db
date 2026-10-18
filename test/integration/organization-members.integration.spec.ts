import { randomUUID } from 'node:crypto';

import { jest } from '@jest/globals';
import { Test, type TestingModule } from '@nestjs/testing';

import { DatabaseModule } from '../../src/database/database.module.js';
import { PrismaService } from '../../src/database/prisma.service.js';
import { MemberPeriodUnit } from '../../src/generated/prisma/client.js';
import { OrganizationTestFixtures } from './organization-test-fixtures.js';
import {
	assertTestDatabaseWasVerified,
	loadTestDatabaseSafetyConfig,
	verifyTestDatabaseSafety,
	verifyTestTablePrivileges,
	type VerifiedTestDatabase,
} from './test-database-safety.js';

const safety = loadTestDatabaseSafetyConfig();
jest.setTimeout(180_000);

describe('organization member persistence', () => {
	let module: TestingModule | undefined;
	let prisma: PrismaService;
	let verified: VerifiedTestDatabase | undefined;
	let organizations: OrganizationTestFixtures;
	let gym: string;
	let otherGym: string;
	let actor: string;
	let plan: string;
	const memberIds = new Set<string>();
	const subscriptionIds = new Set<string>();
	const planIds = new Set<string>();
	const userIds = new Set<string>();

	beforeAll(async () => {
		module = await Test.createTestingModule({
			imports: [
				DatabaseModule.forRoot({
					databaseUrl: safety.databaseUrl,
					poolMax: 3,
					connectionTimeoutMilliseconds: 30_000,
				}),
			],
		}).compile();
		await module.init();
		prisma = module.get(PrismaService);
		const safe = await verifyTestDatabaseSafety(prisma, safety);
		await verifyTestTablePrivileges(prisma, [
			{ tableName: 'organization_members', privileges: ['SELECT', 'INSERT', 'UPDATE', 'DELETE'] },
			{
				tableName: 'organization_member_subscriptions',
				privileges: ['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
			},
			{
				tableName: 'organization_membership_plans',
				privileges: ['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
			},
			{ tableName: 'users', privileges: ['SELECT', 'INSERT', 'DELETE'] },
		]);
		verified = safe;
	});

	beforeEach(async () => {
		assertTestDatabaseWasVerified(verified);
		organizations = new OrganizationTestFixtures();
		const first = organizations.reserve(verified);
		const second = organizations.reserve(verified);
		gym = first.id;
		otherGym = second.id;
		await prisma.organization.create({ data: { ...first, name: 'Example Strength Gym' } });
		await prisma.organization.create({ data: { ...second, name: 'Example Fitness Gym' } });
		actor = reserve(userIds);
		await prisma.user.create({
			data: { id: actor, displayName: 'Example Operator', email: `${actor}@example.com` },
		});
		plan = reserve(planIds);
		await prisma.organizationMembershipPlan.create({
			data: {
				id: plan,
				organizationId: gym,
				name: 'Monthly access',
				normalizedName: 'monthly access',
				priceRwf: 30_000n,
			},
		});
	});

	afterEach(async () => {
		if (verified === undefined) return;
		assertTestDatabaseWasVerified(verified);
		await prisma.organizationMemberSubscription.deleteMany({
			where: { id: { in: [...subscriptionIds] } },
		});
		await prisma.organizationMember.deleteMany({ where: { id: { in: [...memberIds] } } });
		await prisma.organizationMembershipPlan.deleteMany({ where: { id: { in: [...planIds] } } });
		await prisma.user.deleteMany({ where: { id: { in: [...userIds] } } });
		await organizations.cleanup(prisma, verified);
		for (const ids of [subscriptionIds, memberIds, planIds, userIds]) ids.clear();
	});

	afterAll(async () => module?.close());

	it('allows the same contact keys in different gyms but not twice in one gym', async () => {
		await createMember(gym);
		await createMember(otherGym);
		await expect(createMember(gym, 'another member', '+250700000001')).rejects.toMatchObject({
			code: 'P2002',
		});
		await expect(createMember(gym, 'example member', '+250700000002')).rejects.toMatchObject({
			code: 'P2002',
		});
	});

	it('allows omitted or shared emails for distinct members', async () => {
		const first = await createMember(gym);
		const second = await createMember(gym, 'another member', '+250700000002');
		expect(first.email).toBeNull();
		await prisma.organizationMember.updateMany({
			where: { organizationId: gym, id: { in: [first.id, second.id] } },
			data: { email: 'shared@example.com' },
		});
		expect(
			await prisma.organizationMember.count({
				where: { organizationId: gym, email: 'shared@example.com' },
			}),
		).toBe(2);
	});

	it('rejects a subscription linking to a member in another gym', async () => {
		const foreignMember = await createMember(otherGym);
		await expect(
			prisma.organizationMemberSubscription.create({
				data: subscriptionData(gym, foreignMember.id, plan),
			}),
		).rejects.toMatchObject({ code: 'P2003' });
	});

	it('rejects a subscription linking to a plan in another gym', async () => {
		const member = await createMember(otherGym);
		await expect(
			prisma.organizationMemberSubscription.create({
				data: subscriptionData(otherGym, member.id, plan),
			}),
		).rejects.toMatchObject({ code: 'P2003' });
	});

	it('retains historical terms when the underlying plan changes', async () => {
		const member = await createMember(gym);
		const registered = await prisma.organizationMemberSubscription.create({
			data: subscriptionData(gym, member.id, plan),
		});
		await prisma.organizationMembershipPlan.updateMany({
			where: { organizationId: gym, id: plan },
			data: { name: 'Updated offer', priceRwf: 50_000n },
		});
		const history = await prisma.organizationMemberSubscription.findFirstOrThrow({
			where: { organizationId: gym, id: registered.id },
		});
		expect(history).toMatchObject({ planName: 'Monthly access', priceRwf: 30_000n });
		await expect(
			prisma.organizationMember.delete({ where: { id: member.id } }),
		).rejects.toMatchObject({ code: 'P2003' });
	});

	it('enforces registration idempotency keys within each gym', async () => {
		const member = await createMember(gym);
		const first = subscriptionData(gym, member.id, plan);
		await prisma.organizationMemberSubscription.create({ data: first });
		const retry = {
			...subscriptionData(gym, member.id, plan),
			idempotencyKey: first.idempotencyKey,
			startDate: new Date('2030-02-01T00:00:00.000Z'),
			endDate: new Date('2030-02-28T00:00:00.000Z'),
		};
		await expect(
			prisma.organizationMemberSubscription.create({ data: retry }),
		).rejects.toMatchObject({ code: 'P2002' });
	});

	it('rolls back profile creation when its first plan registration fails', async () => {
		const id = reserve(memberIds);
		await expect(
			prisma.$transaction(async (transaction) => {
				await transaction.organizationMember.create({
					data: {
						id,
						organizationId: otherGym,
						name: 'Rollback Member',
						normalizedName: 'rollback member',
						phoneNumber: '+250700000003',
					},
				});
				await transaction.organizationMemberSubscription.create({
					data: subscriptionData(otherGym, id, plan),
				});
			}),
		).rejects.toMatchObject({ code: 'P2003' });
		expect(
			await prisma.organizationMember.findFirst({ where: { organizationId: otherGym, id } }),
		).toBeNull();
	});

	it('enforces profile checks in PostgreSQL', async () => {
		await expect(createMember(gym, ' ', '+250700000001')).rejects.toMatchObject(sqlState('23514'));
		await expect(createMember(gym, 'example member', '0700000001')).rejects.toMatchObject(
			sqlState('23514'),
		);
	});

	it.each([
		{ periodCount: 0 },
		{ periodCount: 121 },
		{ priceRwf: -1n },
		{ requestFingerprint: 'invalid' },
		{ endDate: new Date('2030-02-01T00:00:00.000Z') },
		{ cancelledByUserId: null, cancelledAt: new Date() },
	])('rejects invalid subscription data in PostgreSQL: %#', async (invalid) => {
		const member = await createMember(gym);
		await expect(
			prisma.organizationMemberSubscription.create({
				data: { ...subscriptionData(gym, member.id, plan), ...invalid },
			}),
		).rejects.toMatchObject(sqlState('23514'));
	});

	it('rejects concurrent overlapping registrations without application locks', async () => {
		const member = await createMember(gym);
		const results = await Promise.allSettled([
			prisma.organizationMemberSubscription.create({
				data: subscriptionData(gym, member.id, plan),
			}),
			prisma.organizationMemberSubscription.create({
				data: subscriptionData(gym, member.id, plan),
			}),
		]);
		expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
		const rejected = results.find((result) => result.status === 'rejected');
		expect(rejected?.reason).toMatchObject(sqlState('23P01'));
	});

	it('allows adjacent periods and replacement after cancellation, preserving history', async () => {
		const member = await createMember(gym);
		const registered = await prisma.organizationMemberSubscription.create({
			data: subscriptionData(gym, member.id, plan),
		});
		await prisma.organizationMemberSubscription.create({
			data: {
				...subscriptionData(gym, member.id, plan),
				startDate: new Date('2030-02-01T00:00:00.000Z'),
				endDate: new Date('2030-02-28T00:00:00.000Z'),
			},
		});
		await expect(
			prisma.organizationMemberSubscription.update({
				where: { id: registered.id },
				data: { priceRwf: 1n },
			}),
		).rejects.toMatchObject(sqlState('23514'));
		await prisma.organizationMemberSubscription.update({
			where: { id: registered.id },
			data: { cancelledAt: new Date(), cancelledByUserId: actor },
		});
		await expect(
			prisma.organizationMemberSubscription.update({
				where: { id: registered.id },
				data: { cancelledAt: null, cancelledByUserId: null },
			}),
		).rejects.toMatchObject(sqlState('23514'));
		await prisma.organizationMemberSubscription.create({
			data: subscriptionData(gym, member.id, plan),
		});
	});

	function sqlState(code: string) {
		return { meta: { driverAdapterError: { cause: { originalCode: code } } } };
	}

	function reserve(ids: Set<string>): string {
		assertTestDatabaseWasVerified(verified);
		const id = randomUUID();
		ids.add(id);
		return id;
	}

	function createMember(
		organizationId: string,
		normalizedName = 'example member',
		phoneNumber = '+250700000001',
	) {
		return prisma.organizationMember.create({
			data: {
				id: reserve(memberIds),
				organizationId,
				name: normalizedName,
				normalizedName,
				phoneNumber,
			},
		});
	}

	function subscriptionData(organizationId: string, memberId: string, membershipPlanId: string) {
		return {
			id: reserve(subscriptionIds),
			organizationId,
			memberId,
			membershipPlanId,
			planName: 'Monthly access',
			priceRwf: 30_000n,
			periodUnit: MemberPeriodUnit.MONTHS,
			periodCount: 1,
			startDate: new Date('2030-01-01T00:00:00.000Z'),
			endDate: new Date('2030-01-31T00:00:00.000Z'),
			idempotencyKey: randomUUID(),
			requestFingerprint: 'a'.repeat(64),
			createdByUserId: actor,
		};
	}
});
