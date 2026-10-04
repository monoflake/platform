import { defineConfig } from 'tsdown';

// One output per source file, named as the source is, published in place of the TypeScript a
// consumer here reads directly.
export default defineConfig({
	entry: [
		'artifacts/src/anchors.ts',
		'artifacts/src/index.ts',
		'artifacts/src/types.ts',
		'cache/src/index.ts',
		'imgsrc/src/index.ts',
		'limits/src/index.ts',
		'robots/src/index.ts',
		'security/src/agents.ts',
		'security/src/index.ts',
		'src/index.ts',
		'store/src/index.ts',
		'symlink/src/index.ts',
	],
	unbundle: true,
	tsconfig: 'tsconfig.build.json',
	// The package's own directory, so `dist/` mirrors it whatever the entries have in common.
	root: '.',
	format: 'esm',
	platform: 'neutral',
	dts: true,
	outExtensions: () => ({ js: '.js', dts: '.d.ts' }),
});
