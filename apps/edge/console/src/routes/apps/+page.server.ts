import { ALL } from '#lib/server/fleet.js';
import { edgeOf } from '#lib/server/platform.js';
import { cluster } from '#lib/server/read.js';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => ({
	cluster: await cluster(edgeOf(event)),
	order: ALL,
});
