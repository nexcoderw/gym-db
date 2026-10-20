import { readFile } from 'node:fs/promises';

describe('organization member reminder storage contract', () => {
	it('reserves one delivery per tenant, subscription, occasion and channel', async () => {
		const source = await readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
		const delivery = /model OrganizationMemberReminderDelivery \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const member = /model OrganizationMember \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const kinds = /enum OrganizationMemberReminderKind \{[\s\S]*?\n\}/u.exec(source)?.[0];

		expect(delivery).toContain('@@unique([organizationId, memberSubscriptionId, kind, channel]');
		expect(delivery).toContain('fields: [organizationId, memberId]');
		expect(delivery).toContain('fields: [organizationId, memberSubscriptionId, memberId]');
		expect(delivery).toContain('providerIdempotencyKey');
		expect(delivery).toContain('messageSubject');
		expect(delivery).toContain('messageBody');
		expect(delivery).not.toContain('onDelete: Cascade');
		expect(member).toContain('reminderEmailOptedOutAt');
		expect(member).toContain('reminderEmailSuppressedAt');
		expect(member).toContain('reminderEmailSuppressionReason');
		expect(kinds).toContain('MANUAL            @map("manual")');
	});
});
