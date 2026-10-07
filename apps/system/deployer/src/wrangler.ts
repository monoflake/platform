/**
 * wrangler, run with nothing but what a deploy needs: the account, the Workers token, the API it
 * may call, and a home of its own outside the artifact, so nothing an artifact carries can stand
 * in for its configuration. Dry, it gets no token at all. See spec/architecture/deployer.md, "What
 * a Worker artifact is", for why wrangler rather than the API.
 */
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { URLS } from '@monoflake/sdk';

/** One wrangler run, as a program and its arguments, before it is started. */
export interface Invocation {
	readonly command: string;
	readonly args: readonly string[];
	readonly cwd: string;
	readonly env: Readonly<Record<string, string>>;
}

/** What a run ended with: its exit code and everything it printed, both streams together. */
export interface Ran {
	readonly code: number;
	readonly output: string;
}

export type Runner = (invocation: Invocation) => Promise<Ran>;

export interface Cloudflare {
	readonly account?: string;
	readonly token?: string;
}

/** Where wrangler writes what it did as JSON lines, in its own home. */
export const OUTPUT_FILE = 'output.jsonl';
/** An empty file handed to `--env-file`, so wrangler reads no `.env` from where it runs. */
export const NO_ENV = 'none.env';
/** Where a rollback runs: an empty directory, since it reads no artifact. */
const NOWHERE = 'cwd';

/** wrangler's own entry, from the package this one pins; its exports name only its manifest. */
export function wranglerBin(): string {
	const manifest = createRequire(import.meta.url).resolve('wrangler/package.json');
	return join(dirname(manifest), 'bin', 'wrangler.js');
}

/** A new home for one wrangler run, private to it, outside every artifact. */
export async function home(): Promise<string> {
	const made = await mkdtemp(join(tmpdir(), 'deployer-'));
	await writeFile(join(made, NO_ENV), '');
	await mkdtemp(join(made, NOWHERE));
	return made;
}

export function forget(path: string): Promise<void> {
	return rm(path, { recursive: true, force: true });
}

/**
 * The child's whole environment, built from nothing rather than from the deployer's, which holds
 * GitHub's tokens. `.dev.vars` is never read into it and the API is pinned, whatever a file says.
 */
export function environment(homeDir: string, cloudflare?: Cloudflare): Record<string, string> {
	const env: Record<string, string> = {
		PATH: process.env.PATH ?? '/usr/local/bin:/usr/bin:/bin',
		HOME: homeDir,
		XDG_CONFIG_HOME: join(homeDir, '.config'),
		CI: 'true',
		WRANGLER_SEND_METRICS: 'false',
		WRANGLER_OUTPUT_FILE_PATH: join(homeDir, OUTPUT_FILE),
		CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV: 'false',
		CLOUDFLARE_API_BASE_URL: URLS.external.cloudflare.api,
	};
	if (cloudflare) {
		if (!cloudflare.account || !cloudflare.token) {
			throw new Error('CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_WORKERS_TOKEN are both needed');
		}
		env.CLOUDFLARE_ACCOUNT_ID = cloudflare.account;
		env.CLOUDFLARE_API_TOKEN = cloudflare.token;
	}
	return env;
}

/** `wrangler deploy --config wrangler.json` in `dir`, or `--dry-run`, which needs no credential. */
export function invocation(
	dir: string,
	homeDir: string,
	dry: boolean,
	cloudflare: Cloudflare,
	bin: string = wranglerBin(),
): Invocation {
	const args = [
		bin,
		'deploy',
		'--config',
		'wrangler.json',
		'--env-file',
		join(homeDir, NO_ENV),
		...(dry ? ['--dry-run'] : []),
	];
	const env = environment(homeDir, dry ? undefined : cloudflare);
	return { command: process.execPath, args, cwd: dir, env };
}

/** `wrangler rollback <version> --name <worker>`, from an empty directory in its own home. */
export function rollbackInvocation(
	worker: string,
	version: string,
	homeDir: string,
	cloudflare: Cloudflare,
	bin: string = wranglerBin(),
): Invocation {
	const args = [
		bin,
		'rollback',
		version,
		'--name',
		worker,
		'--message',
		'Rolled back from the deployer',
		'--yes',
		'--env-file',
		join(homeDir, NO_ENV),
	];
	return { command: process.execPath, args, cwd: homeDir, env: environment(homeDir, cloudflare) };
}

/** How long one run may take before it is stopped and recorded as failed. */
const LIMIT_MS = 10 * 60 * 1000;
/** How much of the output a row keeps: the end, where wrangler says what went wrong. */
const KEPT = 64 * 1024;

/** Start `asked` and wait for it, keeping the end of what it printed. */
export const run: Runner = (asked) =>
	new Promise((resolve) => {
		const child = spawn(asked.command, asked.args, {
			cwd: asked.cwd,
			env: asked.env,
			stdio: ['ignore', 'pipe', 'pipe'],
		});
		let output = '';
		const keep = (chunk: Buffer) => {
			output = (output + chunk.toString('utf8')).slice(-KEPT);
		};
		child.stdout.on('data', keep);
		child.stderr.on('data', keep);
		const timer = setTimeout(() => child.kill('SIGTERM'), LIMIT_MS);
		child.on('error', (error) => {
			clearTimeout(timer);
			resolve({ code: -1, output: `${output}\n${error.message}` });
		});
		child.on('close', (code) => {
			clearTimeout(timer);
			resolve({ code: code ?? -1, output });
		});
	});

/** How much of a failed run's output its row's `error` keeps, and how many lines the log does. */
const ERROR_BYTES = 4096;
const LOG_LINES = 40;

/** Terminal color and cursor codes, built from the escape so no control character is literal. */
const COLOR = new RegExp(`${String.fromCharCode(27)}\\[[0-9;]*[A-Za-z]`, 'g');

/**
 * `output` as it may be kept and shown: colors gone, and the token and account id it was run with
 * replaced wherever they appear, so a row or a log line never carries them.
 */
export function redacted(output: string, cloudflare: Cloudflare): string {
	let plain = output.replaceAll(COLOR, '');
	for (const secret of [cloudflare.token, cloudflare.account]) {
		if (secret) plain = plain.replaceAll(secret, '[redacted]');
	}
	return plain;
}

/** A failed run, as its row and the log keep it: the end of what it printed, redacted. */
export function failureOf(
	ran: Ran,
	cloudflare: Cloudflare,
): { error: string; log: string; output: string } {
	const output = redacted(ran.output, cloudflare).trimEnd();
	const end = Buffer.from(output).subarray(-ERROR_BYTES).toString('utf8');
	const said = end.length < output.length ? `...${end}` : end;
	return {
		error: `wrangler exited with ${ran.code}${said ? `:\n${said}` : ', printing nothing'}`,
		log: output.split('\n').slice(-LOG_LINES).join('\n'),
		output,
	};
}

/**
 * The version a deploy made: from wrangler's output file, its `deploy` entry's `version_id`, or
 * else the `Current Version ID` line it prints. None for a dry run, which makes none.
 */
export function versionOf(output: string, lines: string): string | null {
	for (const line of lines.split('\n').toReversed()) {
		try {
			const entry = JSON.parse(line) as { type?: string; version_id?: unknown };
			if (entry.type === 'deploy' && typeof entry.version_id === 'string') return entry.version_id;
		} catch {
			// A line that is not JSON is not an entry.
		}
	}
	return /Current Version ID:\s*([0-9a-f-]{36})/i.exec(output)?.[1] ?? null;
}

/** The output file a run in `homeDir` wrote, or nothing when it wrote none. */
export async function outputFileOf(homeDir: string): Promise<string> {
	try {
		return await readFile(join(homeDir, OUTPUT_FILE), 'utf8');
	} catch {
		return '';
	}
}
