import { defineConfig } from 'vitest/config';

/**
 * The one thing the default configuration cannot resolve.
 *
 * `apps/delivery/cdn` imports its codecs' `.wasm` files directly, which wrangler substitutes at
 * bundle time and node does not -- so any test reaching one failed to load. An empty stub is safe
 * because a codec initializes lazily: a path that does not encode or decode never touches it.
 */
export default defineConfig({
	plugins: [
		{
			name: 'stub-wasm',
			// Ahead of Vite's own resolver, which otherwise hands the bytes to the JS loader and fails
			// while reading them as source.
			enforce: 'pre' as const,
			resolveId(id) {
				return id.endsWith('.wasm') ? '\0stub-wasm' : null;
			},
			load(id) {
				return id === '\0stub-wasm' ? 'export default {};' : null;
			},
		},
	],
	test: {
		include: ['{apps,libs}/**/*.test.ts'],
		exclude: ['**/node_modules/**'],
	},
});
