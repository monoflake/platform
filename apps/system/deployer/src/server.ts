/**
 * The deployer's routes: `/notice` for the hook, open since it is only a hint; `/api/*` behind
 * host's two tokens -- the token for anything, the read token for a `GET` alone -- so a rollback is
 * the operator's act and never a notice's; and `/health` for host. See
 * spec/architecture/deployer.md, and infra's spec/architecture/host.md, "One token, behind two
 * doors".
 */
import { createHash, timingSafeEqual } from 'node:crypto';
import { failure, success } from '@canmi/response';
import type { Notice, Rollback } from './deploy.ts';
import type { Deploy } from './store.ts';

export interface Routes {
	/** `DEPLOYER_TOKEN`, which acts; none refuses every request that would. */
	readonly token: string | undefined;
	/** `DEPLOYER_READ_TOKEN`, which reads and never acts. */
	readonly readToken: string | undefined;
	/** Whether a Worker is one the deployer may act on: a name in `WORKER_OWNERS`. */
	readonly owned: (worker: string) => boolean;
	readonly notice: (notice: Notice) => void;
	readonly rollback: (rollback: Rollback) => void;
	readonly deploys: (limit: number, before?: number) => Deploy[];
}

function digest(value: string): Buffer {
	return createHash('sha256').update(value).digest();
}

/** Compared as digests, so the time taken says nothing about where two tokens differ. */
function same(given: string, expected: string | undefined): boolean {
	return expected !== undefined && timingSafeEqual(digest(given), digest(expected));
}

/** Whether `request` may go on: anything with the token, a `GET` with the read token. */
function admission(request: Request, routes: Routes): Response | undefined {
	const given = /^Bearer (.+)$/.exec(request.headers.get('authorization') ?? '')?.[1];
	if (given === undefined) return failure(401, 'invalid_token');
	if (same(given, routes.token)) return undefined;
	if (!same(given, routes.readToken)) return failure(401, 'invalid_token');
	if (request.method === 'GET') return undefined;
	return failure(403, 'invalid_token', { message: 'This token reads and does not act' });
}

function noticeOf(body: unknown): Notice | undefined {
	const { run, repository } = (body ?? {}) as Record<string, unknown>;
	if (!Number.isSafeInteger(run) || (run as number) <= 0) return undefined;
	if (typeof repository !== 'string' || !/^[\w.-]+\/[\w.-]+$/.test(repository)) return undefined;
	return { run: run as number, repository };
}

/** A whole number from `text` between 1 and `most`, or `fallback`. */
function bounded(text: string | null, most: number, fallback: number | undefined) {
	const number = Number(text);
	return text !== null && Number.isSafeInteger(number) && number > 0
		? Math.min(number, most)
		: fallback;
}

const ROLLBACK = /^\/api\/workers\/([a-z0-9-]{1,63})\/rollback$/;
const VERSION = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export async function handle(request: Request, routes: Routes): Promise<Response> {
	const url = new URL(request.url);
	if (url.pathname === '/health' && request.method === 'GET') return new Response('ok');

	// A hint, so it is taken at once and checked later against GitHub itself.
	if (url.pathname === '/notice' && request.method === 'POST') {
		const notice = noticeOf(await request.json().catch(() => undefined));
		if (!notice) return failure(400, 'invalid_body', { message: 'Expected {run, repository}' });
		routes.notice(notice);
		return success(notice, { status: 202 });
	}

	if (!url.pathname.startsWith('/api/')) return failure(404, 'no_such_route');
	const refused = admission(request, routes);
	if (refused) return refused;

	if (url.pathname === '/api/deploys' && request.method === 'GET') {
		const limit = bounded(url.searchParams.get('limit'), 200, 50) ?? 50;
		const before = bounded(url.searchParams.get('before'), Number.MAX_SAFE_INTEGER, undefined);
		return success(routes.deploys(limit, before));
	}

	const worker = ROLLBACK.exec(url.pathname)?.[1];
	if (worker !== undefined && request.method === 'POST') {
		if (!routes.owned(worker)) return failure(404, 'no_such_app');
		const { version } = ((await request.json().catch(() => undefined)) ?? {}) as {
			version?: unknown;
		};
		if (typeof version !== 'string' || !VERSION.test(version)) {
			return failure(400, 'invalid_body', { message: 'Expected {version}, a version id' });
		}
		routes.rollback({ worker, version });
		return success({ worker, version }, { status: 202 });
	}

	return failure(404, 'no_such_route');
}
