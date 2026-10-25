// Asks a target by its id through the entry and answers what came back, RFC y2xd3.
export default {
	async fetch(request, env) {
		const path = new URL(request.url).pathname;
		if (request.method !== 'POST' || path !== '/reach') {
			return new Response('no export at this path\n', { status: 404 });
		}
		const { id, body } = await request.json();
		const origins = JSON.parse(env.MONOFLAKE_REACHING ?? '{}');
		if (!Object.hasOwn(origins, id)) {
			return Response.json({ unreachable: id });
		}
		try {
			const answer = await fetch(new URL('/echo', origins[id]), {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body),
			});
			const text = await answer.text();
			let parsed;
			try {
				parsed = JSON.parse(text);
			} catch {
				parsed = text;
			}
			return Response.json({ status: answer.status, body: parsed });
		} catch (e) {
			return Response.json({ failed: e.name }, { status: 502 });
		}
	},
};
