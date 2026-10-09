/**
 * What CI built, fetched: a run held to what a deploy requires, and its `worker-` artifacts
 * downloaded and held to the digest GitHub recorded. The notice that names a run is a hint; this is
 * where it becomes a decision. Ported from infra's libs/deploy/src/github.rs. See
 * spec/architecture/deployer.md, "One deployer, on one node".
 */
import { createHash } from 'node:crypto';
import { createWriteStream } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import type { ReadableStream } from 'node:stream/web';
import { URLS } from '@monoflake/sdk';
import { tokenVariable } from './config.ts';

/** The workflow that builds what is deployed; a run of any other builds nothing to deploy. */
export const WORKFLOW = '.github/workflows/deploy.yml';
/** What may have started it. A pull request never does, and would not count if it did. */
const EVENTS = new Set(['push', 'schedule', 'workflow_dispatch']);
/** How an artifact carrying a Worker is named: `worker-console`. host takes `deploy-` alone. */
const PREFIX = 'worker-';

/** A run, an artifact or a Worker the deployer will not deploy, and why. */
export class Refused extends Error {
	override name = 'Refused';
}

/**
 * What the deployer asked GitHub for and did not get, said as an operator acts on it: which run of
 * which repository, what was answered, and for a refused token, the variable it is read from.
 */
export class Unread extends Error {
	override name = 'Unread';
}

/** The fields of GitHub's run record a deploy is decided on. */
export interface Run {
	readonly repository: { readonly full_name: string };
	readonly path: string;
	readonly head_branch: string | null;
	readonly event: string;
	readonly status: string;
	readonly conclusion: string | null;
	readonly head_sha?: string | null;
}

/** One Worker as a run left it. */
export interface Artifact {
	readonly app: string;
	readonly id: number;
	readonly digest: string;
}

/** Throws unless `record` is a finished, successful run of `repository`'s deploy.yml on `main`. */
export function check(run: number, record: Run, repository: string): void {
	const refuse = (why: string) => {
		throw new Refused(`run ${run} is not one to deploy: ${why}`);
	};
	if (record.repository.full_name !== repository) {
		refuse(`it belongs to ${record.repository.full_name}`);
	}
	if (record.path !== WORKFLOW) refuse(`it ran ${record.path}`);
	if (record.head_branch !== 'main') refuse(`it ran on ${record.head_branch}`);
	if (!EVENTS.has(record.event)) refuse(`a ${record.event} started it`);
	if (record.status !== 'completed' || record.conclusion !== 'success') {
		refuse(`it is ${record.status} with ${record.conclusion}`);
	}
}

/** A DNS label, as every app name is; see infra's spec/architecture/host.md. */
function isLabel(name: string): boolean {
	return name.length <= 63 && /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(name);
}

/**
 * The app a `worker-<app>` artifact name carries, when the name could be an app's. The name is
 * GitHub's answer, not this repository's, so it is held to the rule before it reaches a path.
 */
export function appOf(artifact: string): string | undefined {
	if (!artifact.startsWith(PREFIX)) return undefined;
	const app = artifact.slice(PREFIX.length);
	return isLabel(app) ? app : undefined;
}

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

/** An error and what it was caused by, as fetch throws `fetch failed` over the reason. */
function causeOf(error: unknown): string {
	if (!(error instanceof Error)) return String(error);
	return error.cause instanceof Error ? `${error.message}: ${error.cause.message}` : error.message;
}

interface Listed {
	readonly artifacts: readonly {
		readonly id: number;
		readonly name: string;
		readonly expired: boolean;
		readonly digest: string | null;
	}[];
}

export class GitHub {
	/** The token for a repository, picked by its owner; see config.ts, `tokenFor`. */
	private readonly tokenOf: (repository: string) => string | undefined;
	private readonly fetch: Fetch;

	constructor(
		tokenOf: (repository: string) => string | undefined,
		fetch: Fetch = globalThis.fetch,
	) {
		this.tokenOf = tokenOf;
		this.fetch = fetch;
	}

	/** A GET for `what`, with the token only when it is GitHub's own API being asked. */
	private async get(url: string, what: string, token?: string): Promise<Response> {
		const headers: Record<string, string> = {
			'user-agent': 'monoflake-deployer',
			accept: 'application/vnd.github+json',
			'x-github-api-version': '2022-11-28',
		};
		if (token) headers.authorization = `Bearer ${token}`;
		try {
			return await this.fetch(url, { headers, redirect: 'manual' });
		} catch (error) {
			const who = token ? 'GitHub' : 'storage';
			throw new Unread(`${who} could not be reached for ${what}: ${causeOf(error)}`);
		}
	}

	private token(repository: string): string {
		const token = this.tokenOf(repository);
		if (token) return token;
		const variable = tokenVariable(repository);
		const why = variable ? `${variable} is not set` : 'its owner names no variable';
		throw new Unread(`no GitHub token reads ${repository}: ${why}`);
	}

	/** Why `answer` is not `what` was asked for: the token named by its variable, never itself. */
	private unread(repository: string, what: string, answer: Response): Unread {
		const variable = tokenVariable(repository);
		const owner = repository.split('/')[0];
		let why = '';
		if (answer.headers.get('x-ratelimit-remaining') === '0') {
			why = `: the rate limit of ${variable} is spent`;
		} else if (answer.status === 401 || answer.status === 403) {
			why = `: ${variable}, the token for ${owner}, was refused`;
		} else if (answer.status === 404) {
			// GitHub answers 404, not 403, for a repository the token may not see.
			why = `: it is gone, or ${variable} may not read it`;
		}
		return new Unread(`GitHub answered ${answer.status} for ${what}${why}`);
	}

	private async json<T>(repository: string, path: string, what: string): Promise<T> {
		const url = `${URLS.external.github.api}/repos/${repository}${path}`;
		const answer = await this.get(url, what, this.token(repository));
		if (!answer.ok) throw this.unread(repository, what, answer);
		try {
			return (await answer.json()) as T;
		} catch (error) {
			throw new Unread(`GitHub's answer for ${what} could not be read: ${causeOf(error)}`);
		}
	}

	/** The `worker-` artifacts of `repository`'s `run`, once its record says it is one to deploy. */
	async artifacts(
		repository: string,
		run: number,
	): Promise<{ commit: string | null; artifacts: Artifact[] }> {
		const of = `run ${run} of ${repository}`;
		const record = await this.json<Run>(repository, `/actions/runs/${run}`, of);
		check(run, record, repository);
		const listed = await this.json<Listed>(
			repository,
			`/actions/runs/${run}/artifacts?per_page=100`,
			`the artifacts of ${of}`,
		);
		const artifacts = listed.artifacts.flatMap((artifact) => {
			const app = appOf(artifact.name);
			if (app === undefined || artifact.expired || !artifact.digest) return [];
			return [{ app, id: artifact.id, digest: artifact.digest }];
		});
		return { commit: record.head_sha ?? null, artifacts };
	}

	/** Download `artifact` of `run` to `zip`, held to its digest; the file is left either way. */
	async download(repository: string, run: number, artifact: Artifact, zip: string): Promise<void> {
		const url = `${URLS.external.github.api}/repos/${repository}/actions/artifacts/${artifact.id}/zip`;
		const what = `artifact worker-${artifact.app} of run ${run} of ${repository}`;
		// GitHub answers with a redirect to storage, which is signed and must not be sent the token.
		const redirect = await this.get(url, what, this.token(repository));
		const location = redirect.headers.get('location');
		if (!location) throw this.unread(repository, what, redirect);
		const answer = await this.get(location, what);
		if (!answer.ok || !answer.body) {
			throw new Unread(`storage answered ${answer.status} for ${what}`);
		}
		const hash = createHash('sha256');
		const body = Readable.fromWeb(answer.body as ReadableStream<Uint8Array>);
		body.on('data', (chunk: Buffer) => hash.update(chunk));
		await pipeline(body, createWriteStream(zip));
		// GitHub's digest is the SHA-256 of the zip as downloaded, as infra's github.rs measured.
		const digest = `sha256:${hash.digest('hex')}`;
		if (digest.toLowerCase() !== artifact.digest.toLowerCase()) {
			throw new Refused(`artifact worker-${artifact.app} does not match its recorded digest`);
		}
	}
}
