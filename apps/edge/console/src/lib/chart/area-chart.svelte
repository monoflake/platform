<script lang="ts">
	/**
	 * An area chart: a gradient under each line, a faint band from each point's minimum to its
	 * maximum, and a crosshair and a tooltip under the pointer. Drawn whole on the server: the plot
	 * is a viewBox stretched across whatever width it is given, so nothing is measured and nothing
	 * moves on hydration, and the labels and hover marks a stretch would distort are HTML placed in
	 * percent. d3 computes the scales and the paths; the markup is Svelte's. Ported from infra's
	 * apps/deploy/panel/src/lib/chart/area-chart.svelte.
	 */
	import * as stylex from '@stylexjs/stylex';
	import { untrack } from 'svelte';
	import { pressMotion, prefersReducedMotion } from '@canmi/kit/motion';
	import { radius, text, weight } from '@canmi/kit/tokens/vocabulary.stylex';
	import { bisector } from 'd3-array';
	import { scaleLinear, scaleTime } from 'd3-scale';
	import { area, curveMonotoneX, line as linePath } from 'd3-shape';
	import { binaryTicks, moment, tickLabel, withGaps, type Datum, type Line } from './series.ts';
	import { type } from '../style.ts';

	let {
		lines,
		since,
		until,
		height = 200,
		ceiling,
		format = (value: number) => value.toFixed(1),
		band = true,
		compact = false,
		bytes = false,
		reveal = '',
	}: {
		lines: Line[];
		/** The span shown, in seconds; the points' own when not given. */
		since?: number;
		until?: number;
		height?: number;
		/** The top of the scale when it is fixed, as a percentage's is at 100. */
		ceiling?: number;
		format?: (value: number) => string;
		/** Whether to shade each point's minimum to maximum. */
		band?: boolean;
		/** No axes and no grid: a sparkline. */
		compact?: boolean;
		/** A quantity of bytes, so its ticks fall on binary units. */
		bytes?: boolean;
		/** Draws the plot in again when it changes: the span chosen, never each new point. */
		reveal?: string;
	} = $props();

	/** The plot's width in its own units; the page stretches it to whatever width it has. */
	const WIDTH = 1000;
	/** Where the tooltip turns to the pointer's left, as a share of the plot. */
	const FLIP = 0.6;

	const id = $props.id();
	/**
	 * How strong each line's fill is. Fills are layered, and several colors layered wash out toward
	 * gray: one line keeps its gradient, two share it, and three or more are drawn as lines alone.
	 */
	const fill = $derived(lines.length === 1 ? 0.32 : lines.length === 2 ? 0.16 : 0);
	/** Where the pointer is across the plot, in its own units. */
	let pointer: number | undefined = $state();
	let plot: SVGGElement | undefined = $state();

	const margin = $derived(
		compact
			? { top: 2, right: 0, bottom: 2, left: 0 }
			: { top: 10, right: 8, bottom: 26, left: 52 },
	);
	/** The plot's height, in pixels and in its own units alike: only its width stretches. */
	const inner = $derived(Math.max(1, height - margin.top - margin.bottom));
	const all = $derived(lines.flatMap((line) => line.points));
	const start = $derived(since ?? (all.length ? Math.min(...all.map((point) => point.at)) : 0));
	const end = $derived(until ?? (all.length ? Math.max(...all.map((point) => point.at)) : 0));

	const x = $derived(
		scaleTime()
			.domain([new Date(start * 1000), new Date(end * 1000)])
			.range([0, WIDTH]),
	);
	const y = $derived.by(() => {
		const highest = Math.max(
			0,
			...all.map((point) => (band ? (point.maximum ?? point.value) : point.value)),
		);
		const top = ceiling ?? (highest > 0 ? highest * 1.1 : 1);
		const scale = scaleLinear().range([inner, 0]);
		if (ceiling !== undefined) return scale.domain([0, ceiling]);
		if (bytes) return scale.domain([0, binaryTicks(top).at(-1) ?? top]);
		return scale.domain([0, top]).nice(4);
	});

	const defined = (point: Datum) => !Number.isNaN(point.value);
	const across = (point: Datum) => x(new Date(point.at * 1000));
	const share = (units: number) => `${(units / WIDTH) * 100}%`;

	const shapes = $derived(
		lines.map((line) => {
			const points = withGaps(line.points);
			const shape = area<Datum>().defined(defined).curve(curveMonotoneX).x(across);
			return {
				line,
				fill: shape.y0(y(0)).y1((point) => y(point.value))(points),
				stroke: linePath<Datum>()
					.defined(defined)
					.curve(curveMonotoneX)
					.x(across)
					.y((point) => y(point.value))(points),
				band:
					band && points.some((point) => point.minimum !== undefined)
						? area<Datum>()
								.defined(defined)
								.curve(curveMonotoneX)
								.x(across)
								.y0((point) => y(point.minimum ?? point.value))
								.y1((point) => y(point.maximum ?? point.value))(points)
						: null,
			};
		}),
	);

	const yTicks = $derived.by(() => {
		if (compact) return [];
		const [, top = 0] = y.domain();
		return bytes ? binaryTicks(top) : y.ticks(4);
	});
	/** No label set against an edge, where it would be cut in half. */
	const xTicks = $derived(
		compact ? [] : x.ticks(6).filter((tick) => x(tick) > WIDTH * 0.04 && x(tick) < WIDTH * 0.96),
	);
	const label = $derived(tickLabel(end - start));

	const nearest = bisector((point: Datum) => point.at).center;
	/** What the pointer is over: the moment, and each line's point nearest it. */
	const hovered = $derived.by(() => {
		if (pointer === undefined || lines.length === 0) return undefined;
		const at = x.invert(pointer).getTime() / 1000;
		const found = lines
			.map((line) => ({ line, point: line.points[nearest(line.points, at)] }))
			.filter((entry): entry is { line: Line; point: Datum } => entry.point !== undefined);
		const [first] = found;
		if (!first) return undefined;
		return { at: first.point.at, left: x(new Date(first.point.at * 1000)), found };
	});

	function move(event: PointerEvent) {
		const box = (event.currentTarget as HTMLElement).getBoundingClientRect();
		const within = box.width > 0 ? (event.clientX - box.left) / box.width : -1;
		pointer = within >= 0 && within <= 1 ? within * WIDTH : undefined;
	}

	/** The span drawn last. The server's drawing is the first, so only a new span draws in. */
	let drawn = untrack(() => reveal);
	$effect(() => {
		const next = reveal;
		if (!plot || next === drawn) return;
		drawn = next;
		const across = plot.ownerSVGElement?.clientWidth ?? 0;
		if (!across || prefersReducedMotion()) return;
		const timing = pressMotion(across);
		plot.animate([{ clipPath: 'inset(0 100% 0 0)' }, { clipPath: 'inset(0 0 0 0)' }], {
			duration: timing.duration * 1000 * 1.6,
			easing: `cubic-bezier(${timing.ease.join(', ')})`,
		});
	});

	const styles = stylex.create({
		axis: {
			color: 'var(--color-text-faint)',
			fontSize: text.px11,
			fontVariantNumeric: 'tabular-nums',
			lineHeight: 1,
		},
		grid: { stroke: 'var(--color-line)', strokeWidth: 1, strokeDasharray: '2 4' },
		base: { stroke: 'var(--color-line-strong)', strokeWidth: 1 },
		crosshair: { stroke: 'var(--color-text-muted)', strokeWidth: 1, strokeDasharray: '3 3' },
		dot: { borderRadius: radius.full, boxShadow: '0 0 0 2px var(--color-surface)' },
		tooltip: {
			backgroundColor: 'var(--color-raised)',
			borderWidth: '1px',
			borderStyle: 'solid',
			borderColor: 'var(--color-line-strong)',
			borderRadius: radius.lg,
			boxShadow: '0 8px 24px rgb(0 0 0 / 0.35)',
		},
		swatch: { borderRadius: radius.sm },
		value: {
			color: 'var(--color-text-strong)',
			fontSize: text.px12,
			fontWeight: weight.semibold,
			fontVariantNumeric: 'tabular-nums',
		},
	});
</script>

<div class="relative w-full" style:height="{height}px">
	{#each yTicks as tick (tick)}
		<span
			class="absolute -translate-y-1/2 text-right whitespace-nowrap {stylex.attrs(styles.axis)
				.class}"
			style:right="calc(100% - {margin.left - 10}px)"
			style:top="{margin.top + y(tick)}px">{format(tick)}</span
		>
	{/each}
	{#each xTicks as tick (tick.getTime())}
		<span
			class="absolute bottom-1.5 -translate-x-1/2 whitespace-nowrap {stylex.attrs(styles.axis)
				.class}"
			style:left="calc({margin.left}px + (100% - {margin.left + margin.right}px) * {x(tick) /
				WIDTH})">{label(tick)}</span
		>
	{/each}

	<div
		class="absolute touch-none select-none"
		style:inset="{margin.top}px {margin.right}px {margin.bottom}px {margin.left}px"
		role="img"
		aria-label={lines.map((line) => line.label).join(', ')}
		onpointermove={move}
		onpointerleave={() => (pointer = undefined)}
	>
		<svg
			viewBox="0 0 {WIDTH} {inner}"
			preserveAspectRatio="none"
			class="absolute inset-0 block size-full overflow-visible"
			aria-hidden="true"
		>
			<defs>
				{#each lines as line (line.key)}
					<linearGradient id="{id}-{line.key}" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0%" style:stop-color={line.color} style:stop-opacity={fill} />
						<stop offset="100%" style:stop-color={line.color} style:stop-opacity="0" />
					</linearGradient>
				{/each}
			</defs>

			{#each yTicks as tick (tick)}
				<line
					x1="0"
					x2={WIDTH}
					y1={y(tick)}
					y2={y(tick)}
					vector-effect="non-scaling-stroke"
					class={stylex.attrs(tick === 0 ? styles.base : styles.grid).class}
				/>
			{/each}

			{#key reveal}
				<g bind:this={plot}>
					{#each shapes as shape (shape.line.key)}
						{#if shape.band && fill > 0}
							<path d={shape.band} style:fill={shape.line.color} style:fill-opacity={fill * 0.4} />
						{/if}
						{#if fill > 0}<path d={shape.fill} fill="url(#{id}-{shape.line.key})" />{/if}
						<path
							d={shape.stroke}
							fill="none"
							style:stroke={shape.line.color}
							stroke-width={compact ? 1.25 : 1.75}
							stroke-linejoin="round"
							stroke-linecap="round"
							vector-effect="non-scaling-stroke"
						/>
					{/each}
				</g>
			{/key}

			{#if hovered && !compact}
				<line
					x1={hovered.left}
					x2={hovered.left}
					y1="0"
					y2={inner}
					vector-effect="non-scaling-stroke"
					class={stylex.attrs(styles.crosshair).class}
				/>
			{/if}
		</svg>

		{#if hovered && !compact}
			{#each hovered.found as entry (entry.line.key)}
				{#if !Number.isNaN(entry.point.value)}
					<span
						class="pointer-events-none absolute size-2 -translate-1/2 {stylex.attrs(styles.dot)
							.class}"
						style:left={share(hovered.left)}
						style:top="{y(entry.point.value)}px"
						style:background-color={entry.line.color}
					></span>
				{/if}
			{/each}
			<div
				class="pointer-events-none absolute -top-2 z-10 flex min-w-44 flex-col gap-1.5 px-3 py-2.5 {stylex.attrs(
					styles.tooltip,
				).class}"
				style:left={share(hovered.left)}
				style:transform={hovered.left > WIDTH * FLIP
					? 'translateX(calc(-100% - 12px))'
					: 'translateX(12px)'}
			>
				<span class={stylex.attrs(type.label).class}>{moment(hovered.at)}</span>
				{#each hovered.found as entry (entry.line.key)}
					<span class="flex items-center gap-2">
						<span
							class="size-2 shrink-0 {stylex.attrs(styles.swatch).class}"
							style:background-color={entry.line.color}
						></span>
						<span class="flex-1 {stylex.attrs(type.soft).class}">{entry.line.label}</span>
						<span class={stylex.attrs(styles.value).class}>{format(entry.point.value)}</span>
					</span>
				{/each}
			</div>
		{/if}
	</div>
</div>
