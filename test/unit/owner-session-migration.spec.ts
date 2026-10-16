import { readFile } from 'node:fs/promises';

const migrationUrl = new URL(
	'../../prisma/migrations/20261016205745_add_owner_sessions/migration.sql',
	import.meta.url,
);

describe('owner session migration', () => {
	async function migration(): Promise<string> {
		return readFile(migrationUrl, 'utf8');
	}

	it('creates the separate global-user session boundary transactionally', async () => {
		const source = await migration();

		expect(source).toContain('BEGIN;');
		expect(source).toContain("SET LOCAL lock_timeout = '10s';");
		expect(source).toContain("SET LOCAL statement_timeout = '60s';");
		expect(source).toContain('CREATE TABLE "owner_sessions"');
		expect(source).toContain('REFERENCES "users"("id") ON DELETE RESTRICT');
		expect(source).not.toContain('platform_staff_id');
		expect(source).not.toContain('organization_id');
		expect(source.trimEnd()).toMatch(/COMMIT;$/u);
	});

	it('enforces digest, assurance and bounded expiry constraints', async () => {
		const source = await migration();

		for (const constraint of [
			'owner_sessions_token_digest_check',
			'owner_sessions_assurance_check',
			'owner_sessions_timestamp_order_check',
		]) {
			expect(source).toContain(`CONSTRAINT "${constraint}"`);
		}

		expect(source).toContain('token_digest COLLATE "C" ~ \'^[0-9a-f]{64}$\'');
		expect(source).toContain("absolute_expires_at <= created_at + interval '30 days'");
		expect(source).toContain("idle_expires_at <= last_activity_at + interval '24 hours'");
		expect(source).toContain("WHEN 'aal2' THEN mfa_verified_at IS NOT NULL");
	});

	it('protects creation, refresh and one-way revocation', async () => {
		const source = await migration();

		expect(source).toContain('CREATE FUNCTION public.guard_owner_session()');
		expect(source).toContain('SECURITY INVOKER');
		expect(source).toContain('SET search_path = pg_catalog, public');
		expect(source).toContain('CREATE TRIGGER owner_session_guard');
		expect(source).toContain("current_user_status <> 'active'");
		expect(source).toContain('revoked owner sessions are immutable');
		expect(source).toContain('owner session revocation cannot refresh activity');
		expect(source).toContain('owner session activity and idle expiry must advance together');
	});

	it('removes public access without embedding environment roles', async () => {
		const source = await migration();

		expect(source).toContain('REVOKE ALL ON TABLE public.owner_sessions FROM PUBLIC;');
		expect(source).toContain('REVOKE ALL ON TYPE public.owner_session_assurance FROM PUBLIC;');
		expect(source).toContain('REVOKE ALL ON FUNCTION public.guard_owner_session() FROM PUBLIC;');
		expect(source).not.toMatch(/\bGRANT\b/u);
	});
});
