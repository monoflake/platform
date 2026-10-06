/**
 * What the events page loads. The host filters nothing and pages by event id alone, so a page is
 * loaded from every node, the most each serves, and the filters run here over what came back.
 * See spec/architecture/console.md.
 */
import { ALL, type Cursor, type FleetEvent, fan } from '#lib/server/fleet.ts';
import { events as read } from '#lib/server/reads.ts';
import type { Edge, Failure } from '#lib/server/read.ts';
import { days, hours } from './counts.ts';
import { choices, matches, pageOf, parseQuery, type Query } from './query.ts';

/** The most one node answers in a page; host's own limit. */
export const PER_NODE = 500;

interface Pool {
	events: FleetEvent[];
	failures: Record<string, Failure>;
	/** Nodes whose answer was full, so older events may remain. */
	full: string[];
}

async function pool(edge: Edge, before: Cursor): Promise<Pool> {
	const fleet = await fan((name) => {
		const at = before[name];
		return read(
			edge,
			name,
			at === undefined ? { limit: PER_NODE } : { limit: PER_NODE, before: at },
		);
	});
	const out: Pool = { events: [], failures: {}, full: [] };
	for (const name of ALL) {
		const answer = fleet[name];
		if (!answer.ok) out.failures[name] = answer.failure;
		else {
			out.events.push(...answer.data.map((event) => ({ ...event, node: name })));
			if (answer.data.length >= PER_NODE) out.full.push(name);
		}
	}
	return out;
}

export async function load(edge: Edge, params: URLSearchParams, zone: string, now = Date.now()) {
	const query: Query = parseQuery(params, ALL);
	const newest = await pool(edge, {});
	const older = Object.keys(query.before).length > 0 ? await pool(edge, query.before) : newest;
	const page = pageOf(older.events, query, ALL);
	const charted = newest.events.filter((event) => matches(event, query));
	return {
		query,
		nodes: ALL,
		events: page.events,
		next: page.next,
		more: page.more || older.full.length > 0,
		failures: { ...newest.failures, ...older.failures },
		options: {
			app: choices(newest.events, 'app', query.app),
			action: choices(newest.events, 'action', query.action),
			outcome: choices(newest.events, 'outcome', query.outcome),
			stage: choices(newest.events, 'stage', query.stage),
		},
		now,
		charts: {
			hours: hours(charted, ALL, now),
			days: days(charted, now, zone),
			covered: charted.length,
			loaded: newest.events.length,
			full: newest.full,
		},
	};
}
