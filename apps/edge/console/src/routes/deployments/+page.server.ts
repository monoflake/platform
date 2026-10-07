import { ALL } from '#lib/server/fleet.js';
import { edgeOf } from '#lib/server/platform.js';
import { cluster } from '#lib/server/read.js';
import { aggregates, runs } from '#lib/server/runs.js';
import type { PageServerLoad } from './$types';

/** The span the chart and the tiles read, in days. */
const DAYS = 30;

/** The runs streamed, so the page stands at once; see spec/architecture/console.md. */
export const load: PageServerLoad = (event) => {
	const edge = edgeOf(event);
	const now = Date.now();
	return {
		cluster: cluster(edge),
		nodes: ALL,
		days: DAYS,
		now,
		runs: runs(edge).then((read) => ({
			...read,
			aggregates: aggregates(
				read.runs.filter((run) => now - Date.parse(run.first_start) < DAYS * 86_400_000),
			),
		})),
	};
};
