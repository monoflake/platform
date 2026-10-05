import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { GATEWAY_HOSTS, GATEWAY_NAMES } from '@monoflake/sdk';
import { renderScopes, scopeTable } from '../src/table.ts';

const ROOT = join(import.meta.dirname, '../../../..');
const APPS = join(ROOT, 'apps');
/**
 * The declarations of apps deployed from another repository that the gateway still routes: the
 * site's API is its own Worker's, and its scope is the gateway's to hold. See
 * spec/repository.md, "An app deployed elsewhere asks for its scope here".
 */
const ELSEWHERE = join(import.meta.dirname, '../elsewhere');
const SCOPES = join(import.meta.dirname, '../src/scopes.ts');
const DECLARATION = join(import.meta.dirname, '../service.toml');

/** The first line of the `[edge]` block this script owns at the foot of the declaration. */
const EDGE_MARK =
	"# Written by `mise run scopes` from @monoflake/sdk's gateway names; do not edit.";

/** A TOML array of strings. */
function list(items: readonly string[]): string {
	return `[${items.map((item) => `"${item}"`).join(', ')}]`;
}

/** A directory's entries, or none when it is not there. */
function listed(directory: string): string[] {
	try {
		return readdirSync(directory);
	} catch {
		return [];
	}
}

/**
 * The names the gateway claims at home, as its declaration states them for host: the hosts Caddy
 * routes to it and certifies, the names the resolver answers exactly, and the zone deployments are
 * spelled under. From the sdk, so a name is still written once. See infra's
 * spec/architecture/host.md, "A role is asked for by the app and granted by the node".
 */
export function renderEdge(): string {
	const { exact, deployments } = GATEWAY_NAMES;
	return [
		EDGE_MARK,
		'# Claimed only where the node grants the gateway `hosts`.',
		'[edge]',
		`hosts = ${list(GATEWAY_HOSTS)}`,
		`names = ${list(exact)}`,
		`deployments = { zone = "${deployments.zone}", regions = ${list(deployments.regions)}, providers = ${list(deployments.providers)} }`,
		'',
	].join('\n');
}

/** `declaration` with its `[edge]` block written from the sdk, in place of any it had. */
export function withEdge(declaration: string): string {
	const at = declaration.indexOf(EDGE_MARK);
	const kept = (at === -1 ? declaration : declaration.slice(0, at)).trimEnd();
	return `${kept}\n\n${renderEdge()}`;
}

/** Every app's declaration, as text. Shared with the test that holds the committed table to it. */
export function declarations(): string[] {
	const paths = [
		...listed(APPS).flatMap((group) =>
			listed(join(APPS, group)).map((app) => ({
				app,
				path: join(APPS, group, app, 'service.toml'),
			})),
		),
		...listed(ELSEWHERE)
			.filter((file) => file.endsWith('.toml'))
			.map((file) => ({ app: file.slice(0, -'.toml'.length), path: join(ELSEWHERE, file) })),
	];
	paths.sort((a, b) => a.app.localeCompare(b.app));
	return paths.flatMap(({ path }) => {
		try {
			return [readFileSync(path, 'utf8')];
		} catch {
			return [];
		}
	});
}

/**
 * `source` as oxfmt would leave it. Written beside the real file, under the name `mise run
 * scopes` never uses, so the same config oxfmt would find for `scopes.ts` applies here too;
 * removed again whether formatting succeeds or throws.
 */
export function formatted(source: string): string {
	const scratch = join(import.meta.dirname, '../src/scopes.check.ts');
	writeFileSync(scratch, source);
	try {
		execFileSync('pnpm', ['exec', 'oxfmt', scratch], { cwd: ROOT, stdio: 'pipe' });
		return readFileSync(scratch, 'utf8');
	} finally {
		rmSync(scratch);
	}
}

/**
 * Whether the committed `src/scopes.ts` disagrees with every `service.toml`, formatting
 * included, without ever writing to it. See spec/architecture/services.md, "One API host, scoped
 * by path".
 */
export function stale(): boolean {
	const table = renderScopes(scopeTable(declarations()));
	return formatted(table) !== readFileSync(SCOPES, 'utf8');
}

if (import.meta.main) {
	const declaration = readFileSync(DECLARATION, 'utf8');
	if (process.argv.includes('--check')) {
		if (stale()) {
			console.error('apps/edge/gateway/src/scopes.ts is stale; run `mise run scopes`');
			process.exit(1);
		}
		if (withEdge(declaration) !== declaration) {
			console.error("apps/edge/gateway/service.toml's [edge] is stale; run `mise run scopes`");
			process.exit(1);
		}
	} else {
		writeFileSync(DECLARATION, withEdge(declaration));
		writeFileSync(SCOPES, renderScopes(scopeTable(declarations())));
	}
}
