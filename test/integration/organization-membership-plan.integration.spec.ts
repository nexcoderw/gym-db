import { jest } from '@jest/globals';
import { Test, type TestingModule } from '@nestjs/testing';

import { DatabaseModule } from '../../src/database/database.module.js';
import { PrismaService } from '../../src/database/prisma.service.js';
import { OrganizationMembershipPlanTestFixtures } from './organization-membership-plan-test-fixtures.js';
import { OrganizationTestFixtures } from './organization-test-fixtures.js';
import {
	loadTestDatabaseSafetyConfig,
	verifyTestDatabaseSafety,
	verifyTestTablePrivileges,
	type VerifiedTestDatabase,
} from './test-database-safety.js';

const safety = loadTestDatabaseSafetyConfig();
const requiredChecks = [
	'membership_plans_name_nonblank_check',
	'membership_plans_normalized_name_nonblank_check',
	'membership_plans_price_rwf_range_check',
	'membership_plans_description_nonblank_check',
	'membership_plans_updated_at_order_check',
	'membership_plans_archived_at_order_check',
];

jest.setTimeout(180_000);

describe('organization membership plans', () => {
	let module: TestingModule | undefined;
	let prisma: PrismaService;
	let verified: VerifiedTestDatabase | undefined;
	let organizations: OrganizationTestFixtures;
	let plans: OrganizationMembershipPlanTestFixtures;

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
		const [table, checks] = await Promise.all([
			prisma.$queryRaw<{ name: string | null }[]>`
				SELECT to_regclass('public.organization_membership_plans')::text AS name
			`,
			prisma.$queryRaw<{ name: string }[]>`
				SELECT conname AS name
				FROM pg_catalog.pg_constraint
				WHERE conrelid = to_regclass('public.organization_membership_plans')
					AND contype = 'c'
					AND convalidated
			`,
		]);
		if (
			table[0]?.name === null ||
			requiredChecks.some((name) => !checks.some((check) => check.name === name))
		) {
			throw new Error(
				'Organization membership plan prerequisites are missing: apply the reviewed migration ' +
					'and its validated SQL checks to the verified test database.',
			);
		}
		await verifyTestTablePrivileges(prisma, [
			{
				tableName: 'organization_membership_plans',
				privileges: ['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
			},
		]);
		verified = safe;
	});

	beforeEach(() => {
		organizations = new OrganizationTestFixtures();
		plans = new OrganizationMembershipPlanTestFixtures();
	});

	afterEach(async () => {
		if (verified === undefined) return;
		await plans.cleanup(prisma, verified);
		await organizations.cleanup(prisma, verified);
	});

	afterAll(async () => {
		await module?.close();
	});

	function requireVerified(): VerifiedTestDatabase {
		if (verified === undefined) throw new Error('Membership plan test database is not verified.');
		return verified;
	}

	async function createOrganization(name: string): Promise<string> {
		const fixture = organizations.reserve(requireVerified());
		await prisma.organization.create({ data: { ...fixture, name } });
		return fixture.id;
	}

	async function createPlan(
		organizationId: string,
		name: string,
		normalizedName: string,
		priceRwf = 30_000n,
	): Promise<string> {
		const id = plans.reserveId(requireVerified());
		await prisma.organizationMembershipPlan.create({
			data: { id, organizationId, name, normalizedName, priceRwf },
		});
		return id;
	}

	it('creates a tenant-owned plan with only name and price required', async () => {
		const organizationId = await createOrganization('Kigali Strength Gym');
		const id = await createPlan(organizationId, 'Monthly Access', 'monthly access');
		const plan = await prisma.organizationMembershipPlan.findUniqueOrThrow({ where: { id } });

		expect(plan).toMatchObject({
			id,
			organizationId,
			name: 'Monthly Access',
			normalizedName: 'monthly access',
			priceRwf: 30_000n,
			description: null,
			archivedAt: null,
		});
	});

	it('isolates names and reads by organization', async () => {
		const kigali = await createOrganization('Kigali Strength Gym');
		const musanze = await createOrganization('Musanze Fitness Club');
		await createPlan(kigali, 'Monthly Access', 'monthly access');
		await createPlan(musanze, 'Monthly Access', 'monthly access');

		expect(
			await prisma.organizationMembershipPlan.count({ where: { organizationId: kigali } }),
		).toBe(1);
		expect(
			await prisma.organizationMembershipPlan.count({ where: { organizationId: musanze } }),
		).toBe(1);
	});

	it('rejects duplicate normalized names within one organization', async () => {
		const organizationId = await createOrganization('Kigali Strength Gym');
		await createPlan(organizationId, 'Monthly Access', 'monthly access');
		const duplicateId = plans.reserveId(requireVerified());

		await expect(
			prisma.organizationMembershipPlan.create({
				data: {
					id: duplicateId,
					organizationId,
					name: 'MONTHLY ACCESS',
					normalizedName: 'monthly access',
					priceRwf: 40_000n,
				},
			}),
		).rejects.toMatchObject({ code: 'P2002' });
	});

	it.each([
		{ name: ' ', normalizedName: 'monthly access', priceRwf: 30_000n, description: null },
		{ name: 'Monthly Access', normalizedName: ' ', priceRwf: 30_000n, description: null },
		{ name: 'Monthly Access', normalizedName: 'monthly access', priceRwf: -1n, description: null },
		{
			name: 'Monthly Access',
			normalizedName: 'monthly access',
			priceRwf: 1_000_000_001n,
			description: null,
		},
		{
			name: 'Monthly Access',
			normalizedName: 'monthly access',
			priceRwf: 30_000n,
			description: ' ',
		},
	])('enforces plan integrity in PostgreSQL: %#', async (invalidPlan) => {
		const organizationId = await createOrganization('Kigali Strength Gym');
		const id = plans.reserveId(requireVerified());
		await expect(
			prisma.organizationMembershipPlan.create({
				data: { id, organizationId, ...invalidPlan },
			}),
		).rejects.toMatchObject({ code: 'P2004' });
	});

	it('restricts organization deletion while plans exist', async () => {
		const organizationId = await createOrganization('Kigali Strength Gym');
		await createPlan(organizationId, 'Monthly Access', 'monthly access');

		await expect(
			prisma.organization.delete({ where: { id: organizationId } }),
		).rejects.toMatchObject({
			code: 'P2003',
		});
	});
});
