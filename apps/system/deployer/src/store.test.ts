import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { Store } from './store.ts';

function path(): string {
	return join(mkdtempSync(join(tmpdir(), 'deployer-')), 'deployer.db');
}

const NOW = () => new Date('2026-10-06T12:00:00Z');

describe('the records', () => {
	it('move one row through its stages to deployed, with the version', () => {
		const store = new Store(path(), NOW);
		const id = store.open('console', 'canmi21/web', 7, 'abc', false);
		expect(store.list()[0]).toMatchObject({ id, stage: 'downloading', finished_at: null });
		store.advance(id, 'admitting');
		expect(store.list()[0]!.stage).toBe('admitting');
		store.advance(id, 'uploading');
		store.deployed(id, 'v-1');
		expect(store.list()).toEqual([
			{
				id,
				action: 'deploy',
				worker: 'console',
				repository: 'canmi21/web',
				run: 7,
				commit: 'abc',
				dry: false,
				stage: 'deployed',
				failed_in: null,
				version: 'v-1',
				error: null,
				output: null,
				started_at: '2026-10-06T12:00:00.000Z',
				finished_at: '2026-10-06T12:00:00.000Z',
			},
		]);
	});

	it('keep the stage a failed row failed in, its error and the output', () => {
		const store = new Store(path(), NOW);
		const id = store.open('console', 'canmi21/web', 7, null, true);
		store.advance(id, 'admitting');
		store.advance(id, 'uploading');
		store.failed(id, 'wrangler exited with 1', 'the output');
		expect(store.list()[0]).toMatchObject({
			dry: true,
			stage: 'failed',
			failed_in: 'uploading',
			error: 'wrangler exited with 1',
			output: 'the output',
		});
	});

	it('close a row a stopped deployer left open, as failed where it was', () => {
		const at = path();
		const first = new Store(at, NOW);
		const id = first.open('console', 'canmi21/web', 7, null, false);
		first.advance(id, 'admitting');
		const done = first.open('hook', 'monoflake/platform', 8, null, false);
		first.deployed(done, 'v');
		first.close();
		const again = new Store(at, NOW);
		const rows = again.list();
		expect(rows.find((row) => row.id === id)).toMatchObject({
			stage: 'failed',
			failed_in: 'admitting',
		});
		expect(rows.find((row) => row.id === done)!.stage).toBe('deployed');
	});

	it('know the newest run that deployed a Worker for real, never a dry one or a failure', () => {
		const store = new Store(path(), NOW);
		expect(store.lastRun('console')).toBeNull();
		store.deployed(store.open('console', 'canmi21/web', 7, null, false), 'v');
		store.deployed(store.open('console', 'canmi21/web', 12, null, true), null);
		store.failed(store.open('console', 'canmi21/web', 11, null, false), 'no');
		store.deployed(store.open('hook', 'monoflake/platform', 20, null, false), 'v');
		expect(store.lastRun('console')).toBe(7);
		store.deployed(store.openRollback('console', 'canmi21/web', 'v0'), null);
		expect(store.lastRun('console')).toBe(7);
		expect(store.list()[0]).toMatchObject({ action: 'rollback', run: null, version: 'v0' });
	});

	it('page the newest first', () => {
		const store = new Store(path(), NOW);
		const ids = [1, 2, 3].map((run) => store.open('hook', 'monoflake/platform', run, null, false));
		expect(store.list().map((row) => row.id)).toEqual(ids.toReversed());
		expect(store.list(1).map((row) => row.id)).toEqual([ids[2]]);
		expect(store.list(50, ids[2]).map((row) => row.id)).toEqual([ids[1], ids[0]]);
	});
});
