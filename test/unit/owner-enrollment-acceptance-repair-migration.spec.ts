import { readFile } from 'node:fs/promises';

const migrationUrl = new URL(
	'../../prisma/migrations/20261016164449_repair_owner_enrollment_acceptance_integrity/migration.sql',
	import.meta.url,
);

describe('owner enrollment and acceptance integrity repair migration', () => {
	async function migration(): Promise<string> {
		return readFile(migrationUrl, 'utf8');
	}

	it('adds every reviewed proof and audit constraint in one transaction', async () => {
		const source = await migration();
		expect(source).toContain('BEGIN;');
		expect(source).toContain("SET LOCAL lock_timeout = '10s';");
		expect(source).toContain("SET LOCAL statement_timeout = '60s';");
		expect(source.trimEnd()).toMatch(/COMMIT;$/u);

		for (const constraint of [
			'owner_enrollment_challenges_lifecycle_check',
			'owner_enrollment_challenges_attempts_check',
			'owner_enrollment_challenges_timestamps_check',
			'owner_enrollment_challenges_digest_check',
			'owner_acceptance_audit_events_request_check',
		]) {
			expect(source).toContain(`ADD CONSTRAINT ${constraint}`);
		}

		expect(source).toContain("expires_at <= created_at + interval '15 minutes'");
		expect(source).toContain("request_id COLLATE \"C\" ~ '^[A-Za-z0-9._:-]{1,128}$'");
	});

	it('enforces proof identity, monotonic attempts and one-way terminal states', async () => {
		const source = await migration();
		expect(source).toContain('CREATE OR REPLACE FUNCTION public.guard_owner_enrollment_challenge()');
		expect(source).toContain('SECURITY INVOKER');
		expect(source).toContain('SET search_path = pg_catalog, public');
		expect(source).toContain('CREATE TRIGGER owner_enrollment_challenge_guard');
		expect(source).toContain("OLD.status IN ('consumed', 'revoked')");
		expect(source).toContain('NEW.failed_attempts < OLD.failed_attempts');
		expect(source).toContain('NEW.token_digest IS DISTINCT FROM OLD.token_digest');
		expect(source).toContain("NEW.status IN ('verified', 'consumed')");
		expect(source).toContain("invitation_record.status <> 'sent'");
		expect(source).toContain("user_record.status <> 'active'");
		expect(source).toContain('NEW.step_up_verified_at IS NULL');
	});

	it('binds acceptance audit rows to consumed proof and exact owner authorization', async () => {
		const source = await migration();
		expect(source).toContain('CREATE OR REPLACE FUNCTION public.guard_owner_acceptance_audit()');
		expect(source).toContain('CREATE OR REPLACE FUNCTION public.stamp_owner_acceptance_audit()');
		expect(source).toContain('CREATE TRIGGER owner_acceptance_audit_guard');
		expect(source).toContain('CREATE TRIGGER owner_acceptance_audit_stamp');
		expect(source).toContain("challenge_record.status <> 'consumed'");
		expect(source).toContain("invitation_record.status <> 'accepted'");
		expect(source).toContain("role.key = 'owner'");
		expect(source).toContain("role.name = 'Owner'");
		expect(source).toContain('role.is_system IS TRUE');
	});

	it('removes public access without embedding environment role grants', async () => {
		const source = await migration();
		expect(source).toContain(
			'REVOKE ALL ON TABLE public.organization_owner_enrollment_challenges FROM PUBLIC;',
		);
		expect(source).toContain(
			'REVOKE ALL ON TABLE public.organization_owner_acceptance_audit_events FROM PUBLIC;',
		);
		expect(source).toContain(
			'REVOKE ALL ON TYPE public.organization_owner_acceptance_audit_action FROM PUBLIC;',
		);
		expect(source).not.toMatch(/\bGRANT\b/u);
	});
});
