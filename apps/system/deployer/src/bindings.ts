/**
 * The binding types the deployer passes through to Cloudflare, by their `wrangler.json` key, and
 * for each the account resource a binding of it names: `r2:<bucket>`, `d1:<id>`, `service:<name>`.
 * One table, so a type Cloudflare adds later is one row and never a silent pass. No type is refused
 * for what it is -- spec/architecture/deployer.md, "What it refuses" -- but a resource is the
 * owner's to have been given. Only types that name no file are here.
 */

/** What one binding names: a resource, as `kind:identifier`, or the field it should have named. */
export type Claim =
	| { readonly resource: string; readonly field: string }
	| { readonly missing: string };

type Reader = (value: unknown) => Claim[];

/** Entries of a binding array, each an object; anything else is read as an entry naming nothing. */
function entries(value: unknown): Record<string, unknown>[] {
	return (Array.isArray(value) ? value : []).map((each) =>
		each && typeof each === 'object' ? (each as Record<string, unknown>) : {},
	);
}

/** Each entry's `field`, as `kind:value`; an entry without it names a resource nobody can check. */
function by(kind: string, field: string): Reader {
	return (value) => entries(value).map((entry) => claim(kind, field, entry[field]));
}

function claim(kind: string, field: string, value: unknown): Claim {
	return typeof value === 'string' && value !== ''
		? { resource: `${kind}:${value}`, field }
		: { missing: field };
}

/** Names nothing but the Worker's own: its files, its plain text, its own secrets' names. */
const OWN: Reader = () => [];

/**
 * A product bound whole, with no identifier to scope it by: AI reaches the account's AI Search and
 * Gateway, Browser Rendering every Worker's open sessions. So the binding is itself the resource,
 * `ai:account` or `browser:account`, given as one.
 */
function whole(kind: string): Reader {
	return (value) => (value === undefined ? [] : [{ resource: `${kind}:account`, field: kind }]);
}

/**
 * A Durable Object or a Workflow is the Worker's own unless `script_name` puts it in another
 * Worker's script, which is then the resource it names.
 */
function inScript(entry: Record<string, unknown>): Claim[] {
	return entry.script_name === undefined ? [] : [claim('script', 'script_name', entry.script_name)];
}

export const BINDINGS: Readonly<Record<string, Reader>> = {
	assets: OWN,
	// Only the names of the Worker's own secrets, which it is asked to have set.
	secrets: OWN,
	vars: OWN,
	version_metadata: OWN,

	ai: whole('ai'),
	browser: whole('browser'),
	// Its own classes' changes, except a class taken from another Worker, with that Worker's data.
	migrations: (value) =>
		entries(value).flatMap((migration) =>
			entries(migration.transferred_classes).map((moved) =>
				claim('script', 'transferred_classes.from_script', moved.from_script),
			),
		),
	// A node's Caddy through its tunnel, the way into its private side: given, never assumed.
	vpc_services: by('vpc', 'service_id'),

	analytics_engine_datasets: by('dataset', 'dataset'),
	d1_databases: by('d1', 'database_id'),
	dispatch_namespaces: (value) =>
		entries(value).flatMap((entry) => {
			const outbound = (entry.outbound ?? {}) as Record<string, unknown>;
			const named = [claim('dispatch', 'namespace', entry.namespace)];
			if (outbound.service === undefined) return named;
			return named.concat(claim('service', 'outbound.service', outbound.service));
		}),
	durable_objects: (value) =>
		entries((value as { bindings?: unknown } | undefined)?.bindings).flatMap(inScript),
	hyperdrive: by('hyperdrive', 'id'),
	kv_namespaces: by('kv', 'id'),
	mtls_certificates: by('mtls', 'certificate_id'),
	pipelines: by('pipeline', 'pipeline'),
	// A consumer's dead-letter queue is a queue it writes to, claimed as its own queue is.
	queues: (value) => {
		const { producers, consumers } = (value ?? {}) as Record<string, unknown>;
		return [
			...entries(producers).map((entry) => claim('queue', 'queue', entry.queue)),
			...entries(consumers).flatMap((entry) => [
				claim('queue', 'queue', entry.queue),
				...(entry.dead_letter_queue === undefined
					? []
					: [claim('queue', 'dead_letter_queue', entry.dead_letter_queue)]),
			]),
		];
	},
	r2_buckets: by('r2', 'bucket_name'),
	ratelimits: by('ratelimit', 'namespace_id'),
	secrets_store_secrets: (value) =>
		entries(value).map((entry) =>
			typeof entry.store_id === 'string' && typeof entry.secret_name === 'string'
				? claim('secret', 'store_id/secret_name', `${entry.store_id}/${entry.secret_name}`)
				: { missing: 'store_id/secret_name' },
		),
	services: by('service', 'service'),
	streaming_tail_consumers: by('service', 'service'),
	tail_consumers: by('service', 'service'),
	vectorize: by('vectorize', 'index_name'),
	workflows: (value) =>
		entries(value).flatMap((entry) =>
			[claim('workflow', 'name', entry.name)].concat(inScript(entry)),
		),
};

/** Every resource `config`'s bindings name, through the types in BINDINGS; others are not read. */
export function claimsOf(config: Readonly<Record<string, unknown>>): Claim[] {
	return Object.entries(config).flatMap(([key, value]) => BINDINGS[key]?.(value) ?? []);
}
