// Answers each call to echo with the body it was sent, as tests/fixtures/echo-modules describes.
export default {
	async fetch(request) {
		const path = new URL(request.url).pathname;
		if (request.method !== 'POST' || path !== '/echo') {
			return new Response('no export at this path\n', { status: 404 });
		}
		const body = await request.text();
		return new Response(body, { headers: { 'content-type': 'application/json' } });
	},
};
