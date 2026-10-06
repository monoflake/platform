import { byNode, daily, figures, marks } from '#lib/overview/deploys.js';
import { heat, missing, perNode } from '#lib/overview/fleet.js';
import { fromRuns } from '#lib/overview/moving.js';
import { ALL, fleetSeries } from '#lib/server/fleet.js';
import { edgeOf } from '#lib/server/platform.js';
import { cluster } from '#lib/server/read.js';
import { type Range, range } from '#lib/server/reads.js';
import { runs } from '#lib/server/runs.js';
import { RANGES } from '#lib/ui/segmented.svelte';
import type { PageServerLoad } from './$types';

/** What the fleet's charts draw, asked of every node in one request each. */
const METRICS = ['cpu.usage', 'memory.used', 'network.received', 'network.sent'];
const HOUR = 3600;
const DAYS = 30;

/**
 * Everything at once: the cluster, the fleet's series over the chosen span and over the last day
 * by the hour, and every node's recent runs. A node that does not answer is a gap and a note.
 */
export const load: PageServerLoad = async (event) => {
	const edge = edgeOf(event);
	const asked = event.url.searchParams.get('range');
	const chosen = (RANGES.find((one) => one.key === asked)?.key ?? '1h') as Range;
	const span = range(chosen);
	const day = range('24h', span.until);
	const series = fleetSeries(edge, { ...span, metrics: METRICS });
	const [read, fleet, hours, history, { zone }] = await Promise.all([
		cluster(edge),
		series,
		chosen === '24h' ? series : fleetSeries(edge, { ...day, metrics: ['cpu.usage'] }),
		runs(edge),
		event.parent(),
	]);
	const now = span.until * 1000;
	const month = now - DAYS * 86_400_000;
	return {
		cluster: read,
		range: chosen,
		span: { since: span.since, until: span.until },
		fleet: {
			cpu: perNode(fleet, 'cpu.usage'),
			memory: perNode(fleet, 'memory.used'),
			received: perNode(fleet, 'network.received'),
			sent: perNode(fleet, 'network.sent'),
			missing: missing(fleet),
			marks: marks(history.runs, span.since, span.until),
		},
		heat: { ...heat(hours, 'cpu.usage', { ...day, step: HOUR }), missing: missing(hours) },
		deploys: {
			daily: daily(history.runs, now, zone, DAYS),
			outcomes: byNode(history.runs, ALL, month),
			figures: figures(history.runs, now, month),
			missing: Object.entries(history.failures).map(([node, failure]) => ({
				node,
				message: failure.message,
			})),
		},
		moving: fromRuns(history.runs),
	};
};
