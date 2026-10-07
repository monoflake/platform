import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import { DOTS } from './land.generated.ts';
import WorldMap from './world-map.svelte';
import type { Held } from '../wire.ts';

const NOW = Date.parse('2026-10-06T12:00:00Z');
const CODES = ['tyo', 'nrt', 'hnd', 'gvx', 'bru', 'buf', 'rdu'];

function held(secondsAgo: number, cpu?: number): Held {
	return {
		version: 1,
		heard_at: new Date(NOW - secondsAgo * 1000).toISOString(),
		snapshot: {
			taken_at: '2026-10-06T12:00:00Z',
			events: [],
			apps: [{ name: 'geo', image: 'geo:1', deployed_at: '', running: true, held: false }],
			machine: cpu === undefined ? undefined : { sample: { values: { 'cpu.usage': cpu } } },
		},
	};
}

/** Each node's mark, from its link to the link's end. */
const marks = (body: string) =>
	Object.fromEntries(
		body
			.split('data-node="')
			.slice(1)
			.map((mark) => [mark.slice(0, 3), mark.split('</a>')[0] ?? '']),
	);

describe('world map on the server', () => {
	const states = { tyo: held(2), gvx: held(30), buf: held(300), nrt: held(2, 15) };

	it('draws the land as dots and every mark, with no name and no line', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW } });
		expect(body).toMatch(/<svg[^>]*viewBox="0 0 1000 670"/);
		expect(body).toContain(`d="${DOTS}"`);
		expect(body).toContain('stroke-dasharray="4 6"');
		for (const code of CODES) {
			expect(body).toContain(`data-node="${code}"`);
			expect(body).not.toMatch(new RegExp(`>${code}</span>`));
		}
		expect(body.match(/data-node="/g)).toHaveLength(7);
		expect(body.match(/<path/g)).toHaveLength(1);
		expect(body).not.toContain('<line');
	});

	it('shows two states, heard and gone, a late node drawn heard', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW } });
		expect(body).toMatch(/data-node="tyo" data-state="live"/);
		expect(body).toMatch(/data-node="gvx" data-state="live"/);
		expect(body).toMatch(/data-node="buf" data-state="gone"/);
		expect(body).toMatch(/data-node="rdu" data-state="gone"/);
		expect(body).toContain('aria-label="gvx, Gävle, live"');
		expect(body).not.toMatch(/data-state="late"|color-warn/);
	});
	it('sizes each mark by its apps running, the middle size where nothing is known', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW } });
		expect(body).toMatch(/data-node="tyo"[^>]*data-radius="7"/);
		expect(body).toMatch(/data-node="rdu"[^>]*data-radius="9.5"/);
		expect(body).toContain('width: 1.4cqw');
	});

	it('fills every mark as deep as its node runs, a gone one too', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW, compact: true } });
		const by = marks(body);
		expect(by.tyo).toContain('style="opacity: 0.45;"');
		expect(by.buf).toContain('style="opacity: 0.45;"');
		expect(by.rdu).toContain('style="opacity: 0.72;"');
	});

	it('breathes a halo behind each heard mark, as fast as its node is busy', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW } });
		const by = marks(body);
		expect(by.tyo).toMatch(/data-halo[^>]*animation-duration: 4s/);
		expect(by.gvx).toMatch(/data-halo[^>]*animation-duration: 4s/);
		expect(by.nrt).toMatch(/data-halo[^>]*animation-duration: 1.6s/);
		expect(by.buf).not.toContain('data-halo');
		expect(by.rdu).not.toContain('data-halo');
		const delays = Object.values(by).map((mark) => /animation-delay: ([^;"]+)/.exec(mark)?.[1]);
		expect(new Set(delays.filter(Boolean)).size).toBe(3);
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

	it('leaves the card and globe out of a compact map', () => {
		const { body } = render(WorldMap, { props: { states, now: NOW, compact: true } });
		expect(body.match(/data-node="/g)).toHaveLength(7);
		expect(body).not.toMatch(/>tyo<\/span>/);
		expect(body).not.toContain('role="tooltip"');
		expect(body).not.toContain('Map view');
	});
});
