import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
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

/** A directory's entries, or none when it is not there. */
function listed(directory: string): string[] {
	try {
		return readdirSync(directory);
	} catch {
		return [];
	}
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
	if (process.argv.includes('--check')) {
		if (stale()) {
			console.error('apps/edge/gateway/src/scopes.ts is stale; run `mise run scopes`');
			process.exit(1);
		}
	} else {
		writeFileSync(SCOPES, renderScopes(scopeTable(declarations())));
	}
}
