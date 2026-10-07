import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = join(import.meta.dirname, '../../../..');
const DECLARATION = join(ROOT, 'apps/system/deployer/service.toml');
const WRANGLER = join(import.meta.dirname, '../wrangler.jsonc');
const GENERATED = join(import.meta.dirname, '../src/receivers.ts');

/** The placement that is Cloudflare's, never a node; the same string as the gateway's `WORKERS`. */
const WORKERS = 'workers';

/** A node's binding: its placement uppercased, hyphens as underscores, as the gateway spells it. */
export function bindingOf(node: string): string {
	return node.toUpperCase().replaceAll('-', '_');
}

/**
 * The bindings of the nodes `declaration` places the deployer on, in its order. Its one-line
 * `placements` array is read by pattern, as every service.toml writes it, so the hook needs no TOML
 * parser of its own; a declaration with none places it nowhere.
 */
export function deployerNodes(declaration: string): string[] {
	const list = /^placements\s*=\s*\[([^\]]*)\]/m.exec(declaration)?.[1] ?? '';
	const placements = [...list.matchAll(/"([^"]*)"/g)].map((match) => match[1]!);
	return placements.filter((each) => each !== WORKERS).map(bindingOf);
}

/** The VPC bindings the hook's wrangler.jsonc names, read by pattern rather than parsed. */
export function boundNodes(wrangler: string): string[] {
	return [...wrangler.matchAll(/"binding":\s*"([A-Z0-9_]+)"/g)].map((match) => match[1]!);
}

/** The module `src/receivers.ts`, as oxfmt leaves it. */
export function render(nodes: readonly string[]): string {
	return [
		'// @generated from apps/system/deployer/service.toml by `mise run receivers`; do not edit.',
		'',
		'/** The bindings of the nodes the deployer is placed on; see spec/architecture/deployer.md. */',
		`export const DEPLOYER_NODES: readonly string[] = [${nodes.map((node) => `'${node}'`).join(', ')}];`,
		'',
	].join('\n');
}

/**
 * Why the committed list is wrong, or nothing: stale against the declaration, or naming a node the
 * hook does not bind, which no notice could reach. Never writes.
 */
export function drift(): string | undefined {
	const nodes = deployerNodes(readFileSync(DECLARATION, 'utf8'));
	const bound = new Set(boundNodes(readFileSync(WRANGLER, 'utf8')));
	const unbound = nodes.filter((node) => !bound.has(node));
	if (unbound.length > 0) {
		return `the deployer is placed on ${unbound.join(', ')}, which the hook does not bind`;
	}
	if (render(nodes) !== readFileSync(GENERATED, 'utf8')) {
		return 'apps/edge/hook/src/receivers.ts is stale; run `mise run receivers`';
	}
	return undefined;
}

if (import.meta.main) {
	if (process.argv.includes('--check')) {
		const why = drift();
		if (why) {
			console.error(why);
			process.exit(1);
		}
	} else {
		writeFileSync(GENERATED, render(deployerNodes(readFileSync(DECLARATION, 'utf8'))));
	}
}
