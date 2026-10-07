/**
 * Whether an artifact's `wrangler.json` may be deployed, and by whom: both keys, as a node's grants
 * are -- the artifact asks, the deployer's own configuration decides. See
 * spec/architecture/deployer.md, "What it refuses".
 */
import { posix } from 'node:path';
import { BINDINGS, claimsOf } from './bindings.ts';
import { HOME_OWNER } from './config.ts';
import { Refused } from './github.ts';

/** What the operator decided, from the deployer's environment; see config.ts. */
export interface Policy {
	readonly owners: ReadonlyMap<string, string>;
	readonly zones: ReadonlyMap<string, readonly string[]>;
	/** The account resources each `owner/repo` may bind, as bindings.ts spells them. */
	readonly resources: ReadonlyMap<string, readonly string[]>;
}

/** Kinds that name a Worker, which a repository may bind freely when it owns that Worker too. */
const WORKERS = new Set(['service', 'script']);

/** The keys that bind nothing: how the Worker is run and reached. Anything else is refused. None
 * names a path but `main`, which is held inside the bundle below. */
const SETTINGS: ReadonlySet<string> = new Set([
	'name',
	'main',
	'compatibility_date',
	'compatibility_flags',
	'no_bundle',
	'routes',
	'route',
	'workers_dev',
	'preview_urls',
	'observability',
	'upload_source_maps',
	'keep_vars',
	'limits',
	'placement',
	'triggers',
	'logpush',
]);

/**
 * Keys that send wrangler looking for modules by path. `find_additional_modules` alone is taken:
 * with no `base_dir` and no `rules` it searches the entry's own directory, which is in `bundle/`,
 * for the modules wrangler split out beside it -- the CDN's codecs. Links never reach the disk.
 */
const SEARCHING: Readonly<Record<string, string>> = {
	base_dir: '`base_dir`',
	rules: '`rules`',
};
const FINDING = 'find_additional_modules';

interface Route {
	readonly pattern?: string;
	readonly zone_name?: string;
	readonly zone_id?: string;
}

/** The host a route pattern is on, without a scheme, a port, a path or a leading `*.`. */
export function hostOf(pattern: string): string {
	const host = pattern
		.replace(/^[a-z]+:\/\//i, '')
		.split('/')[0]!
		.split(':')[0]!;
	// A bare leading `*` is left on, so it is on no zone: `*canmi.app` would take `xcanmi.app` too.
	return host.toLowerCase().replace(/^\*\./, '');
}

function within(host: string, zone: string): boolean {
	return host === zone || host.endsWith(`.${zone}`);
}

/** `path`, normalized, when it is a relative path under `tree` of the artifact; none otherwise. */
export function under(tree: string, path: unknown): string | undefined {
	if (typeof path !== 'string' || path.includes('\\') || path.includes('\0')) return undefined;
	const normal = posix.normalize(path).replace(/(?<=.)\/$/, '');
	return normal === tree || normal.startsWith(`${tree}/`) ? normal : undefined;
}

/**
 * Throws unless `config`, from `repository`'s run, may deploy as the Worker `app`: the artifact
 * names the Worker it is, the Worker is that repository's, every key is one admitted, and every
 * route is on a zone the repository is given.
 */
export function admit(
	app: string,
	repository: string,
	config: Readonly<Record<string, unknown>>,
	policy: Policy,
): void {
	function refuse(why: string): never {
		throw new Refused(`${app}: ${why}`);
	}
	if (config.name !== app) refuse(`the artifact deploys ${String(config.name)}, not itself`);
	const owner = policy.owners.get(app);
	if (owner === undefined) refuse('no repository owns this Worker');
	if (owner !== repository) refuse(`it is ${owner}'s, not ${repository}'s`);
	for (const key of Object.keys(config)) {
		if (Object.hasOwn(BINDINGS, key) || SETTINGS.has(key)) continue;
		if (key === FINDING && config[key] === true) continue;
		if (SEARCHING[key]) refuse(`${SEARCHING[key]} could reach outside the artifact`);
		refuse(`\`${key}\` is not a binding or a setting the deployer knows`);
	}
	const main = under('bundle', config.main);
	if (config.no_bundle !== true || main === undefined || main === 'bundle') {
		refuse('it is not a bundle packaged by .mise/tasks/worker, its entry in bundle/');
	}
	const assets = config.assets as { directory?: unknown } | undefined;
	if (assets !== undefined && under('assets', assets.directory) !== 'assets') {
		refuse("its assets are not the artifact's assets/");
	}

	// Scoped as zones are: a repository outside the platform binds what it is given, and its own.
	if (!repository.startsWith(`${HOME_OWNER}/`)) {
		const given = new Set(policy.resources.get(repository) ?? []);
		for (const claim of claimsOf(config)) {
			if ('missing' in claim) refuse(`a binding names no \`${claim.missing}\``);
			const [kind = '', name = ''] = claim.resource.split(/:(.*)/s);
			const own = WORKERS.has(kind) && policy.owners.get(name) === repository;
			if (!own && !given.has(claim.resource)) {
				refuse(`\`${claim.field}\` ${name} is not a resource ${repository} is given`);
			}
		}
	}

	const zones = policy.zones.get(repository) ?? [];
	const routes = [...((config.routes as unknown[]) ?? []), ...(config.route ? [config.route] : [])];
	for (const route of routes) {
		const {
			pattern,
			zone_name: zone,
			zone_id: id,
		} = typeof route === 'string' ? ({ pattern: route } as Route) : (route as Route);
		if (typeof pattern !== 'string') refuse('a route names no pattern');
		const host = hostOf(pattern);
		if (id !== undefined && zone === undefined) refuse(`${pattern} names its zone by id alone`);
		const allowed = zone === undefined ? zones : zones.filter((each) => each === zone);
		if (!allowed.some((each) => within(host, each))) {
			refuse(`${pattern} is not on a zone ${repository} is given`);
		}
	}
}
