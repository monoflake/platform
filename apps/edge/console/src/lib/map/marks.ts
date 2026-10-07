/**
 * What a node's mark says: its size and depth how much it runs, its breathing how busy it is now,
 * its color whether it is heard. The globe takes size, depth and color and leaves the breathing
 * out. See spec/architecture/console.md, the paragraph on the world map.
 */
import type { Liveness } from '../node.ts';

/** The two states a mark shows: a late node is only between two snapshots, so it is drawn heard. */
export type Shown = 'live' | 'gone';

export function shown(liveness: Liveness): Shown {
	return liveness === 'gone' ? 'gone' : 'live';
}

/**
 * Apps running, at most, for each radius in the flat map's viewBox units and each opacity; the
 * last has no top. The smallest spans two of the land's dots, a pitch and a dot
 * (scripts/project.ts).
 */
export const SIZES = [
	{ apps: 5, radius: 7, opacity: 0.45 },
	{ apps: 15, radius: 9.5, opacity: 0.72 },
	{ apps: Infinity, radius: 12, opacity: 1 },
] as const;

/** CPU percent now, below which each breathing period holds, in seconds: the busier, the faster. */
export const BREATHS = [
	{ below: 2, period: 4 },
	{ below: 10, period: 2.6 },
	{ below: 30, period: 1.6 },
	{ below: Infinity, period: 0.9 },
] as const;

/** The step for the apps running on a node; not knowing gives the middle one. */
function step(apps: number | undefined) {
	if (apps === undefined || !Number.isFinite(apps)) return SIZES[1];
	return SIZES.find((size) => apps <= size.apps) ?? SIZES[2];
}

/** A mark's radius for the apps running on its node. */
export function radius(apps: number | undefined): number {
	return step(apps).radius;
}

/** A mark's opacity for the apps running on its node. */
export function opacity(apps: number | undefined): number {
	return step(apps).opacity;
}

/** A mark's breathing period for its node's CPU percent now; not knowing gives the slowest. */
export function period(cpu: number | undefined): number {
	if (cpu === undefined || !Number.isFinite(cpu)) return BREATHS[0].period;
	return (BREATHS.find((breath) => cpu < breath.below) ?? BREATHS[3]).period;
}
