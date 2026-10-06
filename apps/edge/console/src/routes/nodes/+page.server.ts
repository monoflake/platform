import { metric } from '#lib/chart/series.js';
import type { Now } from '#lib/host.js';
import { ALL, fleetNow, fleetSeries } from '#lib/server/fleet.js';
import type { Node } from '#lib/server/nodes.js';
import { edgeOf } from '#lib/server/platform.js';
import { cluster, type Failure } from '#lib/server/read.js';
import { range } from '#lib/server/reads.js';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
	const edge = edgeOf(event);
	const [read, machines, cpu] = await Promise.all([
		cluster(edge),
		fleetNow(edge),
		fleetSeries(edge, { ...range('1h'), metrics: ['cpu.usage'] }),
	]);
	const known: Partial<Record<Node, Now>> = {};
	const failures: Partial<Record<Node, Failure>> = {};
	const trends: Partial<Record<Node, number[]>> = {};
	for (const name of ALL) {
		const machine = machines[name];
		if (machine.ok) known[name] = machine.data;
		else failures[name] = machine.failure;
		const series = cpu[name];
		if (series.ok) trends[name] = metric(series.data, 'cpu.usage').map((point) => point.value);
	}
	return { cluster: read, machines: known, failures, trends, now: Date.now() };
};
