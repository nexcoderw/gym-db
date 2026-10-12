import { config } from 'dotenv';
import { defineConfig, env } from 'prisma/config';

config({ path: ['.env.local', '.env'] });

const migrationDatabaseUrl = process.env.DIRECT_DATABASE_URL ?? env('DATABASE_URL');
const shadowDatabaseUrl = process.env.SHADOW_DATABASE_URL;

if (shadowDatabaseUrl !== undefined && shadowDatabaseUrl === migrationDatabaseUrl) {
	throw new Error(
		'SHADOW_DATABASE_URL must point to a database that is separate from the migration database.',
	);
}

export default defineConfig({
	schema: 'prisma/schema.prisma',
	migrations: {
		path: 'prisma/migrations',
	},
	datasource: {
		url: migrationDatabaseUrl,
		...(shadowDatabaseUrl === undefined ? {} : { shadowDatabaseUrl }),
	},
});
