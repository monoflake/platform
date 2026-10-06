import { ALL } from '#lib/server/fleet.js';
import { edgeOf } from '#lib/server/platform.js';
import { cluster } from '#lib/server/read.js';
import { aggregates, runs } from '#lib/server/runs.js';
import type { PageServerLoad } from './$types';

/** The span the chart and the tiles read, in days. */
const DAYS = 30;

export const load: PageServerLoad = async (event) => {
	const edge = edgeOf(event);
	const [read, held] = await Promise.all([runs(edge), cluster(edge)]);
	const now = Date.now();
	const month = read.runs.filter((run) => now - Date.parse(run.first_start) < DAYS * 86_400_000);
	return { cluster: held, ...read, nodes: ALL, aggregates: aggregates(month), days: DAYS, now };
};
