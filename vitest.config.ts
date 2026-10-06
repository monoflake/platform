import { fileURLToPath } from 'node:url';
import stylex from '@stylexjs/unplugin/vite';
import { svelte, vitePreprocess } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vitest/config';

const CONSOLE = fileURLToPath(new URL('./apps/edge/console/', import.meta.url));
const ROOT = fileURLToPath(new URL('./', import.meta.url));

/**
 * Two suites, split by filename as web splits its own: a component needs Svelte and StyleX, whose
 * `create` throws uncompiled, and nothing else here does.
 */
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
			{
				/**
				 * Svelte's plugin rather than SvelteKit's, which would start the adapter's emulated
				 * Worker for every run; the StyleX options are the console's vite.config.ts's, for the
				 * reason it gives. The tests render on the server, so Svelte's server build is the one.
				 */
				extends: false,
				root: CONSOLE,
				plugins: [
					svelte({ preprocess: vitePreprocess(), compilerOptions: { runes: true } }),
					{
						...stylex({
							useCSSLayers: true,
							unstable_moduleResolution: { type: 'commonJS', rootDir: ROOT },
						}),
						enforce: undefined,
						// A test run is not a dev server: nothing the hook installs is read.
						configureServer: undefined,
					},
				],
				test: { name: 'console', include: ['src/**/*.svelte.test.ts'] },
			},
		],
	},
});
