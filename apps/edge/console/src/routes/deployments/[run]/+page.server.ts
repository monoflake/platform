import { error } from '@sveltejs/kit';
import { edgeOf } from '#lib/server/platform.js';
import { cluster } from '#lib/server/read.js';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
	const run = Number(event.params.run);
	if (!Number.isSafeInteger(run) || run <= 0) error(404, `No run is numbered ${event.params.run}.`);
	return { cluster: await cluster(edgeOf(event)), run };
};
