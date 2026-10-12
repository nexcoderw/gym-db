/** Tenant identity established by the authenticated API request. */
export interface TenantContext {
	readonly organizationId: string;
	readonly branchId?: string;
}
