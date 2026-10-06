import { error } from '@sveltejs/kit';
import { markers, nodeCharts } from '#lib/nodes/charts.js';
import { PAGE, olderThan, viewOf } from '#lib/nodes/view.js';
import { edgeOf } from '#lib/server/platform.js';
import { cluster, isNode } from '#lib/server/read.js';
import { apps, disk, events, nodeNow, nodeSeries, range } from '#lib/server/reads.js';
import type { PageServerLoad } from './$types';

/** How many of the node's latest events the charts look through for deploys to mark. */
const MARKED = 200;

/**
 * The header's reads on every tab, and the open tab's own beside them, all at once. A read that
 * fails comes back as its failure, said in its place on the page.
 */
export const load: PageServerLoad = async (event) => {
	const name = event.params.node;
	if (!isNode(name)) error(404, `No node is named ${name}.`);
	const edge = edgeOf(event);
	const view = viewOf(event.url.searchParams);
	const span = range(view.range);
	const on = <T>(tab: typeof view.tab, read: () => Promise<T>) =>
		view.tab === tab ? read() : Promise.resolve(undefined);

	const [read, machine, series, recent, listed, page, usage] = await Promise.all([
		cluster(edge),
		nodeNow(edge, name),
		on('overview', () => nodeSeries(edge, name, span)),
		on('overview', () => events(edge, name, { limit: MARKED })),
		on('apps', () => apps(edge, name)),
		on('events', () => events(edge, name, { limit: PAGE, before: view.before })),
		on('disk', () => disk(edge, name)),
	]);

	return {
		cluster: read,
		name,
		view,
		span,
		now: Date.now(),
		machine,
		charts: series && (series.ok ? { ...series, data: nodeCharts(series.data) } : series),
		marks: recent?.ok ? markers(recent.data, span.since, span.until) : [],
		apps: listed,
		events: page && {
			read: page,
			older: page.ok ? olderThan(page.data.map((one) => one.id)) : undefined,
		},
		disk: usage,
	};
};
