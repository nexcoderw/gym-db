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
});
