import { error } from '@sveltejs/kit';
import { ALL, fleetEvents } from '#lib/server/fleet.js';
import { edgeOf } from '#lib/server/platform.js';
import { cluster } from '#lib/server/read.js';
import { group } from '#lib/server/runs.js';
import type { PageServerLoad } from './$types';

/** As `runs()` asks: every node's last 500 events, the most host answers for at once. */
const LIMIT = 500 * ALL.length;

export const load: PageServerLoad = async (event) => {
	const run = Number(event.params.run);
	if (!Number.isSafeInteger(run) || run <= 0) error(404, `No run is numbered ${event.params.run}.`);
	const edge = edgeOf(event);
	const [read, held] = await Promise.all([fleetEvents(edge, { limit: LIMIT }), cluster(edge)]);
	const events = read.events.filter(({ source }) => source.kind === 'run' && source.run === run);
	return {
		cluster: held,
		run,
		found: group(events).runs[0],
		events,
		failures: read.failures,
		nodes: ALL,
		now: Date.now(),
	};
};
