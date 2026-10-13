import { readFile } from 'node:fs/promises';

describe('organization schema contract', () => {
	it('defines a minimal independent root without identity or future-domain relationships', async () => {
		const schema = await readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
		const model = /model Organization \{[\s\S]*?\n\}/u.exec(schema)?.[0];
		expect(model).toBeDefined();
		expect(model).toMatch(/id\s+String\s+@id\(map: "organizations_pkey"\) @default\(uuid\(\)\) @db\.Uuid/u);
		expect(model).toMatch(/name\s+String\s+@db\.VarChar\(160\)/u);
		expect(model).toMatch(/slug\s+String\s+@unique\(map: "organizations_slug_key"\) @db\.VarChar\(63\)/u);
		expect(model).toMatch(/status\s+OrganizationStatus\s+@default\(PENDING\)/u);
		expect(model).toContain('@@map("organizations")');
		expect(model).toContain('@@index([status, createdAt(sort: Desc), id]');
		expect(model).not.toMatch(/organizationId|userId|platformStaffId|subscription|Json|@relation/u);
		expect(model).not.toMatch(/name[^\n]*@unique/u);
	});

	it('maps all lifecycle statuses and timestamps explicitly without implied authorization', async () => {
		const schema = await readFile(new URL('../../prisma/schema.prisma', import.meta.url), 'utf8');
		const status = /enum OrganizationStatus \{[\s\S]*?\n\}/u.exec(schema)?.[0];
		for (const value of ['pending', 'active', 'suspended', 'archived']) {
			expect(status).toContain(`@map("${value}")`);
		}
		expect(status).toContain('@@map("organization_status")');
		const model = /model Organization \{[\s\S]*?\n\}/u.exec(schema)?.[0];
		for (const field of ['activatedAt', 'suspendedAt', 'archivedAt']) {
			expect(model).toMatch(new RegExp(`${field}\\s+DateTime\\?[^\\n]+@db\\.Timestamptz\\(6\\)`, 'u'));
		}
		expect(model).toMatch(/createdAt\s+DateTime\s+@default\(now\(\)\)/u);
		expect(model).toMatch(/updatedAt\s+DateTime\s+@updatedAt/u);
	});
});
