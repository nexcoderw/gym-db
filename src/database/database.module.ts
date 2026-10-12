import { DynamicModule, Module, type InjectionToken, type ModuleMetadata } from '@nestjs/common';

import type { DatabaseConfig } from '../config/database.config.js';
import { DATABASE_CONFIG } from './database.constants.js';
import { PrismaService } from './prisma.service.js';
import { TenantTransactionService } from './tenant-transaction.service.js';

/** Configuration for asynchronous database module registration. */
export interface DatabaseModuleAsyncOptions extends Pick<ModuleMetadata, 'imports'> {
	readonly inject?: InjectionToken[];
	readonly useFactory: (...dependencies: never[]) => DatabaseConfig | Promise<DatabaseConfig>;
}

/**
 * NestJS module exposing one process-wide Prisma client and fail-closed tenant transactions.
 * Import this module once in the API application's root module.
 */
@Module({})
export class DatabaseModule {
	static forRoot(config: DatabaseConfig): DynamicModule {
		return {
			module: DatabaseModule,
			providers: [
				{ provide: DATABASE_CONFIG, useValue: config },
				PrismaService,
				TenantTransactionService,
			],
			exports: [PrismaService, TenantTransactionService],
		};
	}

	static forRootAsync(options: DatabaseModuleAsyncOptions): DynamicModule {
		return {
			module: DatabaseModule,
			imports: options.imports,
			providers: [
				{
					provide: DATABASE_CONFIG,
					inject: options.inject ?? [],
					useFactory: options.useFactory,
				},
				PrismaService,
				TenantTransactionService,
			],
			exports: [PrismaService, TenantTransactionService],
		};
	}
}
