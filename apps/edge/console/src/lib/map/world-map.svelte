<script lang="ts">
	/**
	 * The nodes on a flat map of dots, each mark encoded as marks.ts says; hovering or focusing one
	 * opens its card, a click opens the node. Projected at build time (scripts/land.ts) and drawn
	 * whole by the server; a full one can turn into a globe (globe.ts). See
	 * spec/architecture/console.md.
	 */
	import * as stylex from '@stylexjs/stylex';
	import { duration, radius, text, weight } from '@canmi/kit/tokens/vocabulary.stylex';
	import { ago } from '../format.ts';
	import { liveness, readings, running } from '../node.ts';
	import { scoped } from '../scope/context.ts';
	import { tone } from '../style.ts';
	import Segmented from '../ui/segmented.svelte';
	import type { Held } from '../wire.ts';
	import type { Globe } from './globe.ts';
	import { DOT, DOTS, HEIGHT, LOCATIONS, PITCH, POINTS, WIDTH } from './land.generated.ts';
	import { opacity, period, radius as size, shown, type Shown } from './marks.ts';
	import { PLACES, ROLES } from './places.ts';

	let {
		states,
		now,
		selected,
		compact = false,
	}: {
		/** What is held of each node, by code; a node not in it has not been heard. */
		states: Record<string, Held>;
		/** The clock liveness is read against, in milliseconds. */
		now: number;
		/** A node drawn above the rest without the pointer, as the one a page is about. */
		selected?: string;
		/** A small card: no card on hover and no globe. */
		compact?: boolean;
	} = $props();

	const { node: toNode } = scoped();

	/** The node under the pointer or holding focus. */
	let active: string | undefined = $state();
	const lit = $derived(active ?? selected);

	const WORDS: Record<Shown, string> = { live: 'Live', gone: 'Gone' };
	const VIEWS = [
		{ key: 'flat', label: 'Flat' },
		{ key: 'globe', label: 'Globe' },
	] as const;
	/** Pixels between a mark's edge and its card, and between the card and the map's edge. */
	const GAP = 8;
	const EDGE = 4;
	/** One unit of the flat map's width in degrees, to move a hand-set offset onto the globe. */
	const DEGREES = 360 / WIDTH;

	const nodes = $derived(
		(Object.keys(POINTS) as (keyof typeof POINTS)[]).map((code, index) => {
			const held = states[code];
			const place = PLACES[code];
			const [ox, oy] = place.offset ?? [0, 0];
			const [x, y] = POINTS[code];
			const apps = held ? running(held) : undefined;
			const cpu = readings(held?.snapshot.machine)?.cpu;
			return {
				code,
				held,
				x: x + ox,
				y: y + oy,
				offset: [ox, oy] as const,
				apps,
				cpu,
				radius: size(apps?.running),
				opacity: opacity(apps?.running),
				period: period(cpu),
				/** Where in its breath a node starts, spread by the golden ratio so none pulse together. */
				phase: (index * 0.618) % 1,
				place,
				state: shown(held ? liveness(held.heard_at, now) : 'gone'),
			};
		}),
	);
	const card = $derived(nodes.find((node) => node.code === active));

	let view: (typeof VIEWS)[number]['key'] = $state('flat');
	let host: HTMLDivElement | undefined = $state();
	let globe: Globe | undefined = $state.raw();

	$effect(() => {
		if (view !== 'globe' || !host) return;
		const into = host;
		const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
		let made: Globe | undefined;
		let gone = false;
		void import('./globe.ts').then(({ mount }) => {
			if (gone) return;
			made = mount(into, still);
			globe = made;
		});
		return () => {
			gone = true;
			made?.destroy();
			globe = undefined;
		};
	});

	$effect(() => {
		globe?.mark(
			nodes.map(({ code, offset: [ox, oy], radius, opacity, state }) => {
				// The flat map's offset moved on the sphere, a Mercator unit north shrinking with latitude.
				const [latitude, longitude] = LOCATIONS[code];
				const north = -oy * DEGREES * Math.cos((latitude * Math.PI) / 180);
				const location = [latitude + north, longitude + ox * DEGREES] as const;
				return { location, radius, opacity, state };
			}),
		);
	});

	/** The map's width in pixels, and the open card's size, read once the card is drawn. */
	let mapWidth = $state(0);
	let cardWidth = $state(0);
	let cardHeight = $state(0);

	/** Beside its mark, on whichever side has room, and never past the map's edges. */
	const placed = $derived.by(() => {
		if (!card || !mapWidth || !cardWidth) return undefined;
		const scale = mapWidth / WIDTH;
		const mapHeight = HEIGHT * scale;
		const [x, y, reach] = [card.x * scale, card.y * scale, card.radius * scale + GAP];
		const right = x + reach;
		const left = right + cardWidth <= mapWidth - EDGE ? right : x - reach - cardWidth;
		const clamp = (value: number, most: number) => Math.min(Math.max(value, EDGE), most - EDGE);
		return {
			left: clamp(left, mapWidth - cardWidth),
			top: clamp(y - cardHeight / 2, mapHeight - cardHeight),
		};
	});

	const share = (units: number, whole: number) => `${(units / whole) * 100}%`;
	/** A mark's diameter as a share of the map's width, so it grows and shrinks with the map. */
	const across = (radius: number) => `${Number((((2 * radius) / WIDTH) * 100).toFixed(4))}cqw`;
	const percent = (cpu: number) => `${cpu < 10 ? cpu.toFixed(1) : Math.round(cpu)}%`;

	/** A heard mark's halo: out from the mark to 1.8 times it, fading as it goes. */
	const breathe = stylex.keyframes({
		from: { transform: 'scale(1)', opacity: 0.35 },
		to: { transform: 'scale(1.8)', opacity: 0 },
	});

	const styles = stylex.create({
		land: { stroke: 'var(--color-line-strong)' },
		marker: {
			outline: { default: 'none', ':focus-visible': '2px solid var(--color-accent)' },
			outlineOffset: 3,
			borderRadius: radius.full,
			transitionProperty: 'width, height',
			transitionDuration: duration.base,
		},
		fill: {
			backgroundColor: 'var(--color-primary)',
			borderRadius: radius.full,
			transitionProperty: 'opacity',
			transitionDuration: duration.base,
		},
		gone: { backgroundColor: 'var(--color-danger)' },
		halo: {
			display: { default: 'block', '@media (prefers-reduced-motion: reduce)': 'none' },
			backgroundColor: 'var(--color-primary)',
			borderRadius: radius.full,
			pointerEvents: 'none',
			animationName: breathe,
			animationTimingFunction: 'ease-out',
			animationIterationCount: 'infinite',
		},
		tooltip: {
			minWidth: 180,
			paddingBlock: 10,
			paddingInline: 12,
			backgroundColor: 'var(--color-surface)',
			borderWidth: '1px',
			borderStyle: 'solid',
			borderColor: 'var(--color-line)',
			borderRadius: 8,
			boxShadow: '0 4px 12px rgb(0 0 0 / 0.25), 0 1px 3px rgb(0 0 0 / 0.2)',
			fontSize: text.px13,
			lineHeight: 1.4,
		},
		code: { color: 'var(--color-text-strong)', fontWeight: weight.semibold },
		muted: { color: 'var(--color-text-muted)' },
		value: { color: 'var(--color-text)', fontVariantNumeric: 'tabular-nums', textAlign: 'right' },
	});
</script>

{#snippet dot(state: Shown, size: string)}
	<span class="shrink-0 {size} {stylex.attrs(styles.fill, state === 'gone' && styles.gone).class}"
	></span>
{/snippet}

<div
	class="@container relative w-full select-none"
	style:aspect-ratio="{WIDTH} / {HEIGHT}"
	bind:clientWidth={mapWidth}
>
	{#if view === 'globe'}
		<div
			bind:this={host}
			class="absolute inset-0"
			role="img"
			aria-label="The nodes on a globe"
		></div>
	{:else}
		<svg viewBox="0 0 {WIDTH} {HEIGHT}" class="absolute inset-0 block size-full" aria-hidden="true">
			<!-- Each run of land is one line, dashed into square dots: scripts/project.ts. -->
			<path
				d={DOTS}
				fill="none"
				stroke-width={DOT}
				stroke-dasharray="{DOT} {PITCH - DOT}"
				class={stylex.attrs(styles.land).class}
			/>
		</svg>

		{#each nodes as node (node.code)}
			<a
				href={toNode(node.code)}
				data-node={node.code}
				data-state={node.state}
				data-radius={node.radius}
				aria-label="{node.code}, {node.place.place}, {WORDS[node.state].toLowerCase()}"
				title={compact ? `${node.code}: ${WORDS[node.state]}` : undefined}
				class="absolute block -translate-x-1/2 -translate-y-1/2 {lit === node.code
					? 'z-[1]'
					: ''} {stylex.attrs(styles.marker).class}"
				style:left={share(node.x, WIDTH)}
				style:top={share(node.y, HEIGHT)}
				style:width={across(node.radius)}
				style:height={across(node.radius)}
				onpointerenter={() => (active = node.code)}
				onpointerleave={() => (active = undefined)}
				onfocus={() => (active = node.code)}
				onblur={() => (active = undefined)}
			>
				{#if node.state === 'live'}
					<span
						data-halo
						class="absolute inset-0 {stylex.attrs(styles.halo).class}"
						style:animation-duration="{node.period}s"
						style:animation-delay="{-(node.phase * node.period).toFixed(2)}s"
					></span>
				{/if}
				<span
					class="absolute inset-0 {stylex.attrs(styles.fill, node.state === 'gone' && styles.gone)
						.class}"
					style:opacity={node.opacity}
				></span>
			</a>
		{/each}

		{#if card && !compact}
			{@const machine = readings(card.held?.snapshot.machine)}
			<div
				role="tooltip"
				class="pointer-events-none absolute top-0 left-0 z-10 flex flex-col gap-1.5 {stylex.attrs(
					styles.tooltip,
				).class}"
				style:visibility={placed ? 'visible' : 'hidden'}
				style:transform={placed ? `translate(${placed.left}px, ${placed.top}px)` : undefined}
				bind:clientWidth={cardWidth}
				bind:clientHeight={cardHeight}
			>
				<span class="flex items-center gap-2">
					<span class={stylex.attrs(styles.code).class}>{card.code}</span>
					{@render dot(card.state, 'size-2')}
					<span class="ml-auto pl-3 {stylex.attrs(styles.muted).class}">{card.place.place}</span>
				</span>
				<dl class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
					<dt class={stylex.attrs(styles.muted).class}>Status</dt>
					<dd class={stylex.attrs(styles.value, card.state === 'gone' && tone.bad).class}>
						{WORDS[card.state]}
					</dd>
					<dt class={stylex.attrs(styles.muted).class}>Heard</dt>
					<dd class={stylex.attrs(styles.value, styles.muted).class}>
						{card.held ? ago(card.held.heard_at, now) : 'never'}
					</dd>
					<dt class={stylex.attrs(styles.muted).class}>Role</dt>
					<dd class={stylex.attrs(styles.value).class}>{ROLES[card.place.role]}</dd>
					<dt class={stylex.attrs(styles.muted).class}>Apps running</dt>
					<dd class={stylex.attrs(styles.value).class}>
						{card.apps ? `${card.apps.running} of ${card.apps.total}` : '–'}
					</dd>
					<dt class={stylex.attrs(styles.muted).class}>CPU now</dt>
					<dd class={stylex.attrs(styles.value).class}>
						{card.cpu === undefined ? '–' : percent(card.cpu)}
					</dd>
					{#if machine?.memory?.total}
						<dt class={stylex.attrs(styles.muted).class}>Memory</dt>
						<dd class={stylex.attrs(styles.value).class}>
							{Math.round((machine.memory.used / machine.memory.total) * 100)}%
						</dd>
					{/if}
				</dl>
			</div>
		{/if}
	{/if}

	{#if !compact}
		<div class="absolute bottom-0 left-0">
			<Segmented options={VIEWS} bind:value={view} label="Map view" />
		</div>
	{/if}
</div>
