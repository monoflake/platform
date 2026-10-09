/**
 * Everything the deployer is told, read from its environment: `config.env` and `secret.env` on its
 * node. The sources, the owners and the zones are the operator's switches, never the artifact's.
 * See spec/architecture/deployer.md, "What it refuses" and "Admitting a repository".
 */

/** Its declared port; see spec/architecture/services.md, "A service keeps one port". */
export const PORT = 12020;

export interface Config {
	/** The repositories whose runs it deploys, from `DEPLOY_SOURCES`, as host reads its own. */
	readonly sources: readonly string[];
	/** Each Worker's name against the `owner/repo` whose runs alone deploy it: `WORKER_OWNERS`. */
	readonly owners: ReadonlyMap<string, string>;
	/** The zones each `owner/repo`'s routes and custom domains may be on: `WORKER_ZONES`. */
	readonly zones: ReadonlyMap<string, readonly string[]>;
	/**
	 * The account resources each `owner/repo` outside the platform may bind: `WORKER_RESOURCES`,
	 * `canmi21/web=d1:<database_id> r2:<bucket_name> service:<worker>, other/repo=...`, each a kind
	 * and the binding's identifying field as bindings.ts reads them.
	 */
	readonly resources: ReadonlyMap<string, readonly string[]>;
	/** Every deploy runs `--dry-run`, recorded and deploying nothing: `DEPLOYER_DRY=1`. */
	readonly dry: boolean;
	/** The Workers that run dry while the rest deploy: `DRY_WORKERS`, a comma list. */
	readonly dryWorkers: ReadonlySet<string>;
	/** What a rollback asks for, as host's `HOST_TOKEN`: `DEPLOYER_TOKEN`; none refuses every one. */
	readonly token: string | undefined;
	/** What `GET /api/*` asks for, as host's `HOST_READ_TOKEN`; none refuses every read. */
	readonly readToken: string | undefined;
	/** The account and its token, `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_WORKERS_TOKEN`. */
	readonly cloudflare: { readonly account: string | undefined; readonly token: string | undefined };
	readonly data: string;
	readonly port: number;
}

export type Env = Readonly<Record<string, string | undefined>>;

function value(env: Env, key: string): string | undefined {
	const found = env[key]?.trim();
	return found ? found : undefined;
}

/** `owner/name` pairs separated by whitespace; anything else is not a repository. */
export function sources(text: string): string[] {
	return text.split(/\s+/).filter((source) => /^[\w.-]+\/[\w.-]+$/.test(source));
}

/** `key=value` pairs separated by commas, each side trimmed; a pair missing either is dropped. */
export function pairs(text: string): [string, string][] {
	return text.split(',').flatMap((pair) => {
		const at = pair.indexOf('=');
		const key = pair.slice(0, at).trim();
		const rest = pair.slice(at + 1).trim();
		return at > 0 && key && rest ? [[key, rest] as [string, string]] : [];
	});
}

export function configOf(env: Env): Config {
	const dryWorkers = (value(env, 'DRY_WORKERS') ?? '').split(',').map((name) => name.trim());
	return {
		sources: sources(value(env, 'DEPLOY_SOURCES') ?? ''),
		owners: new Map(pairs(value(env, 'WORKER_OWNERS') ?? '')),
		zones: new Map(
			pairs(value(env, 'WORKER_ZONES') ?? '').map(([owner, zones]) => [owner, zones.split(/\s+/)]),
		),
		resources: new Map(
			pairs(value(env, 'WORKER_RESOURCES') ?? '').map(([owner, list]) => [
				owner,
				list.split(/\s+/),
			]),
		),
		dry: value(env, 'DEPLOYER_DRY') === '1',
		dryWorkers: new Set(dryWorkers.filter(Boolean)),
		token: value(env, 'DEPLOYER_TOKEN'),
		readToken: value(env, 'DEPLOYER_READ_TOKEN'),
		cloudflare: {
			account: value(env, 'CLOUDFLARE_ACCOUNT_ID'),
			token: value(env, 'CLOUDFLARE_WORKERS_TOKEN'),
		},
		data: value(env, 'DEPLOYER_DATA') ?? '/data',
		port: Number(value(env, 'PORT') ?? PORT),
	};
}

/** Whether `worker` runs dry: everything does under `DEPLOYER_DRY`, or the names listed. */
export function isDry(config: Config, worker: string): boolean {
	return config.dry || config.dryWorkers.has(worker);
}

/**
 * The platform's organization: its runs are fetched with `GITHUB_ACTIONS_TOKEN` itself, and its
 * repositories bind any resource, since the platform is the account.
 */
export const HOME_OWNER = 'monoflake';

/**
 * The variable a repository's artifacts are fetched with the token in, picked by its owner: the
 * monoflake organization's own, or that owner's `GITHUB_ACTIONS_TOKEN_<OWNER>` -- `_CANMI21` for
 * `canmi21/web`. See spec/architecture/deployer.md, "Credentials".
 */
export function tokenVariable(repository: string): string | undefined {
	const [owner = ''] = repository.split('/');
	if (owner === HOME_OWNER) return 'GITHUB_ACTIONS_TOKEN';
	if (!/^[\w-]+$/.test(owner)) return undefined;
	return `GITHUB_ACTIONS_TOKEN_${owner.toUpperCase().replaceAll('-', '_')}`;
}

/** The token a repository's artifacts are fetched with, from its `tokenVariable`. */
export function tokenFor(repository: string, env: Env): string | undefined {
	const variable = tokenVariable(repository);
	return variable === undefined ? undefined : value(env, variable);
}
