import { defineConfig } from 'tsdown';

// One output per source file, named as the source is, published in place of the TypeScript a
// consumer here reads directly.
export default defineConfig({
	entry: ['src/schema.ts'],
	unbundle: true,
	// The package's own directory, so `dist/` mirrors it whatever the entries have in common.
	root: '.',
	format: 'esm',
	platform: 'neutral',
	dts: true,
	outExtensions: () => ({ js: '.js', dts: '.d.ts' }),
});
