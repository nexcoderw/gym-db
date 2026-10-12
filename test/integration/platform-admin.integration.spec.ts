import { jest } from '@jest/globals';
import { Test, type TestingModule } from '@nestjs/testing';

import { DatabaseModule } from '../../src/database/database.module.js';
import { PrismaService } from '../../src/database/prisma.service.js';
import { PlatformStaffStatus, UserStatus } from '../../src/generated/prisma/client.js';

const FICTIONAL_PASSWORD_HASH = 'argon2id-test-hash-not-a-real-credential';
const UNKNOWN_USER_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const UNKNOWN_ROLE_ID = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const TRANSACTION_MAX_WAIT_MILLISECONDS = 10_000;
const TRANSACTION_TIMEOUT_MILLISECONDS = 15_000;

jest.setTimeout(30_000);

function requireTestDatabaseUrl(): string {
	const value = process.env.TEST_DATABASE_URL?.trim();
	if (value === undefined || value === '') {
		throw new Error(
			'TEST_DATABASE_URL is required for platform authorization integration tests. ' +
				'Provide a disposable, migrated PostgreSQL database; production databases are forbidden.',
		);
	}

	const runtimeDatabaseUrl = process.env.DATABASE_URL?.trim();
	if (runtimeDatabaseUrl !== undefined && value === runtimeDatabaseUrl) {
		throw new Error(
			'TEST_DATABASE_URL must not match DATABASE_URL. Use a separate disposable test database.',
		);
	}

	return value;
}

async function clearPlatformData(prisma: PrismaService): Promise<void> {
	await prisma.$transaction(
		async (transaction) => {
			await transaction.platformRolePermission.deleteMany();
			await transaction.platformStaffRole.deleteMany();
			await transaction.passwordCredential.deleteMany();
			await transaction.platformPermission.deleteMany();
			await transaction.platformRole.deleteMany();
			await transaction.platformStaff.deleteMany();
			await transaction.user.deleteMany();
		},
		{
			maxWait: TRANSACTION_MAX_WAIT_MILLISECONDS,
			timeout: TRANSACTION_TIMEOUT_MILLISECONDS,
		},
	);
}

async function expectConstraintViolation(
	operation: Promise<unknown>,
	code: 'P2002' | 'P2003',
): Promise<void> {
	await expect(operation).rejects.toMatchObject({ code });
}

const testDatabaseUrl = requireTestDatabaseUrl();

describe('platform administrator database foundation', () => {
	let module: TestingModule;
	let prisma: PrismaService;

	beforeAll(async () => {
		module = await Test.createTestingModule({
			imports: [
				DatabaseModule.forRoot({
					databaseUrl: testDatabaseUrl,
					poolMax: 2,
					connectionTimeoutMilliseconds: 10_000,
				}),
			],
		}).compile();
		await module.init();
		prisma = module.get(PrismaService);
	});

	beforeEach(async () => {
		await clearPlatformData(prisma);
	});

	afterAll(async () => {
		await clearPlatformData(prisma);
		await module.close();
	});

	it('creates a pending global user without platform access', async () => {
		const user = await prisma.user.create({
			data: { email: 'aline.uwase@example.com', displayName: 'Aline Uwase' },
			include: { passwordCredential: true, platformStaff: true },
		});

		expect(user.status).toBe(UserStatus.PENDING);
		expect(user.passwordCredential).toBeNull();
		expect(user.platformStaff).toBeNull();
		expect(await prisma.platformStaffRole.count()).toBe(0);
	});

	it('rejects email duplicates that differ only by case', async () => {
		await prisma.user.create({
			data: { email: 'claudine.mukamana@example.com', displayName: 'Claudine Mukamana' },
		});

		await expectConstraintViolation(
			prisma.user.create({
				data: { email: 'CLAUDINE.MUKAMANA@EXAMPLE.COM', displayName: 'Another Identity' },
			}),
			'P2002',
		);
	});

	it('allows at most one password credential per user', async () => {
		const user = await prisma.user.create({
			data: { email: 'kevin.habimana@example.com', displayName: 'Kevin Habimana' },
		});
		await prisma.passwordCredential.create({
			data: { userId: user.id, passwordHash: FICTIONAL_PASSWORD_HASH },
		});

		await expectConstraintViolation(
			prisma.passwordCredential.create({
				data: { userId: user.id, passwordHash: FICTIONAL_PASSWORD_HASH },
			}),
			'P2002',
		);
	});

	it('rejects credentials for an unknown user', async () => {
		await expectConstraintViolation(
			prisma.passwordCredential.create({
				data: { userId: UNKNOWN_USER_ID, passwordHash: FICTIONAL_PASSWORD_HASH },
			}),
			'P2003',
		);
	});

	it('allows at most one platform staff assignment per user', async () => {
		const user = await prisma.user.create({
			data: { email: 'diane.ingabire@example.com', displayName: 'Diane Ingabire' },
		});
		await prisma.platformStaff.create({
			data: { userId: user.id, status: PlatformStaffStatus.PENDING },
		});

		await expectConstraintViolation(
			prisma.platformStaff.create({
				data: { userId: user.id, status: PlatformStaffStatus.ACTIVE },
			}),
			'P2002',
		);
	});

	it('enforces unique platform role keys', async () => {
		await prisma.platformRole.create({
			data: {
				key: 'platform.support',
				name: 'Platform Support',
				description: 'Supports fictional NEXCODE platform operations.',
			},
		});

		await expectConstraintViolation(
			prisma.platformRole.create({
				data: {
					key: 'PLATFORM.SUPPORT',
					name: 'Duplicate Support',
					description: 'Must not be created.',
				},
			}),
			'P2002',
		);
	});

	it('enforces unique platform permission keys', async () => {
		await prisma.platformPermission.create({
			data: {
				key: 'platform.staff.read',
				description: 'Reads platform staff metadata.',
			},
		});

		await expectConstraintViolation(
			prisma.platformPermission.create({
				data: { key: 'PLATFORM.STAFF.READ', description: 'Must not be created.' },
			}),
			'P2002',
		);
	});

	it('rejects duplicate staff role assignments', async () => {
		const user = await prisma.user.create({
			data: { email: 'eric.nshimiyimana@example.com', displayName: 'Eric Nshimiyimana' },
		});
		const staff = await prisma.platformStaff.create({
			data: { userId: user.id, status: PlatformStaffStatus.ACTIVE },
		});
		const role = await prisma.platformRole.create({
			data: {
				key: 'platform.administrator',
				name: 'Platform Administrator',
				description: 'Administers approved NEXCODE platform capabilities.',
			},
		});
		const assignment = { platformStaffId: staff.id, platformRoleId: role.id };
		await prisma.platformStaffRole.create({ data: assignment });

		await expectConstraintViolation(prisma.platformStaffRole.create({ data: assignment }), 'P2002');
	});

	it('rejects duplicate role permission mappings', async () => {
		const role = await prisma.platformRole.create({
			data: {
				key: 'platform.billing',
				name: 'Platform Billing',
				description: 'Manages approved platform billing capabilities.',
			},
		});
		const permission = await prisma.platformPermission.create({
			data: {
				key: 'platform.subscriptions.manage',
				description: 'Manages platform subscription configuration.',
			},
		});
		const mapping = { platformRoleId: role.id, platformPermissionId: permission.id };
		await prisma.platformRolePermission.create({ data: mapping });

		await expectConstraintViolation(
			prisma.platformRolePermission.create({ data: mapping }),
			'P2002',
		);
	});

	it('rejects staff role assignments with invalid relationships', async () => {
		await expectConstraintViolation(
			prisma.platformStaffRole.create({
				data: { platformStaffId: UNKNOWN_USER_ID, platformRoleId: UNKNOWN_ROLE_ID },
			}),
			'P2003',
		);
	});

	it('restricts deletion of security records that still have dependents', async () => {
		const user = await prisma.user.create({
			data: { email: 'fiona.mutesi@example.com', displayName: 'Fiona Mutesi' },
		});
		await prisma.passwordCredential.create({
			data: { userId: user.id, passwordHash: FICTIONAL_PASSWORD_HASH },
		});
		const staff = await prisma.platformStaff.create({
			data: { userId: user.id, status: PlatformStaffStatus.ACTIVE },
		});
		const role = await prisma.platformRole.create({
			data: {
				key: 'platform.owner',
				name: 'Platform Owner',
				description: 'Reserved for explicitly bootstrapped NEXCODE ownership.',
				isSystem: true,
			},
		});
		const permission = await prisma.platformPermission.create({
			data: {
				key: 'platform.audit.read',
				description: 'Reads privileged platform audit records.',
			},
		});
		await prisma.platformStaffRole.create({
			data: { platformStaffId: staff.id, platformRoleId: role.id },
		});
		await prisma.platformRolePermission.create({
			data: { platformRoleId: role.id, platformPermissionId: permission.id },
		});

		await expectConstraintViolation(prisma.user.delete({ where: { id: user.id } }), 'P2003');
		await expectConstraintViolation(
			prisma.platformStaff.delete({ where: { id: staff.id } }),
			'P2003',
		);
		await expectConstraintViolation(
			prisma.platformRole.delete({ where: { id: role.id } }),
			'P2003',
		);
		await expectConstraintViolation(
			prisma.platformPermission.delete({ where: { id: permission.id } }),
			'P2003',
		);
	});

	it('persists account and platform staff suspension states', async () => {
		const suspendedAt = new Date('2026-10-12T12:00:00.000Z');
		const user = await prisma.user.create({
			data: {
				email: 'grace.umutesi@example.com',
				displayName: 'Grace Umutesi',
				status: UserStatus.SUSPENDED,
			},
		});
		const staff = await prisma.platformStaff.create({
			data: {
				userId: user.id,
				status: PlatformStaffStatus.SUSPENDED,
				suspendedAt,
			},
		});

		expect(user.status).toBe(UserStatus.SUSPENDED);
		expect(staff.status).toBe(PlatformStaffStatus.SUSPENDED);
		expect(staff.suspendedAt).toEqual(suspendedAt);
	});

	it('resolves permissions only through explicit staff role relationships', async () => {
		const user = await prisma.user.create({
			data: { email: 'henriette.kayitesi@example.com', displayName: 'Henriette Kayitesi' },
		});
		const staff = await prisma.platformStaff.create({
			data: { userId: user.id, status: PlatformStaffStatus.ACTIVE },
		});
		const role = await prisma.platformRole.create({
			data: {
				key: 'platform.support',
				name: 'Platform Support',
				description: 'Supports approved platform operations.',
			},
		});
		const permission = await prisma.platformPermission.create({
			data: {
				key: 'platform.dashboard.read',
				description: 'Reads the platform operations dashboard.',
			},
		});
		await prisma.platformStaffRole.create({
			data: { platformStaffId: staff.id, platformRoleId: role.id },
		});
		await prisma.platformRolePermission.create({
			data: { platformRoleId: role.id, platformPermissionId: permission.id },
		});

		const authorization = await prisma.platformStaff.findUnique({
			where: { id: staff.id },
			include: {
				roles: {
					include: {
						platformRole: {
							include: { permissions: { include: { platformPermission: true } } },
						},
					},
				},
			},
		});

		expect(authorization?.roles[0]?.platformRole.key).toBe('platform.support');
		expect(authorization?.roles[0]?.platformRole.permissions[0]?.platformPermission.key).toBe(
			'platform.dashboard.read',
		);
	});

	it('rolls back related identity and platform staff writes together', async () => {
		const rollbackError = new Error('intentional platform identity rollback');
		const email = 'ineza.marie@example.com';

		await expect(
			prisma.$transaction(
				async (transaction) => {
					const user = await transaction.user.create({
						data: { email, displayName: 'Marie Ineza' },
					});
					await transaction.passwordCredential.create({
						data: { userId: user.id, passwordHash: FICTIONAL_PASSWORD_HASH },
					});
					await transaction.platformStaff.create({
						data: { userId: user.id, status: PlatformStaffStatus.PENDING },
					});
					throw rollbackError;
				},
				{
					maxWait: TRANSACTION_MAX_WAIT_MILLISECONDS,
					timeout: TRANSACTION_TIMEOUT_MILLISECONDS,
				},
			),
		).rejects.toBe(rollbackError);

		expect(await prisma.user.findUnique({ where: { email } })).toBeNull();
	});
});
