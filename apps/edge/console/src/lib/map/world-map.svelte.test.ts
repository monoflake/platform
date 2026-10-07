import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import { DOTS } from './land.generated.ts';
import WorldMap from './world-map.svelte';
import type { Held } from '../wire.ts';

const NOW = Date.parse('2026-10-06T12:00:00Z');
const CODES = ['tyo', 'nrt', 'hnd', 'gvx', 'bru', 'buf', 'rdu'];

function held(secondsAgo: number): Held {
	return {
		version: 1,
		heard_at: new Date(NOW - secondsAgo * 1000).toISOString(),
		snapshot: {
			taken_at: '2026-10-06T12:00:00Z',
			events: [],
			apps: [{ name: 'geo', image: 'geo:1', deployed_at: '', running: true, held: false }],
		},
	};
}

describe('world map on the server', () => {
	const states = { tyo: held(2), gvx: held(30), buf: held(300) };

	it('draws the land as dots, every marker with its code, and the mesh whole', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW } });
		expect(body).toMatch(/<svg[^>]*viewBox="0 0 1000 670"/);
		expect(body).toContain(`d="${DOTS}"`);
		expect(body).toContain('stroke-dasharray="4 6"');
		for (const code of CODES) {
			expect(body).toContain(`data-node="${code}"`);
			expect(body).toMatch(new RegExp(`>${code}</span>`));
		}
		expect(body.match(/data-node="/g)).toHaveLength(7);
		expect(body.match(/<path/g)).toHaveLength(1);
	});

	it('tones each marker by when it was heard, and says it in words', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW } });
		expect(body).toMatch(/data-node="tyo" data-state="live"/);
		expect(body).toMatch(/data-node="gvx" data-state="late"/);
		expect(body).toMatch(/data-node="buf" data-state="gone"/);
		expect(body).toMatch(/data-node="rdu" data-state="gone"/);
		expect(body).toContain('aria-label="gvx, Gävle, late"');
	});

	it('sizes each mark by its apps running, the middle size where nothing is known', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW } });
		expect(body).toMatch(/data-node="tyo"[^>]*data-radius="10"/);
		expect(body).toMatch(/data-node="rdu"[^>]*data-radius="14"/);
		expect(body).toContain('width: 2cqw');
	});

	it('leaves a gone node hollow, and fills the rest', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW, compact: true } });
		const marks = body.split('data-node="').slice(1);
		const filled = marks.filter((mark) => mark.split('</a>')[0]?.includes('style="opacity'));
		expect(filled).toHaveLength(2);
	});

	it('draws no links between nodes, a node selected or not', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW, selected: 'bru' } });
		expect(body).not.toContain('data-lit');
		expect(body.match(/<path/g)).toHaveLength(1);
	});

	it('starts flat, the globe offered and not drawn', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW } });
		expect(body).toContain('aria-label="Map view"');
		expect(body).toMatch(/aria-checked="true"[^>]*>Flat</);
		expect(body).toMatch(/aria-checked="false"[^>]*>Globe</);
		expect(body).not.toContain('<canvas');
		expect(body).not.toContain('The nodes on a globe');
	});

	it('leaves the labels, card and globe out of a compact map', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW, compact: true } });
		expect(body.match(/data-node="/g)).toHaveLength(7);
		expect(body).not.toMatch(/>tyo<\/span>/);
		expect(body).not.toContain('role="tooltip"');
		expect(body).not.toContain('Map view');
	});
});
