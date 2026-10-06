import { known } from '#lib/ui/time-zone.js';
import { load as events } from '#lib/events/load.js';
import { edgeOf } from '#lib/server/platform.js';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
	const zone = known((event.request.cf as { timezone?: string } | undefined)?.timezone);
	return events(edgeOf(event), event.url.searchParams, zone);
};
