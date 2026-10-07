/**
 * The world map's geometry: land as a grid of dots, the nodes and the mesh between them, projected
 * once on a Mercator rectangle cut short of Antarctica. `land.ts` writes it to
 * `src/lib/map/land.generated.ts`; the map's test builds it again to see the committed module is
 * current. See spec/architecture/console.md.
 */
import { createRequire } from 'node:module';
import { geoBounds, geoContains, geoMercator, type GeoProjection } from 'd3-geo';
import type { FeatureCollection, MultiPolygon, Polygon } from 'geojson';
import { feature } from 'topojson-client';
import { NODES } from '../src/lib/server/nodes.ts';

/** Dots across the whole world, on an even grid of the plot rather than of degrees. */
const COLUMNS = 100;
/** The plot's units between one dot and the next, and a dot's side. */
export const PITCH = 10;
export const DOT = 4;
/** The latitudes the plot runs between: the far north kept, Antarctica cut off. */
const NORTH = 84;
const SOUTH = -57;

/** Mercator's height above the equator, in radians of width. */
const mercator = (latitude: number) => Math.log(Math.tan(Math.PI / 4 + radians(latitude) / 2));
const SCALE = (COLUMNS * PITCH) / (2 * Math.PI);
const ROWS = Math.ceil((SCALE * (mercator(NORTH) - mercator(SOUTH))) / PITCH);

/** The plot's width and height in its own units; the page stretches it to whatever it has. */
export const WIDTH = COLUMNS * PITCH;
export const HEIGHT = ROWS * PITCH;
function radians(degrees: number): number {
	return (degrees * Math.PI) / 180;
}

/** Nodes closer than this share a place on the map, and a link between them would be a speck. */
const MESH_MIN_KM = 100;
/** How far a link bows from the straight line, as a share of its length. */
const BOW = 0.15;

type Atlas = Parameters<typeof feature>[0] & { objects: { land: Parameters<typeof feature>[1] } };

export interface Fit {
	readonly scale: number;
	readonly translate: readonly [number, number];
}

export interface Geometry {
	width: number;
	height: number;
	projection: Fit;
	dots: string;
	/** Each node's latitude and longitude, for a reader that projects them itself. */
	locations: Record<string, [number, number]>;
	points: Record<string, [number, number]>;
	arcs: { from: string; to: string; d: string }[];
}

/** The projection a fit describes, as the module's reader rebuilds it. */
export function projectionOf({ scale, translate }: Fit): GeoProjection {
	return geoMercator()
		.scale(scale)
		.translate([...translate])
		.clipExtent([
			[0, 0],
			[WIDTH, HEIGHT],
		]);
}

const round = (value: number) => Math.round(value * 100) / 100;

export function build(): Geometry {
	const projection: Fit = {
		scale: round(SCALE),
		translate: [WIDTH / 2, round(SCALE * mercator(NORTH))],
	};
	const world = projectionOf(projection);

	const codes = Object.keys(NODES) as (keyof typeof NODES)[];
	const at = (code: keyof typeof NODES): [number, number] => {
		const [latitude, longitude] = NODES[code];
		return [longitude, latitude];
	};
	const locations: Geometry['locations'] = {};
	const points: Geometry['points'] = {};
	for (const code of codes) {
		const [x, y] = world(at(code)) ?? [0, 0];
		locations[code] = [...NODES[code]];
		points[code] = [round(x), round(y)];
	}

	const arcs: Geometry['arcs'] = [];
	for (const [index, from] of codes.entries()) {
		for (const to of codes.slice(index + 1)) {
			if (kilometers(NODES[from], NODES[to]) < MESH_MIN_KM) continue;
			arcs.push({ from, to, d: link(points[from] ?? [0, 0], points[to] ?? [0, 0]) });
		}
	}

	return { width: WIDTH, height: HEIGHT, projection, dots: dots(world), locations, points, arcs };
}

/**
 * Every cell whose center is on land, as one run per row of neighbors: a line the width of a dot,
 * which the map dashes into squares one pitch apart.
 */
function dots(world: GeoProjection): string {
	const topology = createRequire(import.meta.url)('world-atlas/land-110m.json') as Atlas;
	const land = feature(
		topology,
		topology.objects.land,
	) as unknown as FeatureCollection<MultiPolygon>;
	const polygons = land.features.flatMap(({ geometry }) => geometry.coordinates);
	const shapes = polygons.map((coordinates) => {
		const shape: Polygon = { type: 'Polygon', coordinates };
		return { shape, bounds: geoBounds(shape) };
	});
	const onLand = (point: [number, number]) =>
		shapes.some(({ shape, bounds: [[west, south], [east, north]] }) => {
			const [longitude, latitude] = point;
			if (latitude < south || latitude > north) return false;
			const inside =
				west <= east
					? west <= longitude && longitude <= east
					: west <= longitude || longitude <= east;
			return inside && geoContains(shape, point);
		});

	const cell = (column: number, row: number) =>
		world.invert?.([(column + 0.5) * PITCH, (row + 0.5) * PITCH]) ?? [0, 90];
	const inset = (PITCH - DOT) / 2;
	let d = '';
	for (let row = 0; row < ROWS; row++) {
		let start = -1;
		for (let column = 0; column <= COLUMNS; column++) {
			const land = column < COLUMNS && onLand(cell(column, row));
			if (land && start < 0) start = column;
			if (land || start < 0) continue;
			const length = (column - start - 1) * PITCH + DOT;
			d += `M${start * PITCH + inset} ${row * PITCH + PITCH / 2}h${length}`;
			start = -1;
		}
	}
	return d;
}

/**
 * A link as the map draws it: one quadratic curve inside the plot, bowed northward, never a great
 * circle, which would wrap the Pacific's links around the plot's edges.
 */
function link([x1, y1]: [number, number], [x2, y2]: [number, number]): string {
	const [dx, dy] = [x2 - x1, y2 - y1];
	// The normal that points up the plot, or left when the link runs straight up it.
	const flip = dx > 0 || (dx === 0 && dy > 0) ? 1 : -1;
	const x = (x1 + x2) / 2 + flip * dy * BOW;
	const y = (y1 + y2) / 2 - flip * dx * BOW;
	const inside = (value: number, most: number) => round(Math.min(Math.max(value, 0), most));
	return `M${x1} ${y1}Q${inside(x, WIDTH)} ${inside(y, HEIGHT)} ${x2} ${y2}`;
}

function kilometers(a: readonly [number, number], b: readonly [number, number]): number {
	const half =
		Math.sin(radians(b[0] - a[0]) / 2) ** 2 +
		Math.cos(radians(a[0])) * Math.cos(radians(b[0])) * Math.sin(radians(b[1] - a[1]) / 2) ** 2;
	return 2 * 6371 * Math.asin(Math.sqrt(half));
}
