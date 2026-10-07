import { defineConfig } from 'vitest/config';

export default defineConfig({
	test: {
		projects: [
			{
				/**
				 * `apps/delivery/cdn` imports its codecs' `.wasm` files directly, which wrangler
				 * substitutes at bundle time and node does not. An empty stub is safe because a codec
				 * initializes lazily: a path that does not encode or decode never touches it.
				 */
				plugins: [
					{
						name: 'stub-wasm',
						// Ahead of Vite's own resolver, which otherwise hands the bytes to the JS loader and
						// fails while reading them as source.
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
					name: 'node',
					include: ['{apps,libs}/**/*.test.ts'],
					exclude: ['**/node_modules/**', '**/*.svelte.test.ts'],
				},
			},
		],
	},
});
