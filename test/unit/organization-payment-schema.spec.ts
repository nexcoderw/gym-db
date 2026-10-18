import { readFile } from 'node:fs/promises';

describe('organization payment storage contract', () => {
	it('keeps tenant-owned payment evidence separate from registrations', async () => {
		const source = await readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
		const payment = /model OrganizationPayment \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const allocation = /model OrganizationPaymentAllocation \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const refund = /model OrganizationPaymentRefund \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const audit = /model OrganizationPaymentAuditEvent \{[\s\S]*?\n\}/u.exec(source)?.[0];

		expect(payment).toMatch(/amountRwf\s+BigInt/u);
		expect(payment).toContain('@@unique([organizationId, idempotencyKey]');
		expect(payment).toContain('fields: [organizationId, memberId]');
		expect(payment).not.toContain('onDelete: Cascade');

		expect(allocation).toContain('fields: [organizationId, paymentId, memberId]');
		expect(allocation).toContain('fields: [organizationId, memberSubscriptionId, memberId]');
		expect(allocation).toMatch(/amountRwf\s+BigInt/u);

		expect(refund).toContain('@@unique([organizationId, idempotencyKey]');
		expect(refund).toMatch(/requestFingerprint\s+String[^\n]+VarChar\(64\)/u);
		expect(audit).toContain('@@unique([organizationId, idempotencyKey]');
		expect(audit).toMatch(/requestId\s+String[^\n]+VarChar\(128\)/u);
	});

	it('models verified and unverified payment states explicitly', async () => {
		const source = await readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');

		for (const value of ['PENDING', 'CONFIRMED', 'FAILED', 'VOIDED', 'PARTIALLY_REFUNDED', 'REFUNDED']) {
			expect(source).toMatch(new RegExp(`enum OrganizationPaymentStatus \\{[\\s\\S]*?${value}`, 'u'));
		}
		for (const method of ['CASH', 'MOBILE_MONEY', 'BANK_TRANSFER', 'CARD', 'OTHER']) {
			expect(source).toMatch(new RegExp(`enum OrganizationPaymentMethod \\{[\\s\\S]*?${method}`, 'u'));
		}
	});
});
