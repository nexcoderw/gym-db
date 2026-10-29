/**
 * Reviewed organization capabilities that platform administrators may enable or disable.
 * Missing persisted entitlement rows must be treated as denied by API consumers.
 */
export const ORGANIZATION_ENTITLEMENT = {
	dashboardRead: 'organization.dashboard.read',
	membershipPlansRead: 'organization.membership-plans.read',
	membershipPlansManage: 'organization.membership-plans.manage',
	membersRead: 'organization.members.read',
	membersCreate: 'organization.members.create',
	membersUpdate: 'organization.members.update',
	membersArchive: 'organization.members.archive',
	memberSubscriptionsRead: 'organization.member-subscriptions.read',
	memberSubscriptionsManage: 'organization.member-subscriptions.manage',
	paymentsRead: 'organization.payments.read',
	paymentsCreate: 'organization.payments.create',
	paymentsVoid: 'organization.payments.void',
	paymentsRefund: 'organization.payments.refund',
	remindersRead: 'organization.reminders.read',
	remindersSend: 'organization.reminders.send',
	reportsRead: 'organization.reports.read',
	reportsExport: 'organization.reports.export',
} as const;

export type OrganizationEntitlementKey =
	(typeof ORGANIZATION_ENTITLEMENT)[keyof typeof ORGANIZATION_ENTITLEMENT];

/** Existing product capabilities enabled during the compatibility-preserving initial rollout. */
export const INITIAL_ORGANIZATION_ENTITLEMENTS = Object.freeze(
	Object.values(ORGANIZATION_ENTITLEMENT),
);
