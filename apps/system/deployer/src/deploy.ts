/**
 * The deployer's one loop: a notice queued, its run checked, each `worker-` artifact downloaded,
 * admitted and handed to wrangler, one Worker at a time, every step recorded. A rollback the
 * operator asks for waits in the same queue. See spec/architecture/deployer.md.
 */
import { mkdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { admit } from './admission.ts';
import { unpack as unpackZip } from './artifact.ts';
import { type Config, isDry } from './config.ts';
import { type Artifact, type GitHub, Refused } from './github.ts';
import type { Store } from './store.ts';
import {
	type Runner,
	failureOf,
	forget,
	home,
	invocation,
	outputFileOf,
	rollbackInvocation,
	versionOf,
} from './wrangler.ts';

/** What the hook posts: a run to look at, and whose it is. Only a hint. */
export interface Notice {
	readonly run: number;
	readonly repository: string;
}

/** A Worker put back on one of its earlier versions, at the operator's word. */
export interface Rollback {
	readonly worker: string;
	readonly version: string;
}

type Work = ({ kind: 'run' } & Notice) | ({ kind: 'rollback' } & Rollback);

export type Unpack = (zip: string, directory: string) => Promise<void>;

export interface Parts {
	readonly config: Config;
	readonly store: Store;
	readonly github: Pick<GitHub, 'artifacts' | 'download'>;
	readonly wrangler: Runner;
	/** Opens an artifact once it is admitted; artifact.ts's unless a test says otherwise. */
	readonly unpack?: Unpack;
	readonly log?: (line: string) => void;
}

/**
 * The Cloudflare configuration a Worker deploys with: today the artifact's own `wrangler.json`,
 * passed through. The seam for a `[worker]` section of `service.toml`, from which the deployer will
 * write the bindings itself -- spec/architecture/deployer.md, "An app's bindings are declared to
 * the platform"; not yet built.
 */
async function workerConfigOf(unpacked: string): Promise<Record<string, unknown>> {
	return JSON.parse(await readFile(join(unpacked, 'wrangler.json'), 'utf8'));
}

function messageOf(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

export class Deployer {
	private readonly queue: Work[] = [];
	private draining: Promise<void> | undefined;
	private readonly parts: Parts;

	constructor(parts: Parts) {
		this.parts = parts;
	}

	private log(line: string): void {
		(this.parts.log ?? console.log)(`deployer: ${line}`);
	}

	private enqueue(work: Work): void {
		this.queue.push(work);
		this.draining ??= this.drain();
	}

	/** Queue `notice`, and start the loop if it is not running. Returns at once. */
	notice(notice: Notice): void {
		this.enqueue({ kind: 'run', ...notice });
	}

	/** Queue a rollback; the caller has checked the write token and that the Worker is owned. */
	rollback(rollback: Rollback): void {
		this.enqueue({ kind: 'rollback', ...rollback });
	}

	/** Resolves once the queue is empty; for a caller that has to wait, as a test does. */
	async idle(): Promise<void> {
		// oxlint-disable-next-line no-await-in-loop -- work may land while the queue drains
		while (this.draining) await this.draining;
	}

	private async drain(): Promise<void> {
		try {
			for (let next = this.queue.shift(); next; next = this.queue.shift()) {
				try {
					// oxlint-disable-next-line no-await-in-loop -- one deploy at a time, by design
					await (next.kind === 'run' ? this.take(next) : this.roll(next));
				} catch (error) {
					this.log(`${next.kind === 'run' ? `run ${next.run}` : next.worker}: ${messageOf(error)}`);
				}
			}
		} finally {
			// In the same turn as the empty queue was seen, so no notice lands between the two.
			this.draining = undefined;
		}
	}

	/** Every Worker `notice`'s run built, once the run is one of its sources' to deploy. */
	private async take({ run, repository }: Notice): Promise<void> {
		if (!this.parts.config.sources.includes(repository)) {
			this.log(`run ${run}: ${repository} is not a repository it deploys from`);
			return;
		}
		const { commit, artifacts } = await this.parts.github.artifacts(repository, run);
		if (artifacts.length === 0) this.log(`run ${run} of ${repository} built no Worker`);
		for (const artifact of artifacts) {
			// oxlint-disable-next-line no-await-in-loop -- one deploy at a time, by design
			await this.deploy(repository, run, commit, artifact);
		}
	}

	private async deploy(
		repository: string,
		run: number,
		commit: string | null,
		artifact: Artifact,
	): Promise<void> {
		const { config, store, github, wrangler } = this.parts;
		const dry = isDry(config, artifact.app);
		const id = store.open(artifact.app, repository, run, commit, dry);
		// Named by the row, so nothing GitHub answered becomes part of a path.
		const work = join(config.data, 'work', String(id));
		const unpacked = join(work, 'artifact');
		let homeDir: string | undefined;
		try {
			// A name nobody owns is one this deployer does not deploy -- `hook`, which Cloudflare's Git
			// integration keeps -- and is skipped, not refused. Owned elsewhere, admit refuses it.
			if (!config.owners.has(artifact.app)) {
				store.skipped(id, 'no repository owns this Worker, so another pipeline deploys it');
				this.log(`${artifact.app} from run ${run} is skipped: nobody owns it here`);
				return;
			}
			// Only forward: a notice naming a run no newer than the last deployed is a replay.
			const last = store.lastRun(artifact.app);
			if (last !== null && run <= last) {
				store.advance(id, 'admitting');
				throw new Refused(`run ${run} is not newer than run ${last}, which deployed it last`);
			}
			await mkdir(work, { recursive: true });
			const zip = join(work, 'artifact.zip');
			await github.download(repository, artifact, zip);

			store.advance(id, 'admitting');
			await (this.parts.unpack ?? unpackZip)(zip, unpacked);
			admit(artifact.app, repository, await workerConfigOf(unpacked), config);

			store.advance(id, 'uploading');
			homeDir = await home();
			const ran = await wrangler(invocation(unpacked, homeDir, dry, config.cloudflare));
			if (ran.code !== 0) {
				const failure = failureOf(ran, config.cloudflare);
				store.failed(id, failure.error, failure.output);
				this.log(`${artifact.app} from run ${run} failed in wrangler:\n${failure.log}`);
				return;
			}
			const version = dry ? null : versionOf(ran.output, await outputFileOf(homeDir));
			store.deployed(id, version);
			this.log(`${artifact.app} from run ${run} ${dry ? 'ran dry' : `is ${version}`}`);
		} catch (error) {
			store.failed(id, messageOf(error));
			this.log(`${artifact.app} from run ${run}: ${messageOf(error)}`);
		} finally {
			await forget(work);
			if (homeDir) await forget(homeDir);
		}
	}

	/** `wrangler rollback`, recorded as a row of its own; the last deployed run is left as it was. */
	private async roll({ worker, version }: Rollback): Promise<void> {
		const { config, store, wrangler } = this.parts;
		const id = store.openRollback(worker, config.owners.get(worker) ?? '', version);
		let homeDir: string | undefined;
		try {
			homeDir = await home();
			const ran = await wrangler(rollbackInvocation(worker, version, homeDir, config.cloudflare));
			if (ran.code !== 0) {
				const failure = failureOf(ran, config.cloudflare);
				store.failed(id, failure.error, failure.output);
				this.log(`${worker} failed to roll back in wrangler:\n${failure.log}`);
				return;
			}
			store.deployed(id, null);
			this.log(`${worker} is rolled back to ${version}`);
		} catch (error) {
			store.failed(id, messageOf(error));
		} finally {
			if (homeDir) await forget(homeDir);
		}
	}
}
