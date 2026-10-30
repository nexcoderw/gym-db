import {
	INITIAL_ORGANIZATION_ENTITLEMENTS,
	ORGANIZATION_ENTITLEMENT,
	type OrganizationEntitlementKey,
} from '../../src/types/organization-entitlement.js';

describe('organization entitlement catalog', () => {
	it('contains unique bounded reviewed capability keys', () => {
		const values: readonly OrganizationEntitlementKey[] = Object.values(ORGANIZATION_ENTITLEMENT);

		expect(new Set(values).size).toBe(values.length);
		expect(values).toHaveLength(17);
		for (const value of values) {
			expect(value).toMatch(/^organization\.[a-z]+(?:-[a-z]+|\.[a-z]+)*$/u);
			expect(value.length).toBeLessThanOrEqual(80);
		}
	});

	it('preserves current organization functionality during the initial rollout', () => {
		expect(INITIAL_ORGANIZATION_ENTITLEMENTS).toEqual(Object.values(ORGANIZATION_ENTITLEMENT));
		expect(Object.isFrozen(INITIAL_ORGANIZATION_ENTITLEMENTS)).toBe(true);
	});
});
