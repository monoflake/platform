import { ALL } from '#lib/server/fleet.js';
import { edgeOf } from '#lib/server/platform.js';
import { cluster } from '#lib/server/read.js';
import type { PageServerLoad } from './$types';

/** The cluster streamed, so the page stands at once; see spec/architecture/console.md. */
export const load: PageServerLoad = (event) => ({
	cluster: cluster(edgeOf(event)),
	order: ALL,
});
