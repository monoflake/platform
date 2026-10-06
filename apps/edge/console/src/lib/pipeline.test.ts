import { describe, expect, it } from 'vitest';
import { pipeline } from './pipeline.ts';
import type { Event, Held } from './wire.ts';

function event(id: number, app: string, fields: Partial<Event> = {}): Event {
	return {
		id,
		app,
		action: 'deploy',
		source: { kind: 'run', run: 18734, commit: '9f1c2ab' },
		outcome: 'succeeded',
		started_at: `2026-10-06T12:00:${String(id).padStart(2, '0')}Z`,
		...fields,
	};
}

function node(...events: Event[]): Held {
	return {
		version: 1,
		heard_at: '2026-10-06T12:01:00Z',
		snapshot: { taken_at: '2026-10-06T12:01:00Z', events, apps: [] },
	};
}

const older = { kind: 'run', run: 18700 };

describe('pipeline', () => {
	it('groups every node by run, newest run first, one row per app', () => {
		const { runs } = pipeline({
			tyo: node(event(3, 'geo'), event(1, 'geo', { source: older })),
			rdu: node(event(2, 'apt', { outcome: 'skipped', detail: 'Placed on tyo, not here' })),
		});
		expect(runs.map((run) => run.run)).toEqual([18734, 18700]);
		const [latest] = runs;
		expect(latest?.commit).toBe('9f1c2ab');
		expect(latest?.rows.map((row) => row.app)).toEqual(['apt', 'geo']);
		expect(Object.keys(latest?.rows[1]?.cells ?? {})).toEqual(['tyo']);
		expect(latest?.rows[0]?.cells.rdu?.event.detail).toBe('Placed on tyo, not here');
	});

	it("keeps a node's newest event for an app within a run, by its id", () => {
		const { runs } = pipeline({
			tyo: node(
				event(7, 'geo', { outcome: 'running', stage: 'loading' }),
				event(5, 'geo', { outcome: 'failed', stage: 'downloading' }),
			),
		});
		expect(runs[0]?.rows[0]?.cells.tyo?.event.stage).toBe('loading');
	});

	it('is running while any node is, failed where any failed, and done otherwise', () => {
		const run = (...events: Event[]) => pipeline({ tyo: node(...events) }).runs[0]?.state;
		expect(run(event(1, 'geo'), event(2, 'apt', { outcome: 'running', stage: 'starting' }))).toBe(
			'running',
		);
		expect(run(event(1, 'geo'), event(2, 'apt', { outcome: 'failed' }))).toBe('failed');
		expect(run(event(1, 'geo'), event(2, 'apt', { outcome: 'skipped' }))).toBe('done');
	});

	it('lists what no run started apart, newest first', () => {
		const { runs, apart } = pipeline({
			tyo: node(event(4, 'cron', { action: 'restart', source: { kind: 'panel' } })),
			rdu: node(event(9, 'geo', { source: { kind: 'upload' } }), event(8, 'apt')),
		});
		expect(apart.map(({ node, event }) => `${node}/${event.app}`)).toEqual(['rdu/geo', 'tyo/cron']);
		expect(runs.flatMap((run) => run.rows.map((row) => row.app))).toEqual(['apt']);
	});
});
