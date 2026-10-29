import { readFile, readdir } from 'node:fs/promises';

describe('organization feature entitlement migration', () => {
	it('adds compatible tenant state, audit protection and the reviewed initial catalog', async () => {
		const migrationsUrl = new URL('../../prisma/migrations/', import.meta.url);
		const entries = await readdir(migrationsUrl, { withFileTypes: true });
		const directory = entries.find(
			(entry) =>
				entry.isDirectory() && entry.name.endsWith('_add_organization_feature_entitlements'),
		);

		if (directory === undefined) {
			throw new Error(
				'Generate and review the create-only add_organization_feature_entitlements migration.',
			);
		}

		const sql = await readFile(new URL(`${directory.name}/migration.sql`, migrationsUrl), 'utf8');

		for (const constraint of [
			'organization_feature_entitlements_feature_key_check',
			'organization_feature_entitlements_version_check',
			'organization_feature_entitlements_window_check',
			'organization_feature_entitlement_audits_version_check',
			'organization_feature_entitlement_audits_reason_check',
			'organization_feature_entitlement_audits_request_check',
			'organization_feature_entitlement_audits_source_evidence_check',
		]) {
			expect(sql).toContain(`CONSTRAINT ${constraint}`);
		}

		for (const trigger of [
			'organization_feature_entitlement_identity_guard',
			'organization_feature_entitlement_audit_history_guard',
		]) {
			expect(sql).toContain(trigger);
		}

		for (const featureKey of [
			'organization.dashboard.read',
			'organization.members.read',
			'organization.members.create',
			'organization.payments.read',
			'organization.payments.create',
			'organization.reports.export',
		]) {
			expect(sql).toContain(featureKey);
		}

		expect(sql).toContain('initial_migration');
		expect(sql).toContain(
			'REVOKE ALL ON TABLE public.organization_feature_entitlements FROM PUBLIC',
		);
		expect(sql).toContain(
			'REVOKE ALL ON TABLE public.organization_feature_entitlement_audit_events FROM PUBLIC',
		);
		expect(sql).not.toMatch(/DROP TABLE|DROP COLUMN|TRUNCATE|ON DELETE CASCADE/u);
	});
});
