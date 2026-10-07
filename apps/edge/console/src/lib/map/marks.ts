/**
 * What a node's mark says, on the flat map and the globe alike: its size how much it runs, its
 * opacity how busy it is now. See spec/architecture/console.md, the paragraph on the world map.
 */

/** Apps running, at most, for each radius in the flat map's viewBox units; the last has no top. */
export const SIZES = [
	{ apps: 5, radius: 10 },
	{ apps: 15, radius: 14 },
	{ apps: Infinity, radius: 19 },
] as const;

/**
 * CPU percent now, below which each opacity holds. Nodes idle at 1 to 10%, so the low steps are
 * close together, to tell idle nodes apart.
 */
export const BUSY = [
	{ below: 2, opacity: 0.35 },
	{ below: 10, opacity: 0.55 },
	{ below: 30, opacity: 0.78 },
	{ below: Infinity, opacity: 1 },
] as const;

/** A mark's radius for the apps running on its node; not knowing gives the middle step. */
export function radius(apps: number | undefined): number {
	if (apps === undefined || !Number.isFinite(apps)) return SIZES[1].radius;
	return (SIZES.find((step) => apps <= step.apps) ?? SIZES[2]).radius;
}

/** A mark's opacity for its node's CPU percent now; not knowing gives full opacity. */
export function opacity(cpu: number | undefined): number {
	if (cpu === undefined || !Number.isFinite(cpu)) return 1;
	return (BUSY.find((step) => cpu < step.below) ?? BUSY[3]).opacity;
}
