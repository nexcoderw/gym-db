import { readFile } from 'node:fs/promises';

describe('organization membership plan schema contract', () => {
	async function schema(): Promise<string> {
		return readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
	}

	async function migration(): Promise<string> {
		return readFile(
			new URL(
				'../../prisma/migrations/20261018090138_add_organization_membership_plans/migration.sql',
				import.meta.url,
			),
			'utf8',
		);
	}

	it('defines tenant-owned plans with nullable descriptions and integer RWF prices', async () => {
		const source = await schema();
		const plan = /model OrganizationMembershipPlan \{[\s\S]*?\n\}/u.exec(source)?.[0];

		expect(plan).toMatch(/organizationId\s+String[^\n]+@db\.Uuid/u);
		expect(plan).toMatch(/name\s+String\s+@db\.VarChar\(120\)/u);
		expect(plan).toMatch(/normalizedName\s+String[^\n]+@db\.VarChar\(120\)/u);
		expect(plan).toMatch(/priceRwf\s+BigInt/u);
		expect(plan).toMatch(/description\s+String\?\s+@db\.VarChar\(1000\)/u);
		expect(plan).toContain(
			'@@unique([organizationId, normalizedName], map: "organization_membership_plans_org_name_key")',
		);
		expect(plan).toContain('onDelete: Restrict');
		expect(plan).not.toMatch(/Float|Decimal|currency|onDelete: Cascade/u);
	});

	it('enforces API invariants and tenant indexes in the reviewed SQL migration', async () => {
		const sql = await migration();

		for (const constraint of [
			'membership_plans_name_nonblank_check',
			'membership_plans_normalized_name_nonblank_check',
			'membership_plans_price_rwf_range_check',
			'membership_plans_description_nonblank_check',
			'membership_plans_updated_at_order_check',
			'membership_plans_archived_at_order_check',
		]) {
			expect(sql).toContain(`CONSTRAINT "${constraint}"`);
		}
		expect(sql).toContain('CHECK ("price_rwf" BETWEEN 0 AND 1000000000)');
		expect(sql).toContain('organization_membership_plans_org_name_key');
		expect(sql).toContain('organization_membership_plans_org_archive_created_id_idx');
		expect(sql).toContain('ON DELETE RESTRICT ON UPDATE RESTRICT');
		expect(sql).not.toMatch(/DROP TABLE|DROP COLUMN|CASCADE/u);
	});
});
