import { readFile } from 'node:fs/promises';

describe('organization member storage contract', () => {
	it('separates profiles and plan history with tenant-bound foreign keys', async () => {
		const source = await readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
		const member = /model OrganizationMember \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const subscription = /model OrganizationMemberSubscription \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const smsSuppression = /enum OrganizationMemberSmsSuppressionReason \{[\s\S]*?\n\}/u.exec(
			source,
		)?.[0];

		expect(member).toContain('@@unique([organizationId, normalizedName]');
		expect(member).toContain('@@unique([organizationId, phoneNumber]');
		expect(member).toMatch(/email\s+String\?\s+@db.Citext/u);
		expect(member).toMatch(/joinedOn\s+DateTime\?[^\n]+@map\("joined_on"\)\s+@db.Date/u);
		expect(member).toMatch(/gender\s+OrganizationMemberGender\?/u);
		expect(member).toMatch(/createdAt\s+DateTime[^\n]+@default\(now\(\)\)/u);
		expect(member).toContain('@updatedAt @map("updated_at") @db.Timestamptz(6)');
		expect(member).not.toMatch(/\[organizationId, email\]/u);
		expect(subscription).toContain('fields: [organizationId, memberId]');
		expect(subscription).toContain('fields: [organizationId, membershipPlanId]');
		expect(subscription).toContain('@@unique([organizationId, idempotencyKey]');
		expect(subscription).toMatch(/priceRwf\s+BigInt/u);
		expect(subscription).toMatch(/startDate\s+DateTime[^\n]+@db.Date/u);
		expect(subscription).toMatch(/endDate\s+DateTime[^\n]+@db.Date/u);
		expect(subscription).not.toContain('onDelete: Cascade');
		expect(member).toMatch(
			/isSynthetic\s+Boolean\s+@default\(false\)\s+@map\("is_synthetic"\)/u,
		);
		expect(member).toMatch(
			/syntheticBatchId\s+String\?[^\n]+@map\("synthetic_batch_id"\)\s+@db.VarChar\(120\)/u,
		);
		expect(member).toMatch(
			/reminderSmsSuppressedAt\s+DateTime\?[^\n]+@map\("reminder_sms_suppressed_at"\)\s+@db.Timestamptz\(6\)/u,
		);
		expect(member).toMatch(
			/reminderSmsSuppressionReason\s+OrganizationMemberSmsSuppressionReason\?/u,
		);
		expect(member).toContain('@@index([organizationId, isSynthetic, syntheticBatchId, id]');
		expect(smsSuppression).toContain('MANUAL @map("manual")');
	});
});
