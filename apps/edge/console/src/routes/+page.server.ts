import { metric } from '#lib/chart/series.js';
import type { Point } from '#lib/host.js';
import { edgeOf } from '#lib/server/platform.js';
import { cluster, node } from '#lib/server/read.js';
import type { PageServerLoad } from './$types';

/** The CPU chart's span, in seconds: the last hour, at a point a minute. */
const SPAN = 3600;

export const load: PageServerLoad = async (event) => {
	const edge = edgeOf(event);
	const read = await cluster(edge);
	if (!read.ok) return { cluster: read, cpu: undefined };
	// The node whose relay answered is the nearest that answers.
	const until = Math.floor(Date.now() / 1000);
	const since = until - SPAN;
	const query = new URLSearchParams({ grain: 'minute', metrics: 'cpu.usage', since: `${since}` });
	const series = await node<Point[]>(edge, read.node, `/node/series?${query}`);
	return {
		cluster: read,
		cpu: {
			node: read.node,
			since,
			until,
			read: series.ok ? { ...series, data: metric(series.data, 'cpu.usage') } : series,
		},
	};
};
