import { error } from '@sveltejs/kit';
import { appReads } from '#lib/apps/read.js';
import { placements } from '#lib/apps/apps.js';
import { ALL } from '#lib/server/fleet.js';
import { edgeOf } from '#lib/server/platform.js';
import { cluster } from '#lib/server/read.js';
import { range } from '#lib/server/reads.js';
import { RANGES } from '#lib/ui/segmented.svelte';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
	const app = event.params.app;
	const edge = edgeOf(event);
	const asked = event.url.searchParams.get('range');
	const chosen = RANGES.find((one) => one.key === asked)?.key ?? '24h';
	const span = range(chosen);
	const held = await cluster(edge);
	const where = held.ok ? placements(ALL, held.data, app).map((one) => one.node) : ALL;
	if (held.ok && where.length === 0) error(404, `No node runs ${app}.`);
	const reads = await appReads(edge, where, app, span);
	return { cluster: held, order: ALL, app, range: chosen, span, ...reads };
};
