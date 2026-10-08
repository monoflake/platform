import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { URLS } from '@monoflake/sdk';
import { describe, expect, it } from 'vitest';
import {
	type Env,
	FRESH_MS,
	SUFFIX,
	type Table,
	labelOf,
	nodeFor,
	readState,
	route,
	tableKeeper,
	tableOf,
} from './index.ts';

/** `path` on `label` under `.app` -- the apex for an empty one -- over `protocol`. */
function on(label: string, path = '/', protocol = 'https:'): string {
	const url = new URL(path, URLS.internal.app);
	url.hostname = label ? `${label}.${SUFFIX}` : SUFFIX;
	url.protocol = protocol;
	return url.href;
}

/** The relay's `GET /state`, its envelope and all, with `apps` per node. */
function state(nodes: Record<string, { label?: string; running?: boolean }[]>) {
	return {
		status: 'success',
		data: {
			version: 1,
			node: 'rdu',
			nodes: Object.fromEntries(
				Object.entries(nodes).map(([name, apps]) => [name, { version: 1, snapshot: { apps } }]),
			),
		},
	};
}

/** A VPC service binding that answers `answer` and keeps what it was sent. */
function node(
	answer: (request: Request) => Response | Promise<Response> = () => new Response('ok'),
) {
	const sent: Request[] = [];
	return {
		sent,
		fetch: async (input: Request | string, init?: RequestInit) => {
			const request =
				input instanceof Request ? new Request(input, init) : new Request(input, init);
			sent.push(request);
			return answer(request);
		},
	};
}

function origin() {
	const sent: Request[] = [];
	return { sent, fetch: async (request: Request) => (sent.push(request), new Response('origin')) };
}

const TABLE: Table = new Map([
	['qq', ['sha']],
	['relay', ['rdu', 'tyo']],
	['shot', ['tyo', 'rdu']],
]);

describe('labelOf', () => {
	it('takes the one label before canmi.app and nothing else', () => {
		expect(labelOf('qq.canmi.app')).toBe('qq');
		expect(labelOf('QQ.Canmi.App')).toBe('qq');
		expect(labelOf('canmi.app')).toBeUndefined();
		expect(labelOf('a.b.canmi.app')).toBeUndefined();
		expect(labelOf('qq.canmi.app.evil.test')).toBeUndefined();
		expect(labelOf('-x.canmi.app')).toBeUndefined();
	});
});

describe('tableOf', () => {
	it('names each running label by the nodes that run it, the origin first', () => {
		const table = tableOf(
			state({
				sha: [{ label: 'qq', running: true }],
				tyo: [
					{ label: 'relay', running: true },
					{ label: 'shot', running: true },
				],
				rdu: [{ label: 'relay', running: true }, { label: 'held', running: false }, {}],
			}),
		);
		expect(table.get('qq')).toEqual(['sha']);
		expect(table.get('relay')).toEqual(['rdu', 'tyo']);
		expect(table.get('held')).toBeUndefined();
		expect(nodeFor(table, 'shot')).toBe('tyo');
		expect(nodeFor(table, 'nothing')).toBeUndefined();
	});

	it('reads nothing into what it cannot read', () => {
		expect(tableOf(undefined).size).toBe(0);
		expect(tableOf({ data: { nodes: { sha: {} } } }).size).toBe(0);
	});
});

describe('tableKeeper', () => {
	it('reads once while fresh, again once stale, and keeps the last good table on a failure', async () => {
		let now = 0;
		let reads = 0;
		let answer: unknown = state({ sha: [{ label: 'qq', running: true }] });
		const table = tableKeeper(
			async () => (reads++, answer),
			() => now,
		);
		const [first, second] = await Promise.all([table(), table()]);
		expect(reads).toBe(1);
		expect(first).toBe(second);
		now += FRESH_MS + 1;
		answer = undefined;
		expect(nodeFor(await table(), 'qq')).toBe('sha');
		expect(reads).toBe(2);
	});
});

describe('route', () => {
	it('sends a label another node runs over its VPC service, the request whole', async () => {
		const sha = node();
		const passed = origin();
		const env: Env = { SHA: sha, RDU: node() };
		const request = new Request(on('qq', '/api/chat?x=1'), {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				'cf-connecting-ip': '203.0.113.9',
				cookie: 'a=b',
			},
			body: JSON.stringify({ hello: 'qq' }),
		});
		const answer = await route(request, env, { origin: passed.fetch, table: async () => TABLE });
		expect(await answer.text()).toBe('ok');
		expect(passed.sent).toHaveLength(0);
		const [sent] = sha.sent;
		expect(sent?.url).toBe(on('qq', '/api/chat?x=1', 'http:'));
		expect(sent?.method).toBe('POST');
		expect(sent?.headers.get('cookie')).toBe('a=b');
		expect(sent?.headers.get('cf-connecting-ip')).toBe('203.0.113.9');
		expect(sent?.headers.get('x-forwarded-proto')).toBe('https');
		expect(await sent?.json()).toEqual({ hello: 'qq' });
	});

	it("hands back the node's answer as it is, a socket's upgrade among them", async () => {
		const upgraded = { status: 101, webSocket: {} } as unknown as Response;
		const sha = node(() => upgraded);
		const request = new Request(on('qq', '/socket'), {
			headers: { upgrade: 'websocket', connection: 'Upgrade', 'sec-websocket-key': 'k' },
		});
		const answer = await route(
			request,
			{ SHA: sha },
			{ origin: origin().fetch, table: async () => TABLE },
		);
		expect(answer).toBe(upgraded);
		expect(sha.sent[0]?.headers.get('upgrade')).toBe('websocket');
		expect(sha.sent[0]?.headers.get('sec-websocket-key')).toBe('k');
	});

	it.each([
		['the node behind the wildcard runs', on('relay', '/state'), TABLE],
		['nobody runs', on('nas'), TABLE],
		['is no label, the apex', on(''), TABLE],
		['has no table yet', on('qq'), undefined],
	] as const)('leaves to the origin a name that %s', async (_, url, table) => {
		const passed = origin();
		const rdu = node();
		const request = new Request(url);
		const answer = await route(
			request,
			{ RDU: rdu, SHA: node() },
			{ origin: passed.fetch, table: async () => table },
		);
		expect(await answer.text()).toBe('origin');
		expect(passed.sent[0]).toBe(request);
		expect(rdu.sent).toHaveLength(0);
	});

	it('goes to the origin when the table cannot be read, and says so when the node does not answer', async () => {
		const failing = {
			origin: origin().fetch,
			table: async () => Promise.reject(new Error('down')),
		};
		expect(await (await route(new Request(on('qq')), {}, failing)).text()).toBe('origin');
		const down = { fetch: async () => Promise.reject(new Error('unreachable')) };
		const answer = await route(
			new Request(on('qq')),
			{ SHA: down },
			{
				origin: origin().fetch,
				table: async () => TABLE,
			},
		);
		expect(answer.status).toBe(502);
	});
});

describe('readState', () => {
	it('asks the relay on the first node that answers, by its own name over VPC', async () => {
		const rdu = node(() => new Response('', { status: 503 }));
		const tyo = node(() => Response.json(state({ sha: [{ label: 'qq', running: true }] })));
		const read = await readState({ RDU: rdu, TYO: tyo });
		expect(nodeFor(tableOf(read), 'qq')).toBe('sha');
		expect(tyo.sent[0]?.url).toBe(on('relay', '/state', 'http:'));
		expect(await readState({})).toBeUndefined();
	});
});

/** A wrangler.jsonc beside this file as data: whole-line comments and trailing commas taken off. */
function wrangler(path: string) {
	const text = readFileSync(join(import.meta.dirname, path), 'utf8');
	return JSON.parse(text.replace(/^\s*\/\/.*$/gm, '').replace(/,(\s*[}\]])/g, '$1'));
}

describe('wrangler.jsonc', () => {
	it('binds every node the gateway binds, and routes the wildcard rather than claiming a domain', () => {
		const own = wrangler('../wrangler.jsonc');
		const gateway = wrangler('../../gateway/wrangler.jsonc');
		expect(own.vpc_services).toEqual(gateway.vpc_services);
		expect(own.routes).toEqual([{ pattern: '*.canmi.app/*', zone_name: 'canmi.app' }]);
	});
});
