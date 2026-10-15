import { readFile } from 'node:fs/promises';

describe('durable platform audit schema', () => {
	it('repairs the complete audit contract without rewriting applied history', async () => {
		const migration = await readFile(
			new URL(
				'../../prisma/migrations/20261015113000_repair_platform_audit_contract/migration.sql',
				import.meta.url,
			),
			'utf8',
		);

		for (const contract of [
			'platform_authorization_audit_events_approval_check',
			'platform_authorization_audit_events_permissions_check',
			'organization_audit_stamp',
			'platform_authorization_audit_stamp',
		]) {
			expect(migration).toContain(contract);
		}
		expect(migration).toContain('CREATE OR REPLACE FUNCTION public.stamp_organization_audit()');
		expect(migration).toContain(
			'CREATE OR REPLACE FUNCTION public.stamp_platform_authorization_audit()',
		);
		expect(migration).toMatch(/REVOKE ALL ON FUNCTION[\s\S]+FROM PUBLIC;/u);
		expect(migration).toMatch(/REVOKE ALL ON TABLE[\s\S]+FROM PUBLIC;/u);
		expect(migration).not.toMatch(/DROP (TABLE|TYPE)|TRUNCATE/u);
	});

	it.each(['OrganizationAuditEvent', 'PlatformAuthorizationAuditEvent'])(
		'keeps %s focused, bounded and restrictive',
		async (name) => {
			const schema = await readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
			const model = new RegExp(`model ${name} \\{[\\s\\S]*?\\n\\}`, 'u').exec(schema)?.[0];
			expect(model).toBeDefined();
			expect(model).toMatch(/id\s+String\s+@id[^\n]+@db\.Uuid/u);
			expect(model).toMatch(/recordedAt\s+DateTime\s+@default\(now\(\)\)/u);
			expect(model).not.toMatch(/Json|Bytes|@updatedAt|onDelete: Cascade/u);
			expect(model).not.toMatch(/password|tokenDigest|encryptedSecret|cookie/iu);
			expect(model).toMatch(/onDelete: Restrict, onUpdate: Restrict/u);
			expect(model).toContain('recordedAt(sort: Desc)');
		},
	);

	it('derives operator identities from PostgreSQL rather than a platform actor claim', async () => {
		const schema = await readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
		const model = /model PlatformAuthorizationAuditEvent \{[\s\S]*?\n\}/u.exec(schema)?.[0];
		expect(model).toContain('@default(dbgenerated("SESSION_USER"))');
		expect(model).toContain('@default(dbgenerated("CURRENT_USER"))');
		expect(model).toContain('@default(dbgenerated("CURRENT_DATABASE()"))');
		expect(model).toMatch(/approvalReference\s+String[^\n]+@db\.VarChar\(120\)/u);
		expect(model).toMatch(/approvedPermissionKeys\s+String\[\][^\n]+@db\.VarChar\(80\)/u);
	});
});
