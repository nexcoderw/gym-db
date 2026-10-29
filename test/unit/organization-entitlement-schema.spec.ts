import { readFile } from 'node:fs/promises';

describe('organization feature entitlement storage contract', () => {
	it('stores one versioned capability state per organization', async () => {
		const schema = await readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
		const entitlement = /model OrganizationFeatureEntitlement \{[\s\S]*?\n\}/u.exec(
			schema,
		)?.[0];

		expect(entitlement).toBeDefined();
		expect(entitlement).toMatch(/featureKey\s+String[^\n]+VarChar\(80\)/u);
		expect(entitlement).toMatch(/enabled\s+Boolean\s+@default\(false\)/u);
		expect(entitlement).toMatch(/version\s+Int\s+@default\(1\)/u);
		expect(entitlement).toContain('@@id([organizationId, featureKey]');
		expect(entitlement).toContain('organizationId, enabled, startsAt, expiresAt');
		expect(entitlement).toContain('onDelete: Restrict, onUpdate: Restrict');
		expect(entitlement).not.toMatch(/Json|Bytes|onDelete: Cascade/u);
	});

	it('records bounded append-only entitlement evidence', async () => {
		const schema = await readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
		const audit = /model OrganizationFeatureEntitlementAuditEvent \{[\s\S]*?\n\}/u.exec(
			schema,
		)?.[0];

		expect(audit).toBeDefined();
		expect(audit).toMatch(/reason\s+String[^\n]+VarChar\(500\)/u);
		expect(audit).toMatch(/requestId\s+String\?[^\n]+VarChar\(128\)/u);
		expect(audit).toContain('@@unique([organizationId, featureKey, resultingVersion]');
		expect(audit).toContain('fields: [organizationId, featureKey]');
		expect(audit).toContain('onDelete: Restrict, onUpdate: Restrict');
		expect(audit).not.toMatch(/@updatedAt|Json|Bytes|onDelete: Cascade/u);
	});

	it('distinguishes migration, provisioning and platform-admin changes', async () => {
		const schema = await readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
		const source = /enum OrganizationFeatureEntitlementChangeSource \{[\s\S]*?\n\}/u.exec(
			schema,
		)?.[0];

		expect(source).toContain('INITIAL_MIGRATION');
		expect(source).toContain('ORGANIZATION_PROVISIONING');
		expect(source).toContain('PLATFORM_ADMIN');
	});
});
