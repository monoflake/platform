import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import AreaChart from './area-chart.svelte';
import type { Datum } from './series.ts';

const START = 1_790_000_000;
const points: Datum[] = Array.from({ length: 60 }, (_, minute) => ({
	at: START + minute * 60,
	value: 20 + (minute % 10),
	minimum: 10,
	maximum: 40,
}));

describe('area chart on the server', () => {
	it('renders the plot and its axes whole, with nothing measured first', () => {
		const { body } = render(AreaChart, {
			props: {
				lines: [{ key: 'cpu', label: 'Busy', color: 'var(--color-series-2)', points }],
				since: START,
				until: START + 3600,
				ceiling: 100,
				format: (value: number) => `${value}%`,
			},
		});
		expect(body).toMatch(/<svg[^>]*viewBox="0 0 1000 164"/);
		// The band, the fill and the line, each a drawn path.
		expect(body.match(/<path d="M[\d.]/g)).toHaveLength(3);
		// The grid, and a label per tick on the value axis and the time axis.
		expect(body.match(/<line /g)?.length).toBeGreaterThanOrEqual(4);
		for (const tick of ['0%', '20%', '100%']) expect(body).toContain(`>${tick}</span>`);
		expect(body.match(/>\d{1,2}:\d{2}(?: [AP]M)?<\/span>/g)?.length).toBeGreaterThan(0);
	});

	it('draws a sparkline with no axes', () => {
		const { body } = render(AreaChart, {
			props: { lines: [{ key: 'cpu', label: 'Busy', color: 'red', points }], compact: true },
		});
		expect(body).toContain('<path d="M');
		expect(body).not.toContain('<line ');
	});
});
