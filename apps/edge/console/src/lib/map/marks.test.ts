import { describe, expect, it } from 'vitest';
import { BUSY, opacity, radius, SIZES } from './marks.ts';

describe('a mark by how much its node runs', () => {
	it('steps at 5 and 15 apps running', () => {
		expect(radius(0)).toBe(10);
		expect(radius(5)).toBe(10);
		expect(radius(6)).toBe(14);
		expect(radius(15)).toBe(14);
		expect(radius(16)).toBe(19);
		expect(radius(400)).toBe(19);
	});

	it('takes the middle step while the count is not known', () => {
		expect(radius(undefined)).toBe(SIZES[1].radius);
		expect(radius(NaN)).toBe(SIZES[1].radius);
	});
});

describe('a mark by how busy its node is', () => {
	it('steps below 2, 10 and 30 percent, so idle nodes are told apart', () => {
		expect(opacity(0)).toBe(0.35);
		expect(opacity(1.99)).toBe(0.35);
		expect(opacity(2)).toBe(0.55);
		expect(opacity(9.99)).toBe(0.55);
		expect(opacity(10)).toBe(0.78);
		expect(opacity(29.99)).toBe(0.78);
		expect(opacity(30)).toBe(1);
		expect(opacity(100)).toBe(1);
	});

	it('is whole while the CPU is not known', () => {
		expect(opacity(undefined)).toBe(1);
		expect(opacity(NaN)).toBe(1);
	});

	it('only grows with the load', () => {
		const opacities = BUSY.map((step) => step.opacity);
		expect(opacities).toEqual(opacities.toSorted((a, b) => a - b));
	});
});
