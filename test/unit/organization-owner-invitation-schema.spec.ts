import { readFile } from 'node:fs/promises';

describe('organization owner invitation schema contract', () => {
	async function schema(): Promise<string> {
		return readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
	}

	it('models a pending-delivery invitation without granting identity or authorization', async () => {
		const source = await schema();
		const status = /enum OrganizationOwnerInvitationStatus \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const invitation = /model OrganizationOwnerInvitation \{[\s\S]*?\n\}/u.exec(source)?.[0];

		expect(status).toBeDefined();
		for (const value of ['pending_delivery', 'sent', 'accepted', 'revoked']) {
			expect(status).toContain(`@map("${value}")`);
		}
		expect(status).toContain('@@map("organization_owner_invitation_status")');
		expect(invitation).toMatch(
			/id\s+String\s+@id\(map: "organization_owner_invitations_pkey"\)[^\n]+@db\.Uuid/u,
		);
		expect(invitation).toMatch(/invitedEmail\s+String[^\n]+@db\.Citext/u);
		expect(invitation).toMatch(/invitedDisplayName\s+String[^\n]+@db\.VarChar\(160\)/u);
		expect(invitation).toMatch(
			/status\s+OrganizationOwnerInvitationStatus\s+@default\(PENDING_DELIVERY\)/u,
		);
		expect(invitation).toMatch(/tokenDigest\s+String\?[^\n]+@db\.VarChar\(128\)/u);
		for (const field of [
			'expiresAt',
			'sentAt',
			'acceptedAt',
			'revokedAt',
			'createdAt',
			'updatedAt',
		]) {
			expect(invitation).toMatch(
				new RegExp(`${field}\\s+DateTime\\??[^\\n]+@db\\.Timestamptz\\(6\\)`, 'u'),
			);
		}
		expect(invitation).not.toMatch(/userId|membershipId|organizationRoleId|password|session/iu);
	});

	it('uses restrictive organization and actor relationships with tenant-leading indexes', async () => {
		const invitation = /model OrganizationOwnerInvitation \{[\s\S]*?\n\}/u.exec(
			await schema(),
		)?.[0];

		expect(invitation).toMatch(
			/organization\s+Organization[^\n]+onDelete: Restrict,[^\n]+onUpdate: Restrict/u,
		);
		expect(invitation).toMatch(
			/invitedByPlatformStaff\s+PlatformStaff[^\n]+onDelete: Restrict,[^\n]+onUpdate: Restrict/u,
		);
		expect(invitation).toContain(
			'@@unique([organizationId, id], map: "organization_owner_invitations_organization_id_key")',
		);
		expect(invitation).toContain('@@index([organizationId, status, createdAt(sort: Desc), id]');
		expect(invitation).toContain(
			'@@index([organizationId, invitedEmail, createdAt(sort: Desc), id]',
		);
		expect(invitation).not.toMatch(/onDelete: Cascade|onUpdate: Cascade/u);
	});

	it('defines a dedicated organization-scoped append-only audit contract', async () => {
		const source = await schema();
		const action = /enum OrganizationOwnershipAuditAction \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const audit = /model OrganizationOwnershipAuditEvent \{[\s\S]*?\n\}/u.exec(source)?.[0];

		expect(action).toContain('@map("invitation_created")');
		expect(action).toContain('@map("invitation_revoked")');
		expect(action).not.toMatch(/owner_accepted|owner_assigned|owner_transferred/iu);
		expect(audit).toMatch(/organizationId\s+String[^\n]+@db\.Uuid/u);
		expect(audit).toMatch(/ownerInvitationId\s+String[^\n]+@db\.Uuid/u);
		expect(audit).toMatch(/actorPlatformStaffId\s+String[^\n]+@db\.Uuid/u);
		expect(audit).toMatch(/requestId\s+String[^\n]+@db\.VarChar\(128\)/u);
		expect(audit).toMatch(
			/@relation\(fields: \[organizationId, ownerInvitationId\],[^\n]+references: \[organizationId, id\],[^\n]+onDelete: Restrict,[^\n]+onUpdate: Restrict/u,
		);
		expect(audit).toContain(
			'@@index([organizationId, ownerInvitationId, recordedAt(sort: Desc), id]',
		);
		expect(audit).toContain(
			'@@index([organizationId, action, recordedAt(sort: Desc), id]',
		);
		expect(audit).not.toMatch(/token|email|credential|rawRequest|metadata\s+Json/iu);
	});

	it('adds only invitation and audit collections to existing roots', async () => {
		const source = await schema();
		const organization = /model Organization \{[\s\S]*?\n\}/u.exec(source)?.[0];
		const staff = /model PlatformStaff \{[\s\S]*?\n\}/u.exec(source)?.[0];

		expect(organization).toMatch(/ownerInvitations\s+OrganizationOwnerInvitation\[\]/u);
		expect(organization).toMatch(
			/ownershipAuditEvents\s+OrganizationOwnershipAuditEvent\[\]/u,
		);
		expect(staff).toMatch(/ownerInvitationsCreated\s+OrganizationOwnerInvitation\[\]/u);
		expect(staff).toMatch(/ownershipAuditEvents\s+OrganizationOwnershipAuditEvent\[\]/u);
	});
});
