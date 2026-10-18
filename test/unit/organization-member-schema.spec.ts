import { readFile } from 'node:fs/promises';

describe('organization member storage contract', () => {
	it('separates profiles and plan history with tenant-bound foreign keys', async () => {
		const source = await readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
		const member = /model OrganizationMember \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const subscription = /model OrganizationMemberSubscription \{[\s\S]*?\n\}/u.exec(source)?.[0];

		expect(member).toContain('@@unique([organizationId, normalizedName]');
		expect(member).toContain('@@unique([organizationId, phoneNumber]');
		expect(member).toMatch(/email\s+String\?\s+@db.Citext/u);
		expect(member).not.toMatch(/\[organizationId, email\]/u);
		expect(subscription).toContain('fields: [organizationId, memberId]');
		expect(subscription).toContain('fields: [organizationId, membershipPlanId]');
		expect(subscription).toContain('@@unique([organizationId, idempotencyKey]');
		expect(subscription).toMatch(/priceRwf\s+BigInt/u);
		expect(subscription).toMatch(/startDate\s+DateTime[^\n]+@db.Date/u);
		expect(subscription).toMatch(/endDate\s+DateTime[^\n]+@db.Date/u);
		expect(subscription).not.toContain('onDelete: Cascade');
	});
});
