import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { type Policy, admit, hostOf } from './admission.ts';
import { BINDINGS } from './bindings.ts';
import { Refused } from './github.ts';

const POLICY: Policy = {
	owners: new Map([
		['console', 'canmi21/web'],
		['site', 'canmi21/web'],
		['gateway', 'monoflake/platform'],
		['hook', 'monoflake/platform'],
	]),
	zones: new Map([
		['canmi21/web', ['canmi.app', 'canmi.net']],
		['monoflake/platform', ['monoflake.com', 'ixc.one']],
	]),
	resources: new Map([
		[
			'canmi21/web',
			['r2:media', 'd1:site-db', 'service:aka', 'script:quota', 'vpc:rdu-caddy', 'queue:mine'],
		],
	]),
};

/** The console's wrangler.json as .mise/tasks/worker writes it. */
const CONSOLE = {
	name: 'console',
	main: 'bundle/_worker.js',
	no_bundle: true,
	compatibility_date: '2026-07-29',
	compatibility_flags: ['nodejs_compat'],
	assets: { directory: 'assets', binding: 'ASSETS' },
	routes: [{ pattern: 'console.canmi.app', custom_domain: true }],
	vpc_services: [{ binding: 'RDU', service_id: 'rdu-caddy', remote: true }],
	observability: { logs: { enabled: true } },
	workers_dev: false,
	preview_urls: false,
};

function refusal(app: string, repository: string, config: Record<string, unknown>) {
	try {
		admit(app, repository, config, POLICY);
	} catch (error) {
		expect(error).toBeInstanceOf(Refused);
		return (error as Error).message;
	}
	return undefined;
}

/** The console's config with `extra` over it, as its own repository's run. */
function as(extra: object) {
	return refusal('console', 'canmi21/web', { ...CONSOLE, ...extra });
}

describe('admit', () => {
	it('takes a Worker its owner deploys, on its own zones, with the bindings allowed', () => {
		expect(refusal('console', 'canmi21/web', CONSOLE)).toBeUndefined();
		const services = { ...CONSOLE, services: [], vars: {}, version_metadata: {}, secrets: {} };
		expect(refusal('console', 'canmi21/web', services)).toBeUndefined();
	});

	it("refuses a name nobody owns, and another repository's Worker", () => {
		expect(refusal('aka', 'canmi21/web', { ...CONSOLE, name: 'aka' })).toMatch(/no repository/);
		expect(refusal('gateway', 'canmi21/web', { ...CONSOLE, name: 'gateway' })).toMatch(
			/monoflake\/platform's/,
		);
	});

	it('refuses an artifact deploying a Worker other than the one it is named for', () => {
		expect(refusal('console', 'canmi21/web', { ...CONSOLE, name: 'gateway' })).toMatch(/deploys/);
	});

	it('passes every binding type through for the platform, unlisted', () => {
		const stateful = {
			d1_databases: [{ binding: 'DB', database_id: 'x' }],
			kv_namespaces: [{ binding: 'KV', id: 'x' }],
			r2_buckets: [{ binding: 'R2', bucket_name: 'x' }],
			durable_objects: { bindings: [{ name: 'COUNTER', class_name: 'Counter' }] },
			migrations: [{ tag: 'v1', new_sqlite_classes: ['Counter'] }],
			queues: { producers: [] },
		};
		const gateway = { ...CONSOLE, name: 'gateway', routes: [], ...stateful };
		expect(refusal('gateway', 'monoflake/platform', gateway)).toBeUndefined();
	});

	it('refuses a key it does not know, so a new binding type is named before it passes', () => {
		for (const key of ['unsafe', 'account_id', 'build', 'wasm_modules', 'containers', 'site']) {
			expect(as({ [key]: {} })).toMatch(new RegExp(`\`${key}\` is not a binding`));
		}
		expect(Object.hasOwn(BINDINGS, 'unsafe')).toBe(false);
	});

	it('refuses a route on a zone its repository is not given', () => {
		const route = (routes: unknown[]) => refusal('console', 'canmi21/web', { ...CONSOLE, routes });
		expect(route(['canmi.net/*', { pattern: '*.canmi.app/*', zone_name: 'canmi.app' }])).toBe(
			undefined,
		);
		expect(route([{ pattern: 'api.monoflake.com/*' }])).toMatch(/not on a zone/);
		expect(route(['evilcanmi.app/*'])).toMatch(/not on a zone/);
		expect(route(['*canmi.app/*'])).toMatch(/not on a zone/);
		expect(route([{ pattern: 'x.canmi.app/*', zone_name: 'monoflake.com' }])).toMatch(/zone/);
		expect(route([{ pattern: 'x.canmi.app/*', zone_id: 'abc' }])).toMatch(/by id/);
		const single = { ...CONSOLE, routes: undefined, route: 'api.monoflake.com/*' };
		expect(refusal('console', 'canmi21/web', single)).toMatch(/not on a zone/);
	});

	it('refuses a config that is not a packaged bundle, or reaches outside the artifact', () => {
		expect(as({ no_bundle: false })).toMatch(/bundle/);
		for (const main of ['../x.js', '/etc/x.js', 'bundle/../../x.js', 'assets/x.js', 'bundle']) {
			expect(as({ main })).toMatch(/bundle/);
		}
		expect(as({ main: './bundle/_worker.js' })).toBeUndefined();
		for (const directory of ['../../data', '/data', 'bundle', 'assets/../..', 'assets/sub']) {
			expect(as({ assets: { directory } })).toMatch(/assets/);
		}
		expect(as({ assets: { directory: './assets/' } })).toBeUndefined();
	});

	it('refuses every key that sends wrangler looking for modules outside the bundle', () => {
		expect(as({ base_dir: '/' })).toMatch(/base_dir/);
		expect(as({ find_additional_modules: true })).toBeUndefined();
		expect(as({ find_additional_modules: 'yes' })).toMatch(/find_additional_modules/);
		expect(as({ rules: [{ type: 'Text', globs: ['../../**'] }] })).toMatch(/rules/);
		expect(as({ dev: { port: 1 } })).toMatch(/`dev`/);
	});
});

describe('hostOf', () => {
	it('is the host a pattern is on, without its wildcard, scheme, port or path', () => {
		expect(hostOf('*.monoflake.com/*')).toBe('monoflake.com');
		expect(hostOf('console.canmi.app')).toBe('console.canmi.app');
		expect(hostOf('https://API.ixc.one:443/v1/*')).toBe('api.ixc.one');
		expect(hostOf('*monoflake.com/*')).toBe('*monoflake.com');
	});
});

/** The platform's own Workers, packaged as .mise/tasks/worker packages them. */
async function packaged(app: string): Promise<Record<string, unknown>> {
	const { experimental_readRawConfig: read } = await import('wrangler');
	const directory = join(import.meta.dirname, '../../..', app);
	const { rawConfig } = read({ config: join(directory, 'wrangler.jsonc') });
	const config: Record<string, unknown> = { ...rawConfig };
	for (const key of ['$schema', 'env', 'dev']) delete config[key];
	const split = app.endsWith('cdn') ? { find_additional_modules: true } : {};
	return { ...config, main: 'bundle/index.js', no_bundle: true, ...split };
}

describe("the platform's Workers", () => {
	const platform: Policy = {
		owners: new Map(['cdn', 'quota', 'gateway'].map((name) => [name, 'monoflake/platform'])),
		zones: new Map([
			['monoflake/platform', ['monoflake.com', 'monoflake.net', 'ixc.one', 'ill.li', 'symlink.si', 'ffoni.com']],
		]),
		resources: new Map(),
	};

	it('admits cdn with R2, quota with Durable Objects and migrations, and the gateway', async () => {
		for (const app of ['delivery/cdn', 'edge/quota', 'edge/gateway']) {
			// oxlint-disable-next-line no-await-in-loop -- one config at a time, read by wrangler
			const config = await packaged(app);
			expect(() =>
				admit(String(config.name), 'monoflake/platform', config, platform),
			).not.toThrow();
		}
		expect(Object.keys(await packaged('delivery/cdn'))).toContain('r2_buckets');
		expect(Object.keys(await packaged('edge/quota'))).toContain('migrations');
	});

	it("refuses a services owner's Worker on a zone it is not given, R2 or no R2", () => {
		const r2 = { ...CONSOLE, r2_buckets: [{ binding: 'R2', bucket_name: 'media' }] };
		expect(refusal('console', 'canmi21/web', r2)).toBeUndefined();
		const elsewhere = { ...r2, routes: ['api.monoflake.com/*'] };
		expect(refusal('console', 'canmi21/web', elsewhere)).toMatch(/not on a zone/);
	});
});

/** A migration taking `Counter` from `script`. */
function from(script: string) {
	return [
		{ tag: 'v2', transferred_classes: [{ from: 'Counter', from_script: script, to: 'Counter' }] },
	];
}

describe("a resource outside the platform's own repositories", () => {
	it('is refused unless the repository is given it, naming the field and the value', () => {
		const refusals = {
			r2_buckets: [[{ binding: 'R2', bucket_name: 'objects' }], /`bucket_name` objects/],
			d1_databases: [[{ binding: 'DB', database_id: 'ledger-db' }], /`database_id` ledger-db/],
			kv_namespaces: [[{ binding: 'KV', id: 'k1' }], /`id` k1/],
			services: [[{ binding: 'GATEWAY', service: 'gateway' }], /`service` gateway/],
			queues: [{ producers: [{ binding: 'Q', queue: 'jobs' }] }, /`queue` jobs/],
			secrets_store_secrets: [
				[{ binding: 'S', store_id: 'st', secret_name: 'root' }],
				/`store_id\/secret_name` st\/root/,
			],
			tail_consumers: [[{ service: 'probe' }], /`service` probe/],
		} as const;
		for (const [key, [value, why]] of Object.entries(refusals)) {
			expect(as({ [key]: value })).toMatch(why);
		}
	});

	it('passes when it is listed', () => {
		expect(
			as({
				r2_buckets: [{ binding: 'R2', bucket_name: 'media' }],
				d1_databases: [{ binding: 'DB', database_id: 'site-db', database_name: 'site' }],
				services: [{ binding: 'AKA', service: 'aka' }],
			}),
		).toBeUndefined();
	});

	it("refuses a consumer's dead-letter queue it is not given", () => {
		const consumer = (dead: string) => ({
			consumers: [{ queue: 'mine', dead_letter_queue: dead }],
		});
		expect(as({ queues: consumer('jobs') })).toMatch(/`dead_letter_queue` jobs/);
		expect(as({ queues: consumer('mine') })).toBeUndefined();
	});

	it("refuses a Durable Object in another Worker's script, unless it is listed", () => {
		const foreign = { bindings: [{ name: 'C', class_name: 'Counter', script_name: 'gateway' }] };
		expect(as({ durable_objects: foreign })).toMatch(/`script_name` gateway/);
		const listed = { bindings: [{ name: 'C', class_name: 'Counter', script_name: 'quota' }] };
		expect(as({ durable_objects: listed })).toBeUndefined();
	});

	it('passes a Durable Object of its own, and a Worker its own repository owns', () => {
		const own = { bindings: [{ name: 'C', class_name: 'Counter' }] };
		const migrations = [{ tag: 'v1', new_sqlite_classes: ['Counter'] }];
		expect(as({ durable_objects: own, migrations })).toBeUndefined();
		expect(as({ services: [{ binding: 'SITE', service: 'site' }] })).toBeUndefined();
	});

	it('refuses a binding that names no resource to check', () => {
		expect(as({ d1_databases: [{ binding: 'DB', database_name: 'site' }] })).toMatch(
			/names no `database_id`/,
		);
	});

	it('passes what names nothing of the account: its assets, vars, secrets and metadata', () => {
		const own = {
			vars: { A: 'b' },
			version_metadata: { binding: 'V' },
			secrets: { required: ['T'] },
		};
		expect(as(own)).toBeUndefined();
	});

	it("refuses a node's VPC service it is not given, and passes one it is", () => {
		const other = [{ binding: 'TYO', service_id: 'tyo-caddy' }];
		expect(as({ vpc_services: other })).toMatch(/`service_id` tyo-caddy/);
		expect(as({ vpc_services: [{ binding: 'RDU', service_id: 'rdu-caddy' }] })).toBeUndefined();
		expect(as({ vpc_services: [{ binding: 'RDU' }] })).toMatch(/names no `service_id`/);
	});

	it('refuses AI and Browser Rendering bound whole unless given, as the account they reach', () => {
		expect(as({ ai: { binding: 'AI' } })).toMatch(/`ai` account/);
		expect(as({ browser: { binding: 'B' } })).toMatch(/`browser` account/);
		const given = new Map([['canmi21/web', ['ai:account', 'vpc:rdu-caddy']]]);
		expect(() =>
			admit(
				'console',
				'canmi21/web',
				{ ...CONSOLE, ai: { binding: 'AI' } },
				{
					...POLICY,
					resources: given,
				},
			),
		).not.toThrow();
	});

	it("refuses a Durable Object class transferred from another repository's Worker", () => {
		expect(as({ migrations: from('gateway') })).toMatch(
			/`transferred_classes.from_script` gateway/,
		);
		// Listed, or a Worker the same repository owns.
		expect(as({ migrations: from('quota') })).toBeUndefined();
		expect(as({ migrations: from('site') })).toBeUndefined();
		const own = [
			{ tag: 'v1', new_sqlite_classes: ['A'] },
			{ tag: 'v2', renamed_classes: [{ from: 'A', to: 'B' }], deleted_classes: ['C'] },
		];
		expect(as({ migrations: own })).toBeUndefined();
	});

	it('is unrestricted for the platform, which is the account', () => {
		const gateway = {
			...CONSOLE,
			name: 'gateway',
			routes: [],
			r2_buckets: [{ binding: 'R2', bucket_name: 'objects' }],
			services: [{ binding: 'QUOTA', service: 'quota' }],
		};
		expect(refusal('gateway', 'monoflake/platform', gateway)).toBeUndefined();
	});
});
