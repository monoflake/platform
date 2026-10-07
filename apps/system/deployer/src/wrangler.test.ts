import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { relative } from 'node:path';
import { URLS } from '@monoflake/sdk';
import { describe, expect, it } from 'vitest';
import {
	NO_ENV,
	OUTPUT_FILE,
	forget,
	home,
	invocation,
	rollbackInvocation,
	versionOf,
	wranglerBin,
} from './wrangler.ts';

const CLOUDFLARE = { account: 'account', token: 'workers-token' };
const DIR = '/data/work/1/artifact';
const HOME = '/tmp/deployer-abc';

describe('the wrangler invocation', () => {
	it('deploys the artifact by its wrangler.json, with the Workers token alone', () => {
		const ran = invocation(DIR, HOME, false, CLOUDFLARE, '/bin/wrangler.js');
		expect(ran.command).toBe(process.execPath);
		expect(ran.args).toEqual([
			'/bin/wrangler.js',
			'deploy',
			'--config',
			'wrangler.json',
			'--env-file',
			`${HOME}/${NO_ENV}`,
		]);
		expect(ran.cwd).toBe(DIR);
		expect(ran.env).toEqual({
			PATH: expect.any(String),
			HOME,
			XDG_CONFIG_HOME: `${HOME}/.config`,
			CI: 'true',
			WRANGLER_SEND_METRICS: 'false',
			WRANGLER_OUTPUT_FILE_PATH: `${HOME}/${OUTPUT_FILE}`,
			CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV: 'false',
			CLOUDFLARE_API_BASE_URL: URLS.external.cloudflare.api,
			CLOUDFLARE_API_TOKEN: 'workers-token',
			CLOUDFLARE_ACCOUNT_ID: 'account',
		});
	});

	it('keeps HOME and its configuration outside the artifact', () => {
		const ran = invocation(DIR, HOME, false, CLOUDFLARE, '/bin/wrangler.js');
		for (const path of [ran.env.HOME, ran.env.XDG_CONFIG_HOME, ran.env.WRANGLER_OUTPUT_FILE_PATH]) {
			expect(relative(DIR, path!).startsWith('..')).toBe(true);
		}
	});

	it('runs dry with no credential at all', () => {
		const ran = invocation(DIR, HOME, true, CLOUDFLARE, '/bin/wrangler.js');
		expect(ran.args.at(-1)).toBe('--dry-run');
		expect(ran.env.CLOUDFLARE_API_TOKEN).toBeUndefined();
		expect(ran.env.CLOUDFLARE_ACCOUNT_ID).toBeUndefined();
	});

	it('refuses to deploy without both the account and the token', () => {
		expect(() => invocation(DIR, HOME, false, { account: 'a' }, '/bin/wrangler.js')).toThrow(
			/CLOUDFLARE_WORKERS_TOKEN/,
		);
	});

	it('rolls back by name and version, from inside its own home', () => {
		const version = '0b7c2f1e-6c3a-4a7e-9b0d-1f2e3d4c5b6a';
		const ran = rollbackInvocation('console', version, HOME, CLOUDFLARE, '/bin/wrangler.js');
		expect(ran.args.slice(1, 5)).toEqual(['rollback', version, '--name', 'console']);
		expect(ran.args).toContain('--yes');
		expect(ran.cwd).toBe(HOME);
		expect(ran.env.CLOUDFLARE_API_TOKEN).toBe('workers-token');
	});

	it('makes a private home with an empty env file, and forgets it', async () => {
		const made = await home();
		expect(readFileSync(`${made}/${NO_ENV}`, 'utf8')).toBe('');
		expect(readdirSync(made)).toHaveLength(2);
		await forget(made);
		expect(existsSync(made)).toBe(false);
	});

	it('finds the wrangler this package pins', () => {
		expect(existsSync(wranglerBin())).toBe(true);
	});
});

describe('versionOf', () => {
	const id = '0b7c2f1e-6c3a-4a7e-9b0d-1f2e3d4c5b6a';

	it("reads the deploy entry wrangler's output file holds", () => {
		const lines = [
			JSON.stringify({ type: 'wrangler-session', version: 1 }),
			JSON.stringify({ type: 'deploy', version: 1, worker_name: 'console', version_id: id }),
			'',
		].join('\n');
		expect(versionOf('', lines)).toBe(id);
	});

	it('falls back on the line wrangler prints', () => {
		expect(versionOf(`Deployed console\nCurrent Version ID: ${id}\n`, '')).toBe(id);
		expect(versionOf('--dry-run: exiting now.', '')).toBeNull();
	});
});
