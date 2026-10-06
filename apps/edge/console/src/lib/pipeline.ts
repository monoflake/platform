/**
 * Every node's events, put together by the CI run they came from: per run, one row per app and in
 * it where each node is. What no run started -- an upload, the panel -- is listed apart. See
 * spec/architecture/console.md, "The pipeline".
 */
import type { Event, Held } from './wire.ts';

/** Where one node is with one app of one run: its newest event for it. */
export interface Cell {
	node: string;
	event: Event;
}

export interface Row {
	app: string;
	/** By node; a node with no event for this app in this run is absent. */
	cells: Record<string, Cell>;
}

export interface Run {
	run: number;
	commit?: string;
	/** The latest any node started on it. */
	started_at: string;
	/** By app name. */
	rows: Row[];
	/** Running while any node is; else failed where any failed; else done. */
	state: 'running' | 'failed' | 'done';
}

export interface Apart {
	node: string;
	event: Event;
}

export interface Pipeline {
	/** Newest first, by run number. */
	runs: Run[];
	/** Newest first. */
	apart: Apart[];
}

export function pipeline(nodes: Readonly<Record<string, Held>>): Pipeline {
	const runs = new Map<number, { commit?: string; started_at: string; rows: Map<string, Row> }>();
	const apart: Apart[] = [];

	for (const [node, held] of Object.entries(nodes)) {
		for (const event of held.snapshot.events) {
			const number = event.source.kind === 'run' ? event.source.run : undefined;
			if (number === undefined) {
				apart.push({ node, event });
				continue;
			}
			let run = runs.get(number);
			if (!run) {
				run = { started_at: event.started_at, rows: new Map() };
				runs.set(number, run);
			}
			run.commit ??= event.source.commit;
			if (later(event.started_at, run.started_at)) run.started_at = event.started_at;
			let row = run.rows.get(event.app);
			if (!row) {
				row = { app: event.app, cells: {} };
				run.rows.set(event.app, row);
			}
			// A node's ids climb as it records, so the higher is the newer on that node.
			const kept = row.cells[node];
			if (!kept || kept.event.id < event.id) row.cells[node] = { node, event };
		}
	}

	return {
		runs: [...runs.entries()]
			.map(([run, { commit, started_at, rows }]) => {
				const sorted = [...rows.values()].toSorted((a, b) => a.app.localeCompare(b.app));
				return { run, commit, started_at, rows: sorted, state: stateOf(sorted) };
			})
			.toSorted((a, b) => b.run - a.run),
		apart: apart.toSorted(
			(a, b) => Date.parse(b.event.started_at) - Date.parse(a.event.started_at),
		),
	};
}

function stateOf(rows: Row[]): Run['state'] {
	const outcomes = rows.flatMap((row) =>
		Object.values(row.cells).map((cell) => cell.event.outcome),
	);
	if (outcomes.includes('running')) return 'running';
	if (outcomes.includes('failed')) return 'failed';
	return 'done';
}

function later(a: string, b: string): boolean {
	return Date.parse(a) > Date.parse(b);
}
