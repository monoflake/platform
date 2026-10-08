/**
 * `router`: a name on `.app` sent to the node that runs the app answering it, over that node's
 * Workers VPC service, with everything the request carried. Which node runs which label is the
 * relay's to say -- every node's apps, gathered -- read from it over VPC and kept a few seconds,
 * so a deploy anywhere is routed without a redeploy here. A name nobody runs, or one the wildcard's
 * own node runs, goes on to the origin as it did before this Worker.
 */
import { URLS } from '@monoflake/sdk';

/** The suffix every interface answers on: `canmi.app`. */
export const SUFFIX = new URL(URLS.internal.app).hostname;

/**
 * The node the wildcard record's tunnel reaches, whose names the origin already answers: sent on
 * there, unchanged, rather than through its VPC service.
 */
export const ORIGIN = 'rdu';

/** Asked in this order for the relay's state, and preferred in it when several run one label. */
export const NODES = ['rdu', 'tyo', 'buf', 'gvx', 'sha', 'nrt', 'hnd', 'bru'] as const;

/** How long a table read from the relay is used, and how long one node has to answer for it. */
export const FRESH_MS = 15_000;
export const ASK_MS = 2_000;

/** label -> the nodes that run an app answering on it, in `NODES`' order. */
export type Table = ReadonlyMap<string, readonly string[]>;

export interface Env {
	readonly [binding: string]: unknown;
}

function isFetcher(value: unknown): value is Fetcher {
	return typeof (value as Fetcher | undefined)?.fetch === 'function';
}

/** The binding of `node`'s VPC service, by its name in capitals, or none. */
export function bindingOf(env: Env, node: string): Fetcher | undefined {
	const binding = env[node.toUpperCase()];
	return isFetcher(binding) ? binding : undefined;
}

/** The one label before `.canmi.app`, or none for the apex, a deeper name, or another zone. */
export function labelOf(hostname: string): string | undefined {
	const host = hostname.toLowerCase();
	if (!host.endsWith(`.${SUFFIX}`)) return undefined;
	const label = host.slice(0, -(SUFFIX.length + 1));
	return /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label) ? label : undefined;
}

interface Snapshot {
	readonly apps?: readonly { readonly label?: string; readonly running?: boolean }[];
}

/**
 * The table from the relay's `GET /state`: every running app with a label, by the nodes it runs on.
 * Anything it cannot read is left out rather than guessed.
 */
export function tableOf(state: unknown): Table {
	const nodes = (state as { data?: { nodes?: Record<string, { snapshot?: Snapshot }> } })?.data
		?.nodes;
	const table = new Map<string, string[]>();
	for (const node of Object.keys(nodes ?? {}).toSorted(byOrder)) {
		for (const app of nodes?.[node]?.snapshot?.apps ?? []) {
			if (typeof app.label !== 'string' || app.running !== true) continue;
			const running = table.get(app.label) ?? [];
			if (!running.includes(node)) running.push(node);
			table.set(app.label, running);
		}
	}
	return table;
}

/** Where `node` stands in `NODES`, one past the end for a node it does not name. */
function rank(node: string): number {
	const at = (NODES as readonly string[]).indexOf(node);
	return at === -1 ? NODES.length : at;
}

function byOrder(left: string, right: string): number {
	return rank(left) - rank(right) || left.localeCompare(right);
}

/** Where a label's requests go: the first node that runs it, or none. */
export function nodeFor(table: Table | undefined, label: string): string | undefined {
	return table?.get(label)?.[0];
}

/** One node's relay's state, as JSON, or none when it does not answer in `ask` milliseconds. */
async function stateFrom(binding: Fetcher, url: URL, ask: number): Promise<unknown> {
	try {
		const answer = await binding.fetch(new Request(url), { signal: AbortSignal.timeout(ask) });
		if (answer.ok) return await answer.json();
		await answer.body?.cancel();
	} catch {
		// Not an answer.
	}
	return undefined;
}

/** The relay's state, from the first node whose relay answers over VPC, as JSON, or none. */
export async function readState(env: Env, ask = ASK_MS): Promise<unknown> {
	const url = new URL('/state', URLS.internal.app);
	url.protocol = 'http:';
	url.hostname = `relay.${SUFFIX}`;
	for (const node of NODES) {
		const binding = bindingOf(env, node);
		if (!binding) continue;
		// oxlint-disable-next-line no-await-in-loop -- the first that answers, in order
		const state = await stateFrom(binding, url, ask);
		if (state !== undefined) return state;
	}
	return undefined;
}

/**
 * The table, read again once `FRESH_MS` have passed, one read at a time however many requests ask
 * at once. One that cannot be read keeps the last good table; with none, every name goes on to the
 * origin.
 */
export function tableKeeper(
	read: () => Promise<unknown>,
	now: () => number = Date.now,
): () => Promise<Table | undefined> {
	let kept: { at: number; table: Table } | undefined;
	let reading: Promise<Table | undefined> | undefined;
	return async () => {
		if (kept && now() - kept.at < FRESH_MS) return kept.table;
		reading ??= (async () => {
			try {
				const state = await read();
				if (state !== undefined) kept = { at: now(), table: tableOf(state) };
			} finally {
				reading = undefined;
			}
			return kept?.table;
		})();
		return reading;
	};
}

export interface Parts {
	/** The request sent on as it came, to the origin behind the route: rdu's tunnel today. */
	readonly origin: (request: Request) => Promise<Response>;
	readonly table: () => Promise<Table | undefined>;
}

/**
 * One request. To the node that runs its label, over that node's VPC service, as cloudflared would
 * hand it to Caddy: plain HTTP on the same name, every header and the body as they came, the
 * visitor's address in `Cf-Connecting-Ip`, which Caddy believes from the tunnel alone, and
 * `X-Forwarded-Proto` saying the visitor came over HTTPS. The answer, a socket's upgrade among
 * them, is handed back as it is.
 */
export async function route(request: Request, env: Env, parts: Parts): Promise<Response> {
	const url = new URL(request.url);
	const label = labelOf(url.hostname);
	if (label === undefined) return parts.origin(request);
	let table: Table | undefined;
	try {
		table = await parts.table();
	} catch {
		table = undefined;
	}
	const node = nodeFor(table, label);
	const binding = node === undefined || node === ORIGIN ? undefined : bindingOf(env, node);
	if (!binding) return parts.origin(request);
	url.protocol = 'http:';
	const forwarded = new Request(url, request);
	forwarded.headers.set('x-forwarded-proto', 'https');
	try {
		return await binding.fetch(forwarded);
	} catch {
		return new Response(`${node} runs ${label} and did not answer`, {
			status: 502,
			headers: { 'content-type': 'text/plain; charset=utf-8' },
		});
	}
}
