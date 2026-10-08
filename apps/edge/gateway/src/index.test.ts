import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { developmentUrl, GATEWAY, PAGE_ORIGINS, URLS } from '@monoflake/sdk';
import { describe, expect, it, vi } from 'vitest';
import { declarations } from '../scripts/scopes.ts';
import { type Env, gateway, INTERNAL_HEADER, MARK, NODE_TIMEOUT_MS } from './index.ts';
import { type Check, covers } from '@monoflake/sdk/limits';
import { GATEWAY_DEFAULTS } from './declaration.ts';
import { SCOPES } from './scopes.ts';
import { type Scope, scopeTable, WORKERS } from './table.ts';

/** The public API host, whatever scope the site's own base names. */
const HOST = new URL(URLS.apps.production.api).origin;

/** wrangler.jsonc as data: its comments and trailing commas taken off, strings left alone. */
function wrangler(): {
	services: Array<{ binding: string; service: string }>;
	vpc_services: Array<{ binding: string }>;
	durable_objects?: { bindings: Array<{ name: string; class_name: string }> };
} {
	const text = readFileSync(join(import.meta.dirname, '../wrangler.jsonc'), 'utf8');
	const bare = text.replace(
		/("(?:\\.|[^"\\])*")|\/\/[^\n]*/g,
		(_match: string, string?: string) => string ?? '',
	);
	return JSON.parse(bare.replace(/,(\s*[}\]])/g, '$1'));
}

/** A binding that records the one request it is sent. */
function binding() {
	const seen: Request[] = [];
	const fetcher = {
		fetch: vi.fn(async (request: Request) => (seen.push(request), new Response('ok'))),
	};
	return { fetcher: fetcher as unknown as Fetcher, seen };
}

/** A `quota` that allows or refuses every call, and remembers which buckets it was asked. */
function counters(allowed: boolean) {
	const asked: Check[] = [];
	return {
		asked,
		counters: {
			take: async (checks: readonly Check[]) => (
				asked.push(...checks),
				{ allowed, retryAfter: allowed ? 0 : 7 }
			),
		},
	};
}

describe('the scope table', () => {
	it('is what the declarations say', () => {
		// A mismatch means a service.toml changed without `mise run scopes`.
		expect(SCOPES).toEqual(scopeTable(declarations()));
	});

	it('binds each Workers scope to its Worker, and each node to its VPC service', () => {
		const config = wrangler();
		const workers = Object.values(SCOPES)
			.filter((scope) => scope.placement === WORKERS)
			.map((scope) => ({ binding: scope.binding, service: scope.worker }));
		const scopes = config.services.filter((service) => service.binding !== 'QUOTA');
		expect(scopes.toSorted((a, b) => a.binding.localeCompare(b.binding))).toEqual(
			workers.toSorted((a, b) => a.binding.localeCompare(b.binding)),
		);
		const nodes = new Set(config.vpc_services.map((service) => service.binding));
		for (const scope of Object.values(SCOPES).filter((each) => each.placement !== WORKERS)) {
			expect(nodes).toContain(scope.binding);
			for (const node of scope.nodes ?? []) expect(nodes).toContain(node);
		}
	});

	it('marks a private scope, and leaves out one on no private side or with no API', () => {
		const table = scopeTable([
			'version = 1\nname = "ledger"\nplacements = ["rdu"]\n[api]\npublic = false\n',
			'version = 1\nname = "quota"\nplacements = ["workers"]\n',
			'version = 1\nname = "door"\nplacements = ["rdu"]\n[api]\npublic = false\nsides = ["tunnel"]\n',
			'version = 1\nname = "geo"\nplacements = ["rdu"]\n[api]\npublic = true\n',
		]);
		expect(table.ledger).toMatchObject({ placement: 'rdu', private: true, nodes: ['RDU'] });
		expect(table.quota).toBeUndefined();
		expect(table.door).toBeUndefined();
		expect(table.geo?.private).toBeUndefined();
		expect(SCOPES.ledger?.private).toBe(true);
	});

	it('carries every node a scope is placed on, and a Worker its first placement alone', () => {
		const table = scopeTable([
			'version = 1\nname = "geo"\nplacements = ["rdu", "tyo"]\n[api]\npublic = true\n',
			'version = 1\nname = "site"\nplacements = ["workers"]\n[api]\npublic = true\n',
		]);
		expect(table.geo).toMatchObject({ placement: 'rdu', binding: 'RDU', nodes: ['RDU', 'TYO'] });
		expect(table.site?.nodes).toBeUndefined();
	});

	it("carries a node scope's routing, `any` unless it says `ordered`, and nothing else", () => {
		const declared = (routing: string) =>
			`version = 1\nname = "shot"\nplacements = ["tyo", "rdu"]\n[api]\npublic = true\n${routing}`;
		expect(scopeTable([declared('')]).shot?.routing).toBe('any');
		expect(scopeTable([declared('routing = "ordered"\n')]).shot).toMatchObject({
			nodes: ['TYO', 'RDU'],
			routing: 'ordered',
		});
		expect(() => scopeTable([declared('routing = "nearest"\n')])).toThrow(/routing/);
	});

	it("binds quota's inside door, which every limit is counted at", () => {
		expect(wrangler().services).toContainEqual({
			binding: 'QUOTA',
			service: 'quota',
			entrypoint: 'Internal',
		});
	});
});

describe('a limit covering a call', () => {
	it('covers its own path exactly, or everything under a prefix ending in /*', () => {
		expect(covers('/checks', '/checks')).toBe(true);
		expect(covers('/checks', '/checks/a/results')).toBe(false);
		expect(covers('/checks/*', '/checks/a/results')).toBe(true);
		expect(covers('/checks/*', '/checks')).toBe(false);
	});
});

describe('the gateway', () => {
	const table: Record<string, Scope> = {
		site: {
			placement: WORKERS,
			binding: 'SITE',
			worker: 'site',
			prefix: '/api',
			limits: [{ methods: ['PUT'], path: '/like', count: 10, seconds: 60 }],
			routes: [
				{
					...GATEWAY_DEFAULTS,
					path: '/*',
					crawlable: true,
					cors: { origins: ['status'], methods: ['GET', 'HEAD', 'PUT'], headers: [] },
				},
			],
		},
		hook: { placement: WORKERS, binding: 'HOOK', worker: 'hook', routes: [] },
		geo: { placement: 'rdu', binding: 'RDU', routes: [] },
	};
	const listed = PAGE_ORIGINS.status?.[0] ?? '';
	const app = gateway(table);
	const ask = (path: string, env: Env = {}, init?: RequestInit) =>
		app.fetch(new Request(`${HOST}${path}`, init), env);

	it('sends a path in another spelling to its one spelling, the query kept', async () => {
		const cases = [
			['//stats', 308, '/stats'],
			['//', 301, HOST],
			['//?abc=', 308, '/?abc='],
			['/geo/address/?latitude=1', 308, '/geo/address?latitude=1'],
		] as const;
		const answers = await Promise.all(cases.map(([path]) => ask(path)));
		for (const [index, [path, status, location]] of cases.entries()) {
			expect(answers[index]?.status, path).toBe(status);
			expect(answers[index]?.headers.get('location')).toBe(location);
		}
	});

	it('does not know a scope outside its table, or one inherited from Object', async () => {
		const unknown = await Promise.all(
			['/v1/nothing/x', '/v1/constructor/x'].map((path) => ask(path)),
		);
		expect(unknown.map((answer) => answer.status)).toEqual([404, 404]);
		// Not a name a service could have, so the path is malformed rather than its scope unknown.
		expect((await ask('/v1/__proto__/x')).status).toBe(400);
	});

	it('says so when a scope it knows has no binding', async () => {
		const answer = await ask('/v1/site/x');
		expect(answer.status).toBe(502);
		expect(await answer.json()).toMatchObject({ code: 'scope_unavailable' });
	});

	it('says the service is out of reach, in the envelope, when the node cannot be reached', async () => {
		const thrown = {
			fetch: async () => Promise.reject(new Error('tunnel down')),
		} as unknown as Fetcher;
		const page = {
			fetch: async () => new Response('<html>Bad gateway</html>', { status: 502 }),
		} as unknown as Fetcher;
		const own = {
			fetch: async () =>
				Response.json({ status: 'error', code: 'service_unavailable' }, { status: 503 }),
		} as unknown as Fetcher;
		const failed = await Promise.all(
			[thrown, page].map(async (RDU) => {
				const answer = await ask('/v1/geo/address', { RDU });
				return { status: answer.status, body: await answer.json() };
			}),
		);
		for (const { status, body } of failed) {
			expect(status).toBe(502);
			expect(body).toMatchObject({ code: 'upstream_unavailable' });
		}
		// A service's own failure is passed on as it said it.
		const passed = await ask('/v1/geo/address', { RDU: own });
		expect(passed.status).toBe(503);
	});

	it('hands a Workers scope its request with the scope taken off', async () => {
		const { fetcher, seen } = binding();
		const answer = await ask(
			'/v1/site/like?slug=a',
			{ SITE: fetcher, QUOTA: counters(true).counters },
			{ method: 'PUT', headers: { 'cf-connecting-ip': '192.0.2.1' }, body: 'x' },
		);
		expect(answer.status).toBe(200);
		const [sent] = seen;
		expect(sent?.url).toBe(`${HOST}/api/v1/like?slug=a`);
		expect(sent?.method).toBe('PUT');
		expect(sent?.headers.get('cf-connecting-ip')).toBe('192.0.2.1');
		expect(await sent?.text()).toBe('x');
	});

	it('gives the bare scope the root of its prefix', async () => {
		const { fetcher, seen } = binding();
		await ask('/v1/site', { SITE: fetcher });
		expect(seen[0]?.url).toBe(`${HOST}/api/v1/`);
	});

	it("sends a scope bound to `development` to its Worker's development address", async () => {
		const real = globalThis.fetch;
		const seen: string[] = [];
		globalThis.fetch = (async (request: Request) => (
			seen.push(request.url),
			new Response('ok')
		)) as typeof fetch;
		try {
			await ask('/v1/site/media?resource=a', { SITE: 'development' });
		} finally {
			globalThis.fetch = real;
		}
		expect(seen).toEqual([`${developmentUrl('site')}/api/v1/media?resource=a`]);
	});

	it('keeps nothing in a development session, and tells the browser to keep nothing', async () => {
		const real = globalThis.fetch;
		globalThis.fetch = (async () =>
			new Response('ok', { headers: { 'cache-control': 'max-age=60' } })) as typeof fetch;
		try {
			const answer = await ask('/v1/site/media?resource=a', { SITE: 'development' });
			expect(answer.headers.get('cache-control')).toBe('no-store');
		} finally {
			globalThis.fetch = real;
		}
	});

	it("sends the host's own address to the site", async () => {
		for (const answer of await Promise.all(['', '/'].map((path) => ask(path)))) {
			expect(answer.status).toBe(301);
			expect(answer.headers.get('location')).toBe(`${URLS.apps.production.site}/?ref=api`);
		}
	});

	it('answers its own security.txt, before any scope is read', async () => {
		const answer = await ask('/.well-known/security.txt');
		expect(answer.status).toBe(200);
		expect(await answer.text()).toContain('Contact: mailto:');
	});

	it('answers robots itself, refusing every crawler on an API host', async () => {
		const text = await (await ask('/robots.txt')).text();
		expect(text).toContain('Disallow: /');
		expect(text).not.toContain('Allow:');
		expect(text).not.toContain('Content-Signal');
	});

	it('says nothing a crawler reading no Allow would read as a refusal, where all is open', async () => {
		const open: Record<string, Scope> = {
			cdn: {
				placement: WORKERS,
				binding: 'CDN',
				worker: 'cdn',
				routes: [{ ...GATEWAY_DEFAULTS, path: '/*', crawlable: true }],
			},
		};
		const answer = await gateway(open).fetch(
			new Request(new URL('/robots.txt', `https://${GATEWAY.cdn}`)),
			{},
		);
		const lines = (await answer.text()).split('\n');
		expect(lines).toContain('Disallow: ');
		expect(lines).not.toContain('Disallow: /');
	});

	it('lets a crawler into a CDN host as far as its routes say', async () => {
		const cdn: Record<string, Scope> = {
			cdn: {
				placement: WORKERS,
				binding: 'CDN',
				worker: 'cdn',
				routes: [
					{ ...GATEWAY_DEFAULTS, path: '/object/*', crawlable: true },
					{ ...GATEWAY_DEFAULTS, path: '/*' },
				],
			},
		};
		const answer = await gateway(cdn).fetch(
			new Request(new URL('/robots.txt', `https://${GATEWAY.cdn}`)),
			{},
		);
		const text = await answer.text();
		expect(text).toContain('Allow: /object/');
		expect(text).toContain('Disallow: /');
	});

	it('follows its own mark for the browser rather than reading it as a scope', async () => {
		const object = `${URLS.apps.production.cdn}/object/abc.ico`;
		const fetching = vi
			.spyOn(globalThis, 'fetch')
			.mockResolvedValue(new Response(null, { status: 302, headers: { Location: object } }));
		const answer = await ask('/favicon.ico');
		expect(String(fetching.mock.calls[0]?.[0])).toBe(
			`${URLS.apps.production.symlink}/api/favicon.ico`,
		);
		expect(answer.status).toBe(302);
		expect(answer.headers.get('Location')).toBe(object);
		fetching.mockRestore();
	});

	it('asks the alias layer by its binding for its own mark, never by a host it may answer', async () => {
		const object = `${URLS.apps.production.cdn}/object/abc.ico`;
		const seen: string[] = [];
		const AKA = {
			fetch: async (request: Request) => (
				seen.push(request.url),
				new Response(null, { status: 302, headers: { Location: object } })
			),
		} as unknown as Fetcher;
		const fetching = vi.spyOn(globalThis, 'fetch');
		const answer = await ask('/favicon.ico', { AKA });
		expect(seen).toEqual([`${URLS.apps.production.symlink}/v1/symlink/api/favicon.ico`]);
		expect(fetching).not.toHaveBeenCalled();
		expect(answer.headers.get('Location')).toBe(object);
		fetching.mockRestore();
	});

	it("sends a node's scope to its Caddy with the scope left on", async () => {
		const { fetcher, seen } = binding();
		await ask('/v1/geo/address?latitude=1&longitude=2', { RDU: fetcher });
		const node = new URL(URLS.internal.app);
		node.hostname = `api.${node.hostname}`;
		node.protocol = 'http:';
		expect(seen[0]?.url).toBe(`${node.origin}/geo/v1/address?latitude=1&longitude=2`);
	});

	it('answers a preflight from a listed origin itself', async () => {
		const { fetcher, seen } = binding();
		const answer = await ask(
			'/v1/site/like',
			{ SITE: fetcher },
			{ method: 'OPTIONS', headers: { origin: listed, 'access-control-request-method': 'PUT' } },
		);
		expect(answer.status).toBe(204);
		expect(answer.headers.get('access-control-allow-origin')).toBe(listed);
		expect(seen).toHaveLength(0);
	});

	it("adds CORS to the service's answer by the route's service codes", async () => {
		const { fetcher } = binding();
		const env = { SITE: fetcher };
		const from = async (origin?: string) =>
			(await ask('/v1/site/stats', env, { headers: origin ? { origin } : {} })).headers;
		expect((await from(listed)).get('access-control-allow-origin')).toBe(listed);
		expect((await from('https://stranger.test')).get('access-control-allow-origin')).toBeNull();
		expect((await from()).get('access-control-allow-origin')).toBeNull();
		expect((await from(listed)).get('vary')).toContain('Origin');
	});

	it('gives a route that declares no CORS none at all', async () => {
		const { fetcher } = binding();
		const answer = await ask('/v1/hook/github', { HOOK: fetcher }, { headers: { origin: listed } });
		expect(answer.headers.get('access-control-allow-origin')).toBeNull();
	});

	it('limits by address on the method and path a limit names, and nothing else', async () => {
		const { fetcher, seen } = binding();
		const refused = counters(false);
		const env = { SITE: fetcher, QUOTA: refused.counters };
		const headers = { 'cf-connecting-ip': '192.0.2.1' };
		const answer = await ask('/v1/site/like', env, { method: 'PUT', headers });
		expect(answer.status).toBe(429);
		expect(answer.headers.get('retry-after')).toBe('7');
		expect(refused.asked).toEqual([
			{ key: 'site_put_like_address-192.0.2.1', rate: { count: 10, seconds: 60 } },
		]);
		expect(seen).toHaveLength(0);
		// Another method on the same path, and a caller with no address, are not this limit's.
		expect((await ask('/v1/site/like', env, { headers })).status).toBe(200);
		expect((await ask('/v1/site/like', env, { method: 'PUT' })).status).toBe(200);
	});

	it('skips the counter for a request carrying the probe token, and counts everyone else', async () => {
		const { fetcher, seen } = binding();
		const refused = counters(false);
		const env = { SITE: fetcher, QUOTA: refused.counters, PROBE_TOKEN: 'shh' };
		const headers = { 'cf-connecting-ip': '192.0.2.1' };
		const probe = await ask('/v1/site/like', env, {
			method: 'PUT',
			headers: { ...headers, 'x-probe': 'shh' },
		});
		expect(probe.status).toBe(200);
		expect(seen).toHaveLength(1);
		expect(refused.asked).toHaveLength(0);
		const stranger = await ask('/v1/site/like', env, {
			method: 'PUT',
			headers: { ...headers, 'x-probe': 'nope' },
		});
		expect(stranger.status).toBe(429);
		const nobody = await ask('/v1/site/like', env, { method: 'PUT', headers });
		expect(nobody.status).toBe(429);
	});

	it('never exempts a probe header when the secret is not set', async () => {
		const { fetcher } = binding();
		const refused = counters(false);
		const env = { SITE: fetcher, QUOTA: refused.counters };
		const answer = await ask('/v1/site/like', env, {
			method: 'PUT',
			headers: { 'cf-connecting-ip': '192.0.2.1', 'x-probe': '' },
		});
		expect(answer.status).toBe(429);
	});

	it('does not count again what the internal gateway counted, and takes its token off', async () => {
		const { fetcher, seen } = binding();
		const refused = counters(false);
		const env = { SITE: fetcher, QUOTA: refused.counters, INTERNAL_TOKEN: 'house' };
		const headers = { 'cf-connecting-ip': '192.0.2.1', [INTERNAL_HEADER]: 'house' };
		expect((await ask('/v1/site/like', env, { method: 'PUT', headers })).status).toBe(200);
		expect(refused.asked).toHaveLength(0);
		expect(seen[0]?.headers.has(INTERNAL_HEADER)).toBe(false);
		const forged = { ...headers, [INTERNAL_HEADER]: 'guess' };
		expect((await ask('/v1/site/like', env, { method: 'PUT', headers: forged })).status).toBe(429);
	});

	it('marks what it passes on as public, over whatever the caller claimed', async () => {
		const { fetcher, seen } = binding();
		await ask('/v1/geo/address', { RDU: fetcher }, { headers: { [MARK.name]: 'internal' } });
		await ask('/v1/site/stats', { SITE: binding().fetcher });
		expect(seen[0]?.headers.get(MARK.name)).toBe(MARK.value);
	});

	it('lets a call through when its counter fails, rather than failing it', async () => {
		const { fetcher } = binding();
		const broken = { take: async () => Promise.reject(new Error('over quota')) };
		const error = vi.spyOn(console, 'error').mockImplementation(() => undefined);
		const headers = { 'cf-connecting-ip': '192.0.2.1' };
		const answer = await ask(
			'/v1/site/like',
			{ SITE: fetcher, QUOTA: broken },
			{ method: 'PUT', headers },
		);
		expect(answer.status).toBe(200);
		expect(error).toHaveBeenCalled();
		error.mockRestore();
	});

	it('refuses rather than skips a limit whose binding is missing', async () => {
		const { fetcher } = binding();
		const headers = { 'cf-connecting-ip': '192.0.2.1' };
		expect((await ask('/v1/site/like', { SITE: fetcher }, { method: 'PUT', headers })).status).toBe(
			429,
		);
	});
});

describe('a private scope', () => {
	const app = gateway({
		ledger: { placement: 'rdu', private: true, binding: 'RDU', nodes: ['RDU'], routes: [] },
	});
	const ask = (env: Env, headers: Record<string, string> = {}) =>
		app.fetch(new Request(`${HOST}/v1/ledger/events?x=1`, { method: 'POST', headers }), env);
	const refusing = counters(false);

	it('reaches its service with the token, sent its own path and never the token', async () => {
		const { fetcher, seen } = binding();
		const env = { RDU: fetcher, QUOTA: refusing.counters, INTERNAL_TOKEN: 'house' };
		const answer = await ask(env, { [INTERNAL_HEADER]: 'house', 'cf-connecting-ip': '192.0.2.1' });
		expect(answer.status).toBe(200);
		const url = new URL(seen[0]?.url ?? '');
		expect(`${url.pathname}${url.search}`).toBe('/ledger/events?x=1');
		expect(seen[0]?.headers.has(INTERNAL_HEADER)).toBe(false);
		// Counted once, where it entered, which counts nothing of our own.
		expect(refusing.asked).toHaveLength(0);
	});

	it('does not exist without the token, a wrong one, or a token unset', async () => {
		const { fetcher, seen } = binding();
		const env = { RDU: fetcher, INTERNAL_TOKEN: 'house' };
		for (const headers of [{}, { [INTERNAL_HEADER]: 'guess' }] as Record<string, string>[]) {
			const answer = await ask(env, headers);
			expect(answer.status).toBe(404);
			expect(((await answer.json()) as { code: string }).code).toBe('no_such_scope');
		}
		const unset = await ask({ RDU: fetcher }, { [INTERNAL_HEADER]: '' });
		expect(unset.status).toBe(404);
		expect(seen).toHaveLength(0);
	});

	it('is in no robots.txt', async () => {
		const robots = await app.fetch(new Request(`${HOST}/robots.txt`), {});
		expect(await robots.text()).not.toContain('ledger');
	});
});

describe('a service placed on several nodes', () => {
	const app = gateway({
		geo: { placement: 'rdu', binding: 'RDU', nodes: ['RDU', 'TYO'], routes: [] },
		shot: { placement: 'rdu', binding: 'RDU', nodes: ['RDU'], routes: [] },
	});
	const ask = (path: string, env: Env, init?: RequestInit) =>
		app.fetch(new Request(`${HOST}${path}`, init), env);

	/** A node that records what it is asked, and answers with `answer`. */
	function node(name: string, asked: string[], answer: () => Promise<Response>) {
		const bodies: string[] = [];
		const fetcher = {
			fetch: async (request: Request) => {
				asked.push(name);
				bodies.push(await request.text());
				return answer();
			},
		} as unknown as Fetcher;
		return { fetcher, bodies };
	}
	const ok = async () => Response.json({ status: 'ok' });
	const down = async () => Promise.reject(new Error('tunnel down'));
	/** The declared order kept: the shuffle swaps nothing when every draw is just under one. */
	const inOrder = () => vi.spyOn(Math, 'random').mockReturnValue(0.999);

	it('asks a node it is placed on, with the scope left on', async () => {
		const asked: string[] = [];
		const rdu = binding();
		const answer = await ask('/v1/geo/address?latitude=1', {
			RDU: rdu.fetcher,
			TYO: node('tyo', asked, ok).fetcher,
		});
		expect(answer.status).toBe(200);
		const urls = [...rdu.seen.map((request) => new URL(request.url).pathname), ...asked];
		expect(urls).toHaveLength(1);
		expect(['/geo/v1/address', 'tyo']).toContain(urls[0]);
	});

	it('falls over to the next node when the first fails to answer, the body sent again', async () => {
		const random = inOrder();
		const asked: string[] = [];
		const tyo = node('tyo', asked, ok);
		const answer = await ask(
			'/v1/geo/address',
			{ RDU: node('rdu', asked, down).fetcher, TYO: tyo.fetcher },
			{ method: 'POST', body: '{"a":1}' },
		);
		random.mockRestore();
		expect(answer.status).toBe(200);
		expect(asked).toEqual(['rdu', 'tyo']);
		expect(tyo.bodies).toEqual(['{"a":1}']);
	});

	it("passes a proxy's page over for the next node, as a node that did not answer", async () => {
		const random = inOrder();
		const asked: string[] = [];
		const page = async () => new Response('<html>Bad gateway</html>', { status: 502 });
		const answer = await ask('/v1/geo/address', {
			RDU: node('rdu', asked, page).fetcher,
			TYO: node('tyo', asked, ok).fetcher,
		});
		random.mockRestore();
		expect(answer.status).toBe(200);
		expect(asked).toEqual(['rdu', 'tyo']);
	});

	it('falls over to the next node when the first outlasts its time', async () => {
		vi.useFakeTimers();
		const random = inOrder();
		const asked: string[] = [];
		const hung = () => new Promise<Response>(() => undefined);
		const pending = ask('/v1/geo/address', {
			RDU: node('rdu', asked, hung).fetcher,
			TYO: node('tyo', asked, ok).fetcher,
		});
		await vi.advanceTimersByTimeAsync(NODE_TIMEOUT_MS);
		const answer = await pending;
		random.mockRestore();
		vi.useRealTimers();
		expect(answer.status).toBe(200);
		expect(asked).toEqual(['rdu', 'tyo']);
	});

	it('gives the upstream error once every node has failed', async () => {
		const asked: string[] = [];
		const answer = await ask('/v1/geo/address', {
			RDU: node('rdu', asked, down).fetcher,
			TYO: node('tyo', asked, down).fetcher,
		});
		expect(answer.status).toBe(502);
		expect(await answer.json()).toMatchObject({ code: 'upstream_unavailable' });
		expect(asked.toSorted()).toEqual(['rdu', 'tyo']);
	});

	it("passes a node's own 503 on as it is, without asking another", async () => {
		const random = inOrder();
		const asked: string[] = [];
		const busy = async () =>
			Response.json({ status: 'error', code: 'service_unavailable' }, { status: 503 });
		const answer = await ask('/v1/geo/address', {
			RDU: node('rdu', asked, busy).fetcher,
			TYO: node('tyo', asked, ok).fetcher,
		});
		random.mockRestore();
		expect(answer.status).toBe(503);
		expect(await answer.json()).toMatchObject({ code: 'service_unavailable' });
		expect(asked).toEqual(['rdu']);
	});

	it('asks the nodes in an order that varies from request to request', async () => {
		const asked: string[] = [];
		const env = { RDU: node('rdu', asked, ok).fetcher, TYO: node('tyo', asked, ok).fetcher };
		await Promise.all(Array.from({ length: 64 }, () => ask('/v1/geo/address', env)));
		expect(new Set(asked)).toEqual(new Set(['rdu', 'tyo']));
	});

	it('asks a node bound here alone, as the gateway at home has only its own', async () => {
		const asked: string[] = [];
		const answers = await Promise.all(
			Array.from({ length: 8 }, () =>
				ask('/v1/geo/address', { RDU: node('rdu', asked, ok).fetcher }),
			),
		);
		expect(answers.map((answer) => answer.status)).toEqual(answers.map(() => 200));
		expect(new Set(asked)).toEqual(new Set(['rdu']));
	});

	it('streams a single placement its body as before, and fails it over to nothing', async () => {
		const { fetcher, seen } = binding();
		const answer = await ask(
			'/v1/shot/tasks',
			{ RDU: fetcher, TYO: binding().fetcher },
			{ method: 'POST', body: 'x' },
		);
		expect(answer.status).toBe(200);
		expect(await seen[0]?.text()).toBe('x');
		const asked: string[] = [];
		const failed = await ask('/v1/shot/tasks', { RDU: node('rdu', asked, down).fetcher });
		expect(failed.status).toBe(502);
		expect(asked).toEqual(['rdu']);
	});
});

describe('a service routed in order', () => {
	const app = gateway({
		shot: {
			placement: 'tyo',
			binding: 'TYO',
			nodes: ['TYO', 'RDU'],
			routing: 'ordered',
			routes: [],
		},
	});
	const ask = (env: Env) => app.fetch(new Request(`${HOST}/v1/shot/tasks/abc`), env);
	const asking = (name: string, asked: string[], answer: () => Promise<Response>) =>
		({
			fetch: async () => (asked.push(name), answer()),
		}) as unknown as Fetcher;
	const ok = async () => Response.json({ status: 'ok' });

	it('always asks its first placement first, and no other while it answers', async () => {
		const asked: string[] = [];
		const env = { TYO: asking('tyo', asked, ok), RDU: asking('rdu', asked, ok) };
		const answers = await Promise.all(Array.from({ length: 32 }, () => ask(env)));
		expect(answers.map((answer) => answer.status)).toEqual(answers.map(() => 200));
		expect(new Set(asked)).toEqual(new Set(['tyo']));
	});

	it('asks the next placement only when the first fails to answer', async () => {
		const asked: string[] = [];
		const down = async () => Promise.reject(new Error('tunnel down'));
		const answer = await ask({ TYO: asking('tyo', asked, down), RDU: asking('rdu', asked, ok) });
		expect(answer.status).toBe(200);
		expect(asked).toEqual(['tyo', 'rdu']);
	});

	it("passes its first placement's own 503 on, without asking the next", async () => {
		const asked: string[] = [];
		const busy = async () =>
			Response.json({ status: 'error', code: 'service_unavailable' }, { status: 503 });
		const answer = await ask({ TYO: asking('tyo', asked, busy), RDU: asking('rdu', asked, ok) });
		expect(answer.status).toBe(503);
		expect(asked).toEqual(['tyo']);
	});
});

describe("geo's declaration", () => {
	const app = gateway({ geo: SCOPES.geo as Scope });

	it('lets any page call it, and limits one address on the lookup alone', async () => {
		const refused = counters(false);
		const env = { RDU: binding().fetcher, QUOTA: refused.counters };
		const headers = { 'cf-connecting-ip': '192.0.2.1', origin: 'https://anyone.test' };
		const lookup = await app.fetch(
			new Request(`${HOST}/v1/geo/address?latitude=1&longitude=2`, { headers }),
			env,
		);
		expect(lookup.status).toBe(429);
		expect(refused.asked).toEqual([
			{ key: 'geo_get-head_address_address-192.0.2.1', rate: { count: 60, seconds: 60 } },
		]);
		const health = await app.fetch(new Request(`${HOST}/v1/geo/health`, { headers }), env);
		expect(health.status).toBe(200);
		expect(health.headers.get('access-control-allow-origin')).toBe('*');
	});
});

describe("shot's declaration", () => {
	const app = gateway({ shot: SCOPES.shot as Scope });
	const headers = { 'cf-connecting-ip': '192.0.2.1' };

	it('refuses `internal` from the public, whatever its value, before the service or a limit', async () => {
		const { fetcher, seen } = binding();
		const allowing = counters(true);
		const env = { RDU: fetcher, QUOTA: allowing.counters };
		const queries = ['internal=true', 'internal=false', 'internal', 'host=a.test&internal=1'];
		const refused = await Promise.all(
			queries.map(async (query) => {
				const answer = await app.fetch(
					new Request(`${HOST}/v1/shot/capture?${query}`, { headers }),
					env,
				);
				return { query, status: answer.status, body: await answer.json() };
			}),
		);
		for (const { query, status, body } of refused) {
			expect(status, query).toBe(403);
			expect(body).toMatchObject({ code: 'forbidden_parameter' });
		}
		const status = await app.fetch(
			new Request(`${HOST}/v1/shot/tasks/abc?internal=true`, { headers }),
			env,
		);
		expect(status.status).toBe(403);
		expect(seen).toHaveLength(0);
		expect(allowing.asked).toHaveLength(0);
	});

	it('refuses `internal` in a JSON body, however deep, and lets any other body through', async () => {
		const { fetcher, seen } = binding();
		const env = { RDU: fetcher, QUOTA: counters(true).counters };
		const post = (body: string) =>
			app.fetch(
				new Request(`${HOST}/v1/shot/capture`, {
					method: 'POST',
					headers: { ...headers, 'content-type': 'application/json' },
					body,
				}),
				env,
			);
		const bodies = ['{"internal":true}', '{"access":{"internal":false}}', '[{"a":{"internal":1}}]'];
		const answers = await Promise.all(bodies.map((body) => post(body)));
		expect(answers.map((answer) => answer.status)).toEqual(bodies.map(() => 403));
		expect(seen).toHaveLength(0);
		expect((await post('{"access":{"insecure":true},"target":{"host":"a.test"}}')).status).toBe(
			200,
		);
		expect((await post('not json')).status).toBe(200);
		expect(seen).toHaveLength(2);
	});

	it('refuses `fresh` from the public, whatever its value, before the service or a limit', async () => {
		const { fetcher, seen } = binding();
		const allowing = counters(true);
		const env = { RDU: fetcher, QUOTA: allowing.counters };
		const queries = ['fresh=true', 'fresh=false', 'fresh', 'host=a.test&fresh=1'];
		const refused = await Promise.all(
			queries.map(async (query) => {
				const answer = await app.fetch(
					new Request(`${HOST}/v1/shot/capture?${query}`, { headers }),
					env,
				);
				return { query, status: answer.status, body: await answer.json() };
			}),
		);
		for (const { query, status, body } of refused) {
			expect(status, query).toBe(403);
			expect(body).toMatchObject({ code: 'forbidden_parameter' });
		}
		expect(seen).toHaveLength(0);
		expect(allowing.asked).toHaveLength(0);
	});

	it('refuses `access.fresh` in a JSON body, however deep, and lets any other body through', async () => {
		const { fetcher, seen } = binding();
		const env = { RDU: fetcher, QUOTA: counters(true).counters };
		const post = (body: string) =>
			app.fetch(
				new Request(`${HOST}/v1/shot/capture`, {
					method: 'POST',
					headers: { ...headers, 'content-type': 'application/json' },
					body,
				}),
				env,
			);
		const bodies = ['{"fresh":true}', '{"access":{"fresh":false}}', '[{"a":{"fresh":1}}]'];
		const answers = await Promise.all(bodies.map((body) => post(body)));
		expect(answers.map((answer) => answer.status)).toEqual(bodies.map(() => 403));
		expect(seen).toHaveLength(0);
		expect((await post('{"access":{"insecure":true},"target":{"host":"a.test"}}')).status).toBe(
			200,
		);
	});

	it('limits starting a capture, and neither asking after one nor fetching it', async () => {
		const refused = counters(false);
		const env = { RDU: binding().fetcher, QUOTA: refused.counters };
		const start = await app.fetch(
			new Request(`${HOST}/v1/shot/tasks`, { method: 'POST', headers, body: '{}' }),
			env,
		);
		expect(start.status).toBe(429);
		const paths = [
			'/v1/shot/tasks/0e6f',
			'/v1/shot/pictures/0e6f.png',
			'/v1/shot/pictures/0e6f.webp',
		];
		const answers = await Promise.all(
			paths.map((path) => app.fetch(new Request(`${HOST}${path}`, { headers }), env)),
		);
		expect(answers.map((answer) => answer.status)).toEqual([200, 200, 200]);
		expect(refused.asked.map((asked) => asked.key)).toEqual(['shot_post_tasks_address-192.0.2.1']);
	});
});
