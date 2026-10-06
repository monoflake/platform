/**
 * The world map's geometry: land, graticule, the nodes and the mesh between them, projected once.
 * `land.ts` writes it to `src/lib/map/land.generated.ts`; the map's test builds it again to see
 * the committed module is current. See spec/architecture/console.md.
 */
import { createRequire } from 'node:module';
import {
	geoEqualEarth,
	geoGraticule,
	geoPath,
	type GeoGeometryObjects,
	type GeoProjection,
} from 'd3-geo';
import { feature } from 'topojson-client';
import { NODES } from '../src/lib/server/nodes.ts';

/** The plot's width and height in its own units; the page stretches it to whatever it has. */
export const WIDTH = 1000;
export const HEIGHT = 520;
const PADDING = 8;
/** Nodes closer than this share a place on the map, and a link between them would be a speck. */
const MESH_MIN_KM = 100;

type Atlas = Parameters<typeof feature>[0] & { objects: { land: Parameters<typeof feature>[1] } };

export interface Fit {
	readonly scale: number;
	readonly translate: readonly [number, number];
}

export interface Geometry {
	width: number;
	height: number;
	projection: Fit;
	land: string;
	graticule: string;
	points: Record<string, [number, number]>;
	arcs: { from: string; to: string; d: string }[];
}

/** The projection a fit describes, as the module's reader rebuilds it. */
export function projectionOf({ scale, translate }: Fit): GeoProjection {
	return geoEqualEarth()
		.scale(scale)
		.translate([...translate]);
}

const round = (value: number) => Math.round(value * 100) / 100;

export function build(): Geometry {
	const topology = createRequire(import.meta.url)('world-atlas/land-110m.json') as Atlas;
	const land = feature(topology, topology.objects.land) as unknown as GeoGeometryObjects;

	const fitted = geoEqualEarth().fitExtent(
		[
			[PADDING, PADDING],
			[WIDTH - PADDING, HEIGHT - PADDING],
		],
		{ type: 'Sphere' },
	);
	const projection: Fit = {
		scale: round(fitted.scale()),
		translate: [round(fitted.translate()[0]), round(fitted.translate()[1])],
	};
	const world = projectionOf(projection);
	const path = geoPath(world).digits(1);

	const codes = Object.keys(NODES) as (keyof typeof NODES)[];
	const at = (code: keyof typeof NODES): [number, number] => {
		const [latitude, longitude] = NODES[code];
		return [longitude, latitude];
	};
	const points: Geometry['points'] = {};
	for (const code of codes) {
		const [x, y] = world(at(code)) ?? [0, 0];
		points[code] = [round(x), round(y)];
	}

	const arcs: Geometry['arcs'] = [];
	for (const [index, from] of codes.entries()) {
		for (const to of codes.slice(index + 1)) {
			if (kilometers(NODES[from], NODES[to]) < MESH_MIN_KM) continue;
			const d = path({ type: 'LineString', coordinates: [at(from), at(to)] });
			if (d) arcs.push({ from, to, d });
		}
	}

	return {
		width: WIDTH,
		height: HEIGHT,
		projection,
		land: path(land) ?? '',
		graticule: path(geoGraticule().step([30, 30])()) ?? '',
		points,
		arcs,
	};
}

function kilometers(a: readonly [number, number], b: readonly [number, number]): number {
	const radians = (degrees: number) => (degrees * Math.PI) / 180;
	const half =
		Math.sin(radians(b[0] - a[0]) / 2) ** 2 +
		Math.cos(radians(a[0])) * Math.cos(radians(b[0])) * Math.sin(radians(b[1] - a[1]) / 2) ** 2;
	return 2 * 6371 * Math.asin(Math.sqrt(half));
}
