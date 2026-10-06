import { error } from '@sveltejs/kit';
import type { Now } from '#lib/host.js';
import { edgeOf } from '#lib/server/platform.js';
import { cluster, isNode, node } from '#lib/server/read.js';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
	const name = event.params.node;
	if (!isNode(name)) error(404, `No node is named ${name}.`);
	const edge = edgeOf(event);
	const [read, now] = await Promise.all([cluster(edge), node<Now>(edge, name, '/node/now')]);
	return { cluster: read, name, now };
};
