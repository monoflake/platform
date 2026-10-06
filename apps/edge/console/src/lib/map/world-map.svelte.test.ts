import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import { ARCS, LAND } from './land.generated.ts';
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

	it('draws the land, every marker with its code, and the mesh whole', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW } });
		expect(body).toMatch(/<svg[^>]*viewBox="0 0 1000 520"/);
		expect(body).toContain(`d="${LAND}"`);
		for (const code of CODES) {
			expect(body).toContain(`data-node="${code}"`);
			expect(body).toMatch(new RegExp(`>${code}</span>`));
		}
		expect(body.match(/data-node="/g)).toHaveLength(7);
		for (const arc of ARCS) expect(body).toContain(`d="${arc.d}"`);
		expect(ARCS.length).toBeGreaterThan(0);
		expect(body).not.toContain('data-lit');
	});

	it('says each marker by shape as well as color: heard, late, gone, never heard', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW } });
		expect(body).toMatch(/data-node="tyo" data-state="live"/);
		expect(body).toMatch(/data-node="gvx" data-state="late"/);
		expect(body).toMatch(/data-node="buf" data-state="gone"/);
		expect(body).toMatch(/data-node="rdu" data-state="gone"/);
		expect(body).toContain('aria-label="gvx, Gävle, late"');
		expect(body).toContain('<circle');
		expect(body).toContain('M7 1.8 12.2 7');
		expect(body).toContain('<rect');
	});

	it('lights the links of the selected node', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW, selected: 'bru' } });
		const lit = ARCS.filter((arc) => arc.from === 'bru' || arc.to === 'bru');
		expect(body.match(/data-lit/g)).toHaveLength(lit.length);
	});

	it('leaves the labels, graticule and card out of a compact map', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW, compact: true } });
		expect(body.match(/data-node="/g)).toHaveLength(7);
		expect(body).not.toMatch(/>tyo<\/span>/);
		expect(body).not.toContain('role="tooltip"');
	});
});
