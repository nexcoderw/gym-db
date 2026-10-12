import { readFile } from 'node:fs/promises';

describe('Prisma schema contract', () => {
	it('keeps Prisma 7 connection configuration outside the canonical schema', async () => {
		const schemaUrl = new URL('../../prisma/schema.prisma', import.meta.url);
		const schema = await readFile(schemaUrl, 'utf8');

		expect(schema).toMatch(/provider\s*=\s*"prisma-client"/u);
		expect(schema).toMatch(/output\s*=\s*"\.\.\/src\/generated\/prisma"/u);
		expect(schema).toMatch(/provider\s*=\s*"postgresql"/u);
		expect(schema).not.toMatch(/^\s*url\s*=/mu);
	});

	it('defines global identity and explicit platform authorization models', async () => {
		const schemaUrl = new URL('../../prisma/schema.prisma', import.meta.url);
		const schema = await readFile(schemaUrl, 'utf8');

		for (const model of [
			'User',
			'PasswordCredential',
			'PlatformStaff',
			'PlatformRole',
			'PlatformPermission',
			'PlatformStaffRole',
			'PlatformRolePermission',
		]) {
			const modelBlock = schema.match(new RegExp(`model ${model} \\{[\\s\\S]*?\\n\\}`, 'u'))?.[0];
			expect(modelBlock).toBeDefined();
			expect(modelBlock).not.toContain('organizationId');
		}
		expect(schema).toMatch(/email\s+String\s+@unique\([^\n]+\)\s+@db\.Citext/u);
		expect(schema).not.toContain('isSuperAdmin');
	});

	it('uses restrictive foreign keys for security-sensitive relationships', async () => {
		const schemaUrl = new URL('../../prisma/schema.prisma', import.meta.url);
		const schema = await readFile(schemaUrl, 'utf8');
		const restrictiveRelations = schema.match(/onDelete:\s*Restrict,\s*onUpdate:\s*Restrict/gu);

		expect(restrictiveRelations?.length).toBeGreaterThanOrEqual(6);
	});
});
