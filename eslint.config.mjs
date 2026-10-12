// @ts-check
import eslint from '@eslint/js';
import eslintPluginPrettierRecommended from 'eslint-plugin-prettier/recommended';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
	{
		ignores: [
			'dist/**',
			'coverage/**',
			'node_modules/**',
			'src/generated/**',
			'eslint.config.mjs',
			'jest.config.cjs',
		],
	},
	eslint.configs.recommended,
	...tseslint.configs.strictTypeChecked,
	...tseslint.configs.stylisticTypeChecked,
	eslintPluginPrettierRecommended,
	{
		languageOptions: {
			globals: { ...globals.node, ...globals.jest },
			parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
			sourceType: 'module',
		},
		rules: {
			'@typescript-eslint/consistent-type-exports': 'error',
			'@typescript-eslint/consistent-type-imports': ['error', { fixStyle: 'inline-type-imports' }],
			'@typescript-eslint/no-explicit-any': 'error',
			'@typescript-eslint/no-floating-promises': 'error',
			'@typescript-eslint/no-unsafe-argument': 'error',
			'prettier/prettier': ['error', { endOfLine: 'lf', useTabs: true }],
		},
	},
	{
		files: ['**/*.module.ts'],
		rules: {
			// Nest modules are framework-discovered classes and may expose only static registration APIs.
			'@typescript-eslint/no-extraneous-class': 'off',
		},
	},
);
