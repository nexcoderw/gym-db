import { readFile } from 'node:fs/promises';

describe('organization owner invitation delivery schema contract', () => {
	async function schema(): Promise<string> {
		return readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
	}

	it('defines bounded delivery states independently from invitation ownership states', async () => {
		const source = await schema();
		const status = /enum OrganizationOwnerInvitationDeliveryStatus \{[\s\S]*?\n\}/u.exec(
			source,
		)?.[0];
		const delivery = /model OrganizationOwnerInvitationDelivery \{[\s\S]*?\n\}/u.exec(
			source,
		)?.[0];

		expect(status).toBeDefined();
		for (const value of ['queued', 'processing', 'confirmed', 'failed', 'uncertain']) {
			expect(status).toContain(`@map("${value}")`);
		}
		expect(status).toContain('@@map("organization_owner_invitation_delivery_status")');
		expect(delivery).toMatch(
			/status\s+OrganizationOwnerInvitationDeliveryStatus\s+@default\(QUEUED\)/u,
		);
		expect(delivery).not.toMatch(/membership|organizationRole|session|password|acceptedAt/iu);
	});

	it('persists a recoverable encrypted token envelope without plaintext token fields', async () => {
		const delivery = /model OrganizationOwnerInvitationDelivery \{[\s\S]*?\n\}/u.exec(
			await schema(),
		)?.[0];

		expect(delivery).toMatch(/tokenDigest\s+String\?\s+@unique[^\n]+@db\.VarChar\(128\)/u);
		for (const field of [
			'tokenCiphertext',
			'tokenInitializationVector',
			'tokenAuthenticationTag',
		]) {
			expect(delivery).toMatch(new RegExp(`${field}\\s+Bytes\\?`, 'u'));
		}
		expect(delivery).toMatch(/tokenEncryptionKeyId\s+String\?[^\n]+@db\.VarChar\(120\)/u);
		expect(delivery).toMatch(/tokenEncryptionVersion\s+Int\?/u);
		expect(delivery).toMatch(/tokenExpiresAt\s+DateTime[^\n]+@db\.Timestamptz\(6\)/u);
		expect(delivery).toMatch(/tokenErasedAt\s+DateTime\?[^\n]+@db\.Timestamptz\(6\)/u);
		expect(delivery).not.toMatch(/rawToken|plaintext|tokenValue|acceptanceUrl/iu);
	});

	it('supports bounded retries, exclusive leases and provider reconciliation', async () => {
		const delivery = /model OrganizationOwnerInvitationDelivery \{[\s\S]*?\n\}/u.exec(
			await schema(),
		)?.[0];

		expect(delivery).toMatch(/attemptCount\s+Int\s+@default\(0\)/u);
		expect(delivery).toMatch(/maxAttempts\s+Int\s+@default\(3\)/u);
		for (const field of [
			'nextAttemptAt',
			'leaseAcquiredAt',
			'leaseExpiresAt',
			'confirmedAt',
			'failedAt',
			'uncertainAt',
		]) {
			expect(delivery).toMatch(
				new RegExp(`${field}\\s+DateTime\\?[^\\n]+@db\\.Timestamptz\\(6\\)`, 'u'),
			);
		}
		expect(delivery).toMatch(/claimedBy\s+String\?[^\n]+@db\.VarChar\(120\)/u);
		expect(delivery).toMatch(
			/providerIdempotencyKey\s+String\s+@unique[^\n]+@db\.VarChar\(128\)/u,
		);
		expect(delivery).toMatch(
			/providerMessageId\s+String\?\s+@unique[^\n]+@db\.VarChar\(128\)/u,
		);
		expect(delivery).toMatch(/lastErrorCode\s+String\?[^\n]+@db\.VarChar\(63\)/u);
		expect(delivery).toContain(
			'@@index([status, nextAttemptAt, leaseExpiresAt, id], map: "organization_owner_invitation_deliveries_worker_claim_idx")',
		);
	});

	it('enforces one tenant-scoped delivery reservation per invitation', async () => {
		const source = await schema();
		const delivery = /model OrganizationOwnerInvitationDelivery \{[\s\S]*?\n\}/u.exec(
			source,
		)?.[0];
		const organization = /model Organization \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const invitation = /model OrganizationOwnerInvitation \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const staff = /model PlatformStaff \{[\s\S]*?\n\}/u.exec(source)?.[0];

		expect(delivery).toMatch(
			/@relation\(fields: \[organizationId, ownerInvitationId\],[^\n]+references: \[organizationId, id\],[^\n]+onDelete: Restrict,[^\n]+onUpdate: Restrict/u,
		);
		expect(delivery).toContain(
			'@@unique([organizationId, ownerInvitationId], map: "organization_owner_invitation_deliveries_organization_invitation_key")',
		);
		expect(delivery).toContain(
			'@@index([organizationId, status, nextAttemptAt, id], map: "organization_owner_invitation_deliveries_org_status_next_id_idx")',
		);
		expect(delivery).not.toMatch(/onDelete: Cascade|onUpdate: Cascade/u);
		expect(organization).toMatch(
			/ownerInvitationDeliveries\s+OrganizationOwnerInvitationDelivery\[\]/u,
		);
		expect(invitation).toMatch(/delivery\s+OrganizationOwnerInvitationDelivery\?/u);
		expect(staff).toMatch(
			/ownerInvitationDeliveriesRequested\s+OrganizationOwnerInvitationDelivery\[\]/u,
		);
	});

	it('adds an explicit administrator-authorized delivery audit action', async () => {
		const source = await schema();
		const action = /enum OrganizationOwnershipAuditAction \{[\s\S]*?\n\}/u.exec(source)?.[0];

		expect(action).toContain('INVITATION_DELIVERY_QUEUED @map("invitation_delivery_queued")');
		expect(action).not.toMatch(/delivery_confirmed|email_delivered|invitation_accepted/iu);
	});
});
