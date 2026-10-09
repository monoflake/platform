import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { tokenFor } from './config.ts';
import { GitHub, Refused, type Run, Unread, WORKFLOW, appOf, check } from './github.ts';

function run(overrides: Partial<Run> = {}): Run {
	return {
		repository: { full_name: 'monoflake/platform' },
		path: WORKFLOW,
		head_branch: 'main',
		event: 'push',
		status: 'completed',
		conclusion: 'success',
		...overrides,
	};
}

function refused(record: Run) {
	return () => check(1, record, 'monoflake/platform');
}

describe('check', () => {
	it('takes a successful deploy run on main', () => {
		expect(() => check(1, run(), 'monoflake/platform')).not.toThrow();
		for (const event of ['schedule', 'workflow_dispatch']) {
			expect(() => check(1, run({ event }), 'monoflake/platform')).not.toThrow();
		}
	});

	it('refuses anything else', () => {
		expect(refused(run({ repository: { full_name: 'else/platform' } }))).toThrow(Refused);
		expect(refused(run({ path: '.github/workflows/other.yml' }))).toThrow(Refused);
		expect(refused(run({ head_branch: 'feature' }))).toThrow(Refused);
		expect(refused(run({ head_branch: null }))).toThrow(Refused);
		expect(refused(run({ event: 'pull_request' }))).toThrow(Refused);
		expect(refused(run({ status: 'in_progress', conclusion: null }))).toThrow(Refused);
		expect(refused(run({ conclusion: 'failure' }))).toThrow(Refused);
	});
});

describe('appOf', () => {
	it('takes `worker-` names whose rest could be an app', () => {
		expect(appOf('worker-console')).toBe('console');
		expect(appOf('worker-my-app')).toBe('my-app');
	});

	it("leaves host's artifacts and anything that could reach a path", () => {
		expect(appOf('deploy-console-arm64')).toBeUndefined();
		expect(appOf('worker-')).toBeUndefined();
		expect(appOf('worker-../../etc')).toBeUndefined();
		expect(appOf('worker-Console')).toBeUndefined();
		expect(appOf('worker--x')).toBeUndefined();
	});
});

/** GitHub as the deployer asks it, answering from `routes` by URL and recording each request. */
function github(routes: Record<string, () => Response>, token = 'secret') {
	const asked: { url: string; authorization: string | null }[] = [];
	const fetch = async (url: string, init?: RequestInit) => {
		asked.push({ url, authorization: new Headers(init?.headers).get('authorization') });
		const route = Object.entries(routes).find(([suffix]) => url.endsWith(suffix));
		return route ? route[1]() : new Response(null, { status: 404 });
	};
	return { asked, client: new GitHub(() => token, fetch) };
}

describe('GitHub', () => {
	const zip = Buffer.from('the artifact');
	const digest = `sha256:${createHash('sha256').update(zip).digest('hex')}`;

	it("lists a checked run's Worker artifacts alone", async () => {
		const { client } = github({
			'/actions/runs/7': () => Response.json({ ...run(), head_sha: 'abc' }),
			'/actions/runs/7/artifacts?per_page=100': () =>
				Response.json({
					artifacts: [
						{ id: 1, name: 'worker-console', expired: false, digest },
						{ id: 2, name: 'deploy-console-arm64', expired: false, digest },
						{ id: 3, name: 'worker-old', expired: true, digest },
						{ id: 4, name: 'worker-nodigest', expired: false, digest: null },
					],
				}),
		});
		const built = await client.artifacts('monoflake/platform', 7);
		expect(built).toEqual({ commit: 'abc', artifacts: [{ app: 'console', id: 1, digest }] });
	});

	it('refuses a run that is not one to deploy before listing anything', async () => {
		const { asked, client } = github({
			'/actions/runs/7': () => Response.json(run({ conclusion: 'failure' })),
		});
		await expect(client.artifacts('monoflake/platform', 7)).rejects.toThrow(Refused);
		expect(asked).toHaveLength(1);
	});

	it('refuses a repository it holds no token for', async () => {
		const { asked, client } = github({}, '');
		await expect(client.artifacts('canmi21/web', 7)).rejects.toThrow(/no GitHub token/);
		expect(asked).toHaveLength(0);
	});

	it('downloads from storage without the token, and holds the zip to its digest', async () => {
		const storage = 'https://storage.example/zip';
		const { asked, client } = github({
			'/actions/artifacts/1/zip': () =>
				new Response(null, { status: 302, headers: { location: storage } }),
			'/zip': () => new Response(zip),
		});
		const path = join(mkdtempSync(join(tmpdir(), 'deployer-')), 'a.zip');
		await client.download('monoflake/platform', 7, { app: 'console', id: 1, digest }, path);
		expect(readFileSync(path)).toEqual(zip);
		expect(asked[0]!.authorization).toBe('Bearer secret');
		expect(asked[1]).toEqual({ url: storage, authorization: null });

		const wrong = { app: 'console', id: 1, digest: `sha256:${'0'.repeat(64)}` };
		await expect(client.download('monoflake/platform', 7, wrong, path)).rejects.toThrow(/digest/);
	});

	it('names what it asked for, what GitHub answered, and where a refused token is', async () => {
		const env = { GITHUB_ACTIONS_TOKEN: 't' };
		const reason = async (answer: Response) => {
			const fetch = async () => answer;
			const client = new GitHub((repository) => tokenFor(repository, env), fetch);
			const failed = client.artifacts('monoflake/platform', 7);
			await expect(failed).rejects.toThrow(Unread);
			return failed.catch((error: Error) => error.message);
		};
		const of = 'GitHub answered 403 for run 7 of monoflake/platform';
		expect(await reason(new Response(null, { status: 403 }))).toBe(
			`${of}: GITHUB_ACTIONS_TOKEN, the token for monoflake, was refused`,
		);
		const spent = { status: 403, headers: { 'x-ratelimit-remaining': '0' } };
		expect(await reason(new Response(null, spent))).toBe(
			`${of}: the rate limit of GITHUB_ACTIONS_TOKEN is spent`,
		);
		expect(await reason(new Response(null, { status: 404 }))).toBe(
			`${of.replace('403', '404')}: it is gone, or GITHUB_ACTIONS_TOKEN may not read it`,
		);
		expect(await reason(new Response(null, { status: 502 }))).toBe(
			'GitHub answered 502 for run 7 of monoflake/platform',
		);
		expect(await reason(new Response('<html>'))).toMatch(
			/^GitHub's answer for run 7 of monoflake\/platform could not be read: /,
		);
	});

	it('names the storage that failed a download', async () => {
		const { client } = github({
			'/actions/artifacts/1/zip': () =>
				new Response(null, { status: 302, headers: { location: 'https://storage.example/zip' } }),
			'/zip': () => new Response(null, { status: 503 }),
		});
		const artifact = { app: 'console', id: 1, digest };
		const failed = client.download('monoflake/platform', 7, artifact, '/x');
		await expect(failed).rejects.toThrow(
			'storage answered 503 for artifact worker-console of run 7 of monoflake/platform',
		);
	});
});
