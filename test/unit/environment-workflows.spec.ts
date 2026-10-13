import { readFile } from 'node:fs/promises';
import { parseEnv } from 'node:util';

async function readRootFile(name: string): Promise<string> {
	return await readFile(new URL(`../../${name}`, import.meta.url), 'utf8');
}

describe('database workflow environment boundaries', () => {
	it('keeps CLI and test credentials out of the runtime template', async () => {
		const runtime = parseEnv(await readRootFile('.env.local.example'));
		expect(Object.keys(runtime)).toEqual(['DATABASE_URL']);
	});

	it('separates migration credentials from restricted test connections', async () => {
		const migrations = parseEnv(await readRootFile('.env.migrations.local.example'));
		const tests = parseEnv(await readRootFile('.env.test.local.example'));
		expect(migrations.TEST_MIGRATION_DATABASE_URL).toBeDefined();
		expect(migrations.TEST_DATABASE_URL).toBeUndefined();
		expect(tests.TEST_MIGRATION_DATABASE_URL).toBeUndefined();
		expect(tests.DATABASE_URL).toBeUndefined();
		expect(tests.NODE_ENV).toBe('test');
		expect(tests.TEST_DATABASE_MARKER).toBeDefined();
		for (const name of ['DIRECT_DATABASE_URL', 'SHADOW_DATABASE_URL']) {
			const value = tests[name];
			if (value === undefined) throw new Error('A reference-only test target is missing.');
			expect(new URL(value).password).toBe('');
		}
	});

	it('loads dedicated files without sourcing shell syntax or loading DDL credentials in tests', async () => {
		const manifest: unknown = JSON.parse(await readRootFile('package.json'));
		expect(manifest).toMatchObject({
			scripts: {
				'migration:test:deploy': 'prisma migrate deploy --config prisma.test.config.ts',
				'test:integration':
					'node --env-file=.env.local --env-file=.env.test.local --experimental-vm-modules ./node_modules/jest/bin/jest.js --config jest.config.cjs --selectProjects integration --runInBand',
			},
		});
		const config = await readRootFile('prisma.test.config.ts');
		expect(config).toContain("env('TEST_MIGRATION_DATABASE_URL')");
		expect(config).not.toContain('shadowDatabaseUrl');
		expect(await readRootFile('prisma.config.ts')).toContain("path: '.env.migrations.local'");
	});
});
