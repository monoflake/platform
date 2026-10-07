import { describe, expect, it } from 'vitest';
import type { Notice, Rollback } from './deploy.ts';
import { type Routes, handle } from './server.ts';

const VERSION = '0b7c2f1e-6c3a-4a7e-9b0d-1f2e3d4c5b6a';

function routes(tokens: { token?: string; readToken?: string } = { token: 'w', readToken: 'r' }) {
	const noticed: Notice[] = [];
	const rolled: Rollback[] = [];
	const asked: [number, number | undefined][] = [];
	const value: Routes = {
		token: tokens.token,
		readToken: tokens.readToken,
		owned: (worker) => worker === 'console',
		notice: (notice) => noticed.push(notice),
		rollback: (back) => rolled.push(back),
		deploys: (limit, before) => {
			asked.push([limit, before]);
			return [];
		},
	};
	return { noticed, rolled, asked, value };
}

function request(path: string, init: RequestInit = {}): Request {
	return new Request(new URL(path, 'http://localhost'), init);
}

function bearer(token: string, init: RequestInit = {}): RequestInit {
	return { ...init, headers: { authorization: `Bearer ${token}` } };
}

function rollback(token: string, version: string = VERSION, worker = 'console') {
	const init = bearer(token, { method: 'POST', body: JSON.stringify({ version }) });
	return request(`/api/workers/${worker}/rollback`, init);
}

describe('the routes', () => {
	it('answer a notice with 202 at once, and queue it', async () => {
		const { noticed, value } = routes();
		const body = JSON.stringify({ run: 7, repository: 'canmi21/web' });
		const answer = await handle(request('/notice', { method: 'POST', body }), value);
		expect(answer.status).toBe(202);
		expect(noticed).toEqual([{ run: 7, repository: 'canmi21/web' }]);
	});

	it('refuse a notice that is not a run and a repository', async () => {
		const { noticed, value } = routes();
		const bodies = ['nonsense', '{"run":"7","repository":"a/b"}', '{"run":7,"repository":"a"}'];
		const answers = await Promise.all(
			bodies.map((body) => handle(request('/notice', { method: 'POST', body }), value)),
		);
		expect(answers.map((answer) => answer.status)).toEqual([400, 400, 400]);
		expect(noticed).toEqual([]);
	});

	it('read the deploys with either token, and with no token refuse', async () => {
		const { asked, value } = routes();
		expect((await handle(request('/api/deploys'), value)).status).toBe(401);
		expect((await handle(request('/api/deploys', bearer('wrong')), value)).status).toBe(401);
		const read = await handle(request('/api/deploys?limit=500&before=9', bearer('r')), value);
		expect(read.status).toBe(200);
		expect(await read.json()).toEqual({ status: 'success', data: [] });
		expect(asked).toEqual([[200, 9]]);
		expect((await handle(request('/api/deploys', bearer('w')), value)).status).toBe(200);
	});

	it('roll back with the token alone: the read token and a notice cannot', async () => {
		const { rolled, value } = routes();
		expect((await handle(rollback('r'), value)).status).toBe(403);
		expect((await handle(rollback('wrong'), value)).status).toBe(401);
		expect(rolled).toEqual([]);
		const answer = await handle(rollback('w'), value);
		expect(answer.status).toBe(202);
		expect(rolled).toEqual([{ worker: 'console', version: VERSION }]);
	});

	it('refuse a rollback of a Worker nobody owns, or to something not a version', async () => {
		const { rolled, value } = routes();
		expect((await handle(rollback('w', VERSION, 'gateway'), value)).status).toBe(404);
		expect((await handle(rollback('w', '--yes'), value)).status).toBe(400);
		expect(rolled).toEqual([]);
	});

	it('refuse every request with no token configured', async () => {
		const { value } = routes({});
		expect((await handle(request('/api/deploys', bearer('')), value)).status).toBe(401);
		expect((await handle(rollback(''), value)).status).toBe(401);
	});

	it('answer health, and nothing else', async () => {
		const { value } = routes();
		expect((await handle(request('/health'), value)).status).toBe(200);
		expect((await handle(request('/other'), value)).status).toBe(404);
	});
});
