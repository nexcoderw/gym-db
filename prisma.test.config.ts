import { config } from 'dotenv';
import { defineConfig, env } from 'prisma/config';

// Explicit test migration deployment never loads the runtime or restricted test environment.
config({ path: '.env.migrations.local' });

export default defineConfig({
	schema: 'prisma/schema.prisma',
	migrations: {
		path: 'prisma/migrations',
	},
	datasource: {
		url: env('TEST_MIGRATION_DATABASE_URL'),
	},
});
