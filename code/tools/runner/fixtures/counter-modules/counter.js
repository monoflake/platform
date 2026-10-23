// Counts the calls to increment for each key in its memory, as tests/fixtures/counter-modules
// describes, a call reaching it at `/<key>/increment`.
const counts = new Map();

export default {
	async fetch(request) {
		const parts = new URL(request.url).pathname.split('/').filter((part) => part !== '');
		if (request.method !== 'POST' || parts.length !== 2 || parts[1] !== 'increment') {
			return new Response('no export at this path\n', { status: 404 });
		}
		const count = (counts.get(parts[0]) ?? 0) + 1;
		counts.set(parts[0], count);
		return Response.json({ count: String(count) });
	},
};
