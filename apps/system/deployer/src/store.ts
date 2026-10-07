/**
 * Every deploy, one row each, moving through its stages as it happens, as host keeps its history:
 * a finished row keeps where it failed, and nothing is pruned. See spec/architecture/deployer.md,
 * "What it refuses", and infra's spec/architecture/host.md, "What host keeps, and where".
 */
import { DatabaseSync } from 'node:sqlite';

export type Stage =
	| 'downloading'
	| 'admitting'
	| 'uploading'
	| 'deployed'
	| 'failed'
	// Left alone on purpose, as host's skipped rows are: nothing went wrong, and `error` says why.
	| 'skipped';

/** A deploy from a run, or a rollback the operator asked for, which has no run. */
export type Action = 'deploy' | 'rollback';

/** A row as `/api/deploys` answers it. */
export interface Deploy {
	readonly id: number;
	readonly action: Action;
	readonly worker: string;
	readonly repository: string;
	readonly run: number | null;
	readonly commit: string | null;
	/** Run with `--dry-run`: recorded, and nothing deployed. */
	readonly dry: boolean;
	readonly stage: Stage;
	/** The stage a failed row was in when it failed. */
	readonly failed_in: Stage | null;
	/** The version Cloudflare returned, once deployed; for a rollback, the version asked for. */
	readonly version: string | null;
	/** Why it failed, or why it was skipped. */
	readonly error: string | null;
	/** wrangler's output, kept when it failed. */
	readonly output: string | null;
	readonly started_at: string;
	readonly finished_at: string | null;
}

const SCHEMA = `
CREATE TABLE IF NOT EXISTS deploys (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	action TEXT NOT NULL,
	worker TEXT NOT NULL,
	repository TEXT NOT NULL,
	run INTEGER,
	commit_sha TEXT,
	dry INTEGER NOT NULL,
	stage TEXT NOT NULL,
	failed_in TEXT,
	version TEXT,
	error TEXT,
	output TEXT,
	started_at TEXT NOT NULL,
	finished_at TEXT
);
`;

/** Still moving: a row in one of these when the deployer starts was left by one that stopped. */
const OPEN = ['downloading', 'admitting', 'uploading'];

interface Row {
	id: number;
	action: Action;
	worker: string;
	repository: string;
	run: number | null;
	commit_sha: string | null;
	dry: number;
	stage: Stage;
	failed_in: Stage | null;
	version: string | null;
	error: string | null;
	output: string | null;
	started_at: string;
	finished_at: string | null;
}

export class Store {
	private readonly db: DatabaseSync;
	private readonly now: () => Date;

	constructor(path: string, now: () => Date = () => new Date()) {
		this.now = now;
		this.db = new DatabaseSync(path);
		this.db.exec(SCHEMA);
		// Nothing will finish a row a stopped deployer left open, so it is closed as failed.
		const open = OPEN.map(() => '?').join(', ');
		this.db
			.prepare(
				`UPDATE deploys SET failed_in = stage, stage = 'failed', finished_at = ?,
					error = 'the deployer stopped during it' WHERE stage IN (${open})`,
			)
			.run(this.stamp(), ...OPEN);
	}

	private stamp(): string {
		return this.now().toISOString();
	}

	/** A new deploy at `downloading`, and its id. */
	open(worker: string, repository: string, run: number, commit: string | null, dry: boolean) {
		const result = this.db
			.prepare(
				`INSERT INTO deploys (action, worker, repository, run, commit_sha, dry, stage, started_at)
					VALUES ('deploy', ?, ?, ?, ?, ?, 'downloading', ?)`,
			)
			.run(worker, repository, run, commit, dry ? 1 : 0, this.stamp());
		return Number(result.lastInsertRowid);
	}

	/** A new rollback of `worker` to `version`, at `uploading` since there is nothing to fetch. */
	openRollback(worker: string, repository: string, version: string) {
		const result = this.db
			.prepare(
				`INSERT INTO deploys (action, worker, repository, dry, stage, version, started_at)
					VALUES ('rollback', ?, ?, 0, 'uploading', ?, ?)`,
			)
			.run(worker, repository, version, this.stamp());
		return Number(result.lastInsertRowid);
	}

	/**
	 * The newest run that deployed `worker` for real, or none. A run is taken only when it is newer,
	 * so a notice naming an old run can never roll a Worker back; a rollback leaves this unmoved.
	 */
	lastRun(worker: string): number | null {
		const row = this.db
			.prepare(
				`SELECT MAX(run) AS run FROM deploys
					WHERE worker = ? AND action = 'deploy' AND stage = 'deployed' AND dry = 0`,
			)
			.get(worker) as { run: number | null } | undefined;
		return row?.run ?? null;
	}

	advance(id: number, stage: 'admitting' | 'uploading'): void {
		this.db.prepare('UPDATE deploys SET stage = ? WHERE id = ?').run(stage, id);
	}

	deployed(id: number, version: string | null): void {
		this.db
			.prepare(
				`UPDATE deploys SET stage = 'deployed', version = COALESCE(?, version), finished_at = ?
					WHERE id = ?`,
			)
			.run(version, this.stamp(), id);
	}

	/** Close a row as left alone, with why: a Worker nobody owns, which is not a refusal. */
	skipped(id: number, reason: string): void {
		this.db
			.prepare(`UPDATE deploys SET stage = 'skipped', error = ?, finished_at = ? WHERE id = ?`)
			.run(reason, this.stamp(), id);
	}

	failed(id: number, error: string, output: string | null = null): void {
		this.db
			.prepare(
				`UPDATE deploys SET failed_in = stage, stage = 'failed', error = ?, output = ?,
					finished_at = ? WHERE id = ?`,
			)
			.run(error, output, this.stamp(), id);
	}

	/** Up to `limit` rows, the newest first, from before `before` when it is given. */
	list(limit = 50, before?: number): Deploy[] {
		const rows = this.db
			.prepare(`SELECT * FROM deploys WHERE (? IS NULL OR id < ?) ORDER BY id DESC LIMIT ?`)
			.all(before ?? null, before ?? null, limit) as unknown as Row[];
		return rows.map((row) => ({
			id: row.id,
			action: row.action,
			worker: row.worker,
			repository: row.repository,
			run: row.run,
			commit: row.commit_sha,
			dry: row.dry === 1,
			stage: row.stage,
			failed_in: row.failed_in,
			version: row.version,
			error: row.error,
			output: row.output,
			started_at: row.started_at,
			finished_at: row.finished_at,
		}));
	}

	close(): void {
		this.db.close();
	}
}
