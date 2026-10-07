import { existsSync } from 'node:fs';
import { mkdtemp, readdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import { describe, expect, it } from 'vitest';
import { configOf } from './config.ts';
import { Deployer } from './deploy.ts';
import { type Item, PACKAGED, zipOf } from './fixtures.ts';
import { type Artifact, Refused } from './github.ts';
import { Store } from './store.ts';
import type { Invocation, Runner } from './wrangler.ts';

const ID = '0b7c2f1e-6c3a-4a7e-9b0d-1f2e3d4c5b6a';
const ARTIFACT: Artifact = { app: 'console', id: 1, digest: 'sha256:00' };

/** A wrangler.json as .mise/tasks/worker writes it. */
function declared(extra: object = {}) {
	return {
		name: 'console',
		main: 'bundle/_worker.js',
		no_bundle: true,
		compatibility_date: '2026-07-29',
		...extra,
	};
}

/** The console's artifact, with `declaration` as its wrangler.json and `extra` entries added. */
function artifactOf(declaration: object = declared(), extra: readonly Item[] = []): Buffer {
	const rest = PACKAGED.filter((item) => item.name !== 'wrangler.json');
	return zipOf([{ name: 'wrangler.json', data: JSON.stringify(declaration) }, ...rest, ...extra]);
}

async function setup(
	options: {
		env?: Record<string, string>;
		artifacts?: Artifact[];
		wrangler?: Runner;
		zip?: Buffer;
		download?: () => Promise<void>;
	} = {},
) {
	const data = await mkdtemp(join(tmpdir(), 'deployer-'));
	const config = configOf({
		DEPLOYER_DATA: data,
		DEPLOY_SOURCES: 'canmi21/web monoflake/platform',
		WORKER_OWNERS: 'console=canmi21/web',
		WORKER_ZONES: 'canmi21/web=canmi.app',
		CLOUDFLARE_ACCOUNT_ID: 'account',
		CLOUDFLARE_WORKERS_TOKEN: 'token',
		...options.env,
	});
	const store = new Store(join(data, 'deployer.db'));
	const invoked: Invocation[] = [];
	const homes: boolean[] = [];
	const github = {
		artifacts: async () => ({ commit: 'abc', artifacts: options.artifacts ?? [ARTIFACT] }),
		download:
			options.download ??
			(async (_repository: string, _artifact: Artifact, zip: string) => {
				await writeFile(zip, options.zip ?? artifactOf());
			}),
	};
	const wrangler: Runner = async (invocation) => {
		invoked.push(invocation);
		homes.push(existsSync(invocation.env.HOME!));
		return options.wrangler
			? options.wrangler(invocation)
			: { code: 0, output: `Current Version ID: ${ID}` };
	};
	const logs: string[] = [];
	const deployer = new Deployer({
		config,
		store,
		github,
		wrangler,
		log: (line) => logs.push(line),
	});
	/** Each notice for `canmi21/web`, then wait for all of them. */
	const deliver = async (...runs: number[]) => {
		for (const run of runs) deployer.notice({ run, repository: 'canmi21/web' });
		await deployer.idle();
	};
	return { data, store, invoked, homes, logs, deployer, deliver };
}

describe('the deployer', () => {
	it('deploys each Worker a run built, and records the version', async () => {
		const { store, invoked, deliver, data } = await setup();
		await deliver(7);
		expect(invoked).toHaveLength(1);
		expect(invoked[0]!.args.slice(1, 4)).toEqual(['deploy', '--config', 'wrangler.json']);
		expect(invoked[0]!.env.CLOUDFLARE_API_TOKEN).toBe('token');
		expect(store.list()).toMatchObject([
			{ action: 'deploy', worker: 'console', run: 7, commit: 'abc', stage: 'deployed' },
		]);
		expect(store.list()[0]).toMatchObject({ version: ID, dry: false });
		// The artifact is gone once it is deployed.
		expect(await readdir(join(data, 'work'))).toEqual([]);
	});

	it('runs wrangler in the artifact with a home of its own outside it, gone afterwards', async () => {
		const { invoked, homes, deliver } = await setup();
		await deliver(7);
		const [ran] = invoked;
		expect(ran!.cwd.endsWith('/artifact')).toBe(true);
		expect(relative(ran!.cwd, ran!.env.HOME!).startsWith('..')).toBe(true);
		expect(homes).toEqual([true]);
		expect(existsSync(ran!.env.HOME!)).toBe(false);
	});

	it('takes nothing from a repository it does not deploy from', async () => {
		const { store, deployer } = await setup();
		deployer.notice({ run: 7, repository: 'stranger/repo' });
		await deployer.idle();
		expect(store.list()).toEqual([]);
	});

	it('runs dry when told, recording it and deploying nothing', async () => {
		const { store, invoked, deliver } = await setup({ env: { DRY_WORKERS: 'console' } });
		await deliver(7);
		expect(invoked[0]!.args).toContain('--dry-run');
		expect(invoked[0]!.env.CLOUDFLARE_API_TOKEN).toBeUndefined();
		expect(store.list()).toMatchObject([{ stage: 'deployed', dry: true, version: null }]);
		expect(store.lastRun('console')).toBeNull();
	});

	it('records a refusal at admitting, and never runs wrangler', async () => {
		const { store, invoked, deliver } = await setup({
			zip: artifactOf(declared({ unsafe: { bindings: [] } })),
		});
		await deliver(7);
		expect(invoked).toEqual([]);
		expect(store.list()).toMatchObject([{ stage: 'failed', failed_in: 'admitting' }]);
		expect(store.list()[0]!.error).toMatch(/`unsafe` is not a binding/);
	});

	it('refuses an artifact holding more than the packaging writes', async () => {
		const extra = [{ name: '.wrangler/deploy/config.json', data: '{}' }];
		const { store, invoked, deliver } = await setup({ zip: artifactOf(declared(), extra) });
		await deliver(7);
		expect(invoked).toEqual([]);
		expect(store.list()[0]).toMatchObject({ stage: 'failed', failed_in: 'admitting' });
		expect(store.list()[0]!.error).toMatch(/\.wrangler/);
	});

	it('skips a Worker nobody owns, recording why, and fetches nothing', async () => {
		let downloaded = false;
		const { store, invoked, deliver } = await setup({
			artifacts: [{ app: 'hook', id: 2, digest: 'sha256:00' }],
			download: async () => {
				downloaded = true;
			},
		});
		await deliver(7);
		expect([downloaded, invoked]).toEqual([false, []]);
		expect(store.list()).toMatchObject([{ worker: 'hook', stage: 'skipped', failed_in: null }]);
		expect(store.list()[0]!.error).toMatch(/no repository owns/);
		expect(store.list()[0]!.finished_at).not.toBeNull();
	});

	it("refuses a Worker another repository owns, though the run is a source's", async () => {
		const { store, invoked, deployer } = await setup();
		deployer.notice({ run: 8, repository: 'monoflake/platform' });
		await deployer.idle();
		expect(invoked).toEqual([]);
		expect(store.list()[0]).toMatchObject({ stage: 'failed', failed_in: 'admitting' });
	});

	it('records a download that does not match its digest at downloading', async () => {
		const { store, deliver } = await setup({
			download: async () => {
				throw new Refused('artifact worker-console does not match its recorded digest');
			},
		});
		await deliver(7);
		expect(store.list()[0]).toMatchObject({ stage: 'failed', failed_in: 'downloading' });
	});

	it("keeps wrangler's output when it fails, in the row and the log, redacted", async () => {
		const printed = [
			...Array.from({ length: 60 }, (_, line) => `line ${line}`),
			'\x1b[31mX\x1b[0m [ERROR] A request to the Cloudflare API (/accounts/acct-42/workers) failed.',
			'Authentication error [code: 10000] for token tok-secret',
		].join('\n');
		const { store, logs, deliver } = await setup({
			env: { CLOUDFLARE_ACCOUNT_ID: 'acct-42', CLOUDFLARE_WORKERS_TOKEN: 'tok-secret' },
			wrangler: async () => ({ code: 1, output: printed }),
		});
		await deliver(7);
		const [row] = store.list();
		expect(row).toMatchObject({ stage: 'failed', failed_in: 'uploading' });
		expect(row!.error).toMatch(/^wrangler exited with 1:\n/);
		expect(row!.error).toContain('(/accounts/[redacted]/workers) failed.');
		expect(row!.error).toContain('Authentication error [code: 10000] for token [redacted]');
		for (const kept of [row!.error!, row!.output!, logs.join('\n')]) {
			expect(kept).not.toMatch(/tok-secret|acct-42/);
			expect(kept).not.toContain(String.fromCharCode(27));
		}
		const logged = logs.find((line) => line.includes('failed in wrangler'))!;
		expect(logged.split('\n')).toHaveLength(1 + 40);
		expect(logged).not.toContain('line 0\n');
	});

	it("keeps no more than the end of a long output in the row's error", async () => {
		const { store, deliver } = await setup({
			wrangler: async () => ({ code: 1, output: `${'x'.repeat(10_000)}\nthe reason` }),
		});
		await deliver(7);
		const { error } = store.list()[0]!;
		expect(error!.length).toBeLessThan(4200);
		expect(error).toMatch(/the reason$/);
	});

	it('says so when a failing wrangler printed nothing', async () => {
		const { store, deliver } = await setup({ wrangler: async () => ({ code: 1, output: '' }) });
		await deliver(7);
		expect(store.list()[0]!.error).toBe('wrangler exited with 1, printing nothing');
	});

	it("keeps a dry run's and a rollback's output the same way", async () => {
		const { store, logs, deployer, deliver } = await setup({
			env: { DRY_WORKERS: 'console', CLOUDFLARE_ACCOUNT_ID: 'acct-42' },
			wrangler: async () => ({ code: 1, output: 'no such version for acct-42' }),
		});
		await deliver(7);
		deployer.rollback({ worker: 'console', version: ID });
		await deployer.idle();
		const [rollback, dry] = store.list();
		expect(dry!.error).toBe('wrangler exited with 1:\nno such version for [redacted]');
		expect(rollback!.error).toBe(dry!.error);
		expect(logs.some((line) => line.includes('failed to roll back'))).toBe(true);
	});

	it('deploys one Worker at a time, in the order the notices came', async () => {
		let running = 0;
		let most = 0;
		const { invoked, deliver } = await setup({
			wrangler: async () => {
				running += 1;
				most = Math.max(most, running);
				await new Promise((resolve) => setTimeout(resolve, 5));
				running -= 1;
				return { code: 0, output: '' };
			},
		});
		await deliver(1, 2, 3);
		expect(invoked).toHaveLength(3);
		expect(most).toBe(1);
	});
});

describe('a replayed notice', () => {
	it('refuses a run older than the last deployed, and records the refusal', async () => {
		const { store, invoked, deliver } = await setup();
		await deliver(9, 7);
		expect(invoked).toHaveLength(1);
		const [older, newer] = store.list();
		expect(newer).toMatchObject({ run: 9, stage: 'deployed' });
		expect(older).toMatchObject({ run: 7, stage: 'failed', failed_in: 'admitting' });
		expect(older!.error).toMatch(/not newer than run 9/);
		expect(store.lastRun('console')).toBe(9);
	});

	it('refuses the same run again', async () => {
		const { store, invoked, deliver } = await setup();
		await deliver(9, 9);
		expect(invoked).toHaveLength(1);
		expect(store.list()[0]).toMatchObject({ run: 9, stage: 'failed' });
	});

	it('takes a newer run', async () => {
		const { store, invoked, deliver } = await setup();
		await deliver(9, 10);
		expect(invoked).toHaveLength(2);
		expect(store.list().map((row) => [row.run, row.stage])).toEqual([
			[10, 'deployed'],
			[9, 'deployed'],
		]);
		expect(store.lastRun('console')).toBe(10);
	});

	it('takes a run again whose deploy failed', async () => {
		let first = true;
		const { store, deliver } = await setup({
			wrangler: async () => {
				const code = first ? 1 : 0;
				first = false;
				return { code, output: '' };
			},
		});
		await deliver(9, 9);
		expect(store.list().map((row) => row.stage)).toEqual(['deployed', 'failed']);
	});
});

describe('a rollback', () => {
	it('runs wrangler rollback, recorded, and leaves the last deployed run where it was', async () => {
		const { store, invoked, deployer, deliver } = await setup();
		await deliver(9);
		deployer.rollback({ worker: 'console', version: ID });
		await deployer.idle();
		expect(invoked[1]!.args.slice(1, 5)).toEqual(['rollback', ID, '--name', 'console']);
		expect(store.list()[0]).toMatchObject({
			action: 'rollback',
			worker: 'console',
			repository: 'canmi21/web',
			run: null,
			stage: 'deployed',
			version: ID,
		});
		expect(store.lastRun('console')).toBe(9);
	});
});
