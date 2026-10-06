import { describe, expect, it } from 'vitest';
import { build, projectionOf } from '../../../scripts/project.ts';
import { NODES } from '../server/nodes.ts';
import * as generated from './land.generated.ts';
import { PLACES } from './places.ts';

describe('the generated map', () => {
	it('places every node of nodes.ts where the projection puts it', () => {
		expect(Object.keys(generated.POINTS).toSorted()).toEqual(Object.keys(NODES).toSorted());
		const world = projectionOf(generated.PROJECTION);
		for (const [code, [latitude, longitude]] of Object.entries(NODES)) {
			const [x, y] = world([longitude, latitude]) ?? [NaN, NaN];
			const [gx, gy] = generated.POINTS[code as keyof typeof NODES];
			expect(gx).toBeCloseTo(x, 1);
			expect(gy).toBeCloseTo(y, 1);
		}
	});

	it('is what scripts/land.ts would write now: run `pnpm map` when this fails', () => {
		const built = build();
		expect(generated.WIDTH).toBe(built.width);
		expect(generated.HEIGHT).toBe(built.height);
		expect(generated.PROJECTION).toEqual(built.projection);
		expect(generated.LAND).toBe(built.land);
		expect(generated.GRATICULE).toBe(built.graticule);
		expect(generated.POINTS).toEqual(built.points);
		expect(generated.ARCS).toEqual(built.arcs);
	});

	it('keeps every node inside the plot', () => {
		for (const [x, y] of Object.values(generated.POINTS)) {
			expect(x).toBeGreaterThan(0);
			expect(x).toBeLessThan(generated.WIDTH);
			expect(y).toBeGreaterThan(0);
			expect(y).toBeLessThan(generated.HEIGHT);
		}
	});

	it('knows a place for every node', () => {
		expect(Object.keys(PLACES).toSorted()).toEqual(Object.keys(NODES).toSorted());
	});
});
