import { readFile } from 'node:fs/promises';

const migrationUrl = new URL(
	'../../prisma/migrations/20261016163359_repair_owner_invitation_delivery_integrity/migration.sql',
	import.meta.url,
);

describe('owner invitation delivery integrity repair migration', () => {
	async function migration(): Promise<string> {
		return readFile(migrationUrl, 'utf8');
	}

	it('adds all reviewed delivery integrity categories in one transaction', async () => {
		const source = await migration();
		expect(source).toContain('BEGIN;');
		expect(source).toContain("SET LOCAL lock_timeout = '10s';");
		expect(source).toContain("SET LOCAL statement_timeout = '60s';");
		expect(source.trimEnd()).toMatch(/COMMIT;$/u);

		for (const constraint of [
			'organization_owner_invitation_deliveries_lifecycle_check',
			'organization_owner_invitation_deliveries_lease_check',
			'organization_owner_invitation_deliveries_retry_check',
			'organization_owner_invitation_deliveries_token_material_check',
			'organization_owner_invitation_deliveries_timestamp_order_check',
			'organization_owner_invitation_deliveries_bounded_text_check',
		]) {
			expect(source).toContain(`ADD CONSTRAINT ${constraint} CHECK`);
		}
		expect(source).toContain('octet_length(token_ciphertext) BETWEEN 32 AND 4096');
		expect(source).toContain('octet_length(token_initialization_vector) = 12');
		expect(source).toContain('octet_length(token_authentication_tag) = 16');
		expect(source).toContain('token_digest COLLATE "C" ~ \'^[0-9a-f]{64}$\'');
	});

	it('guards immutable identity, bounded transitions and terminal outcomes', async () => {
		const source = await migration();
		expect(source).toContain('CREATE FUNCTION public.guard_owner_invitation_delivery()');
		expect(source).toContain('SECURITY INVOKER');
		expect(source).toContain('SET search_path = pg_catalog, public');
		expect(source).toContain('CREATE TRIGGER owner_invitation_delivery_guard');
		expect(source).toContain('BEFORE INSERT OR UPDATE');

		for (const identity of [
			'NEW.organization_id IS DISTINCT FROM OLD.organization_id',
			'NEW.owner_invitation_id IS DISTINCT FROM OLD.owner_invitation_id',
			'NEW.requested_by_platform_staff_id IS DISTINCT FROM OLD.requested_by_platform_staff_id',
			'NEW.provider_idempotency_key IS DISTINCT FROM OLD.provider_idempotency_key',
			'NEW.token_expires_at IS DISTINCT FROM OLD.token_expires_at',
		]) {
			expect(source).toContain(identity);
		}

		expect(source).toContain("OLD.status = 'confirmed'");
		expect(source).toContain("OLD.status = 'failed' AND OLD.next_attempt_at IS NULL");
		expect(source).toContain(
			"OLD.status = 'uncertain' AND NEW.status = 'failed'\n        AND NEW.next_attempt_at IS NULL AND erasing",
		);
		expect(source).not.toContain(
			"OLD.status = 'uncertain' AND NEW.status IN ('confirmed', 'failed')",
		);
	});

	it('protects invitation lifecycle, queue audit metadata and public access', async () => {
		const source = await migration();
		expect(source).toContain(
			'CREATE OR REPLACE FUNCTION public.guard_organization_owner_invitation_identity()',
		);
		expect(source).toContain("OLD.status IN ('revoked', 'accepted')");
		expect(source).toContain("OLD.status = 'pending_delivery' AND NEW.status = 'accepted'");
		expect(source).toContain("WHEN 'invitation_delivery_queued'");
		expect(source).toContain("resulting_invitation_status = 'pending_delivery'");
		expect(source).toContain('REVOKE ALL ON TABLE');
		expect(source).toContain(
			'REVOKE ALL ON TYPE public.organization_owner_invitation_delivery_status FROM PUBLIC;',
		);
		expect(source).toContain('public.guard_owner_invitation_delivery()');
		expect(source).not.toMatch(/\bGRANT\b/u);
	});
});
