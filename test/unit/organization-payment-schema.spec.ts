import { readFile } from 'node:fs/promises';

describe('organization payment storage contract', () => {
	async function paymentMigration(): Promise<string> {
		return readFile(
			new URL(
				'../../prisma/migrations/20261018140155_add_organization_payment_ledger/migration.sql',
				import.meta.url,
			),
			'utf8',
		);
	}

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

	it('hardens financial history, balances, lifecycle transitions and public access', async () => {
		const sql = await paymentMigration();

		for (const constraint of [
			'payments_amount_range_check',
			'payments_provider_reference_check',
			'payments_lifecycle_check',
			'payment_refunds_lifecycle_check',
			'payment_audit_action_check',
		]) {
			expect(sql).toContain(`CONSTRAINT ${constraint}`);
		}
		for (const guard of [
			'organization_payment_history_guard',
			'payment_allocation_history_guard',
			'payment_refund_history_guard',
			'payment_audit_history_guard',
			'payment_allocation_balance_payment_guard',
			'payment_refund_balance_payment_guard',
		]) {
			expect(sql).toContain(guard);
		}
		expect(sql).toContain('DEFERRABLE INITIALLY DEFERRED');
		expect(sql).toContain('REVOKE ALL ON TABLE public.organization_payments FROM PUBLIC');
		expect(sql).not.toMatch(/DROP TABLE|DROP COLUMN|ON DELETE CASCADE/u);
	});
});
