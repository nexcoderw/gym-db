import { Inject, Injectable, type OnModuleDestroy, type OnModuleInit } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';

import type { DatabaseConfig } from '../config/database.config.js';
import { PrismaClient } from '../generated/prisma/client.js';
import { DATABASE_CONFIG } from './database.constants.js';

/**
 * Shared Prisma client with lifecycle hooks controlled by the consuming NestJS application.
 * The application must enable Nest shutdown hooks so `onModuleDestroy` runs on termination.
 */
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
	constructor(@Inject(DATABASE_CONFIG) config: DatabaseConfig) {
		const adapter = new PrismaPg({
			connectionString: config.databaseUrl,
			connectionTimeoutMillis: config.connectionTimeoutMilliseconds,
			max: config.poolMax,
		});
		super({ adapter });
	}

	async onModuleInit(): Promise<void> {
		await this.$connect();
	}

	async onModuleDestroy(): Promise<void> {
		await this.$disconnect();
	}
}
