<script lang="ts">
	/**
	 * The nodes on a world map: land, a faint graticule and the relay mesh as great circles, with a
	 * marker per node colored by whether it is heard and shaped by it as well. The geometry is
	 * projected at build time (scripts/land.ts), so the server draws the whole map and nothing is
	 * measured; the markers and labels are HTML placed in percent, so they keep their size as the
	 * plot stretches. Hovering or focusing a marker opens its card and lights its links, and a click
	 * goes to the node's page.
	 */
	import * as stylex from '@stylexjs/stylex';
	import { radius, text, weight } from '@canmi/kit/tokens/vocabulary.stylex';
	import { ago } from '../format.ts';
	import { liveness, readings, running, type Liveness } from '../node.ts';
	import { tone as tones, type, type Tone } from '../style.ts';
	import type { Held } from '../wire.ts';
	import { ARCS, GRATICULE, HEIGHT, LAND, POINTS, WIDTH } from './land.generated.ts';
	import { PLACES, ROLES, type Side } from './places.ts';

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
		/** A node to light up without the pointer, as the one a page is about. */
		selected?: string;
		/** A small card: no labels, no graticule and no card on hover. */
		compact?: boolean;
	} = $props();

	/** The node under the pointer or holding focus. */
	let active: string | undefined = $state();
	const lit = $derived(active ?? selected);

	const WORDS: Record<Liveness, string> = { live: 'Live', late: 'Late', gone: 'Gone' };
	const TONES: Record<Liveness, Tone> = { live: 'good', late: 'warn', gone: 'bad' };
	/** Where a code is written from its marker, as whole classes for Tailwind to find. */
	const SIDES: Record<Side, string> = {
		left: 'right-full mr-1 top-1/2 -translate-y-1/2',
		right: 'left-full ml-1 top-1/2 -translate-y-1/2',
		top: 'bottom-full mb-0.5 left-1/2 -translate-x-1/2',
		bottom: 'top-full mt-0.5 left-1/2 -translate-x-1/2',
	};
	/** Where the tooltip turns to the marker's left, as a share of the plot. */
	const FLIP = 0.6;

	const nodes = $derived(
		(Object.keys(POINTS) as (keyof typeof POINTS)[]).map((code) => {
			const held = states[code];
			const [x, y] = POINTS[code];
			return {
				code,
				held,
				x,
				y,
				place: PLACES[code],
				state: held ? liveness(held.heard_at, now) : ('gone' as Liveness),
			};
		}),
	);
	const card = $derived(nodes.find((node) => node.code === active));
	const linked = (arc: { from: string; to: string }) => arc.from === lit || arc.to === lit;
	const share = (units: number, whole: number) => `${(units / whole) * 100}%`;

	const styles = stylex.create({
		land: { fill: 'var(--color-raised)', stroke: 'var(--color-line)', strokeWidth: 0.75 },
		graticule: { stroke: 'var(--color-line)', strokeWidth: 1, opacity: 0.35 },
		arc: { stroke: 'var(--color-line-strong)', strokeWidth: 1, opacity: 0.4 },
		arcLit: { stroke: 'var(--color-accent)', strokeWidth: 1.5, opacity: 0.9 },
		leader: { stroke: 'var(--color-line-strong)', strokeWidth: 1 },
		origin: { backgroundColor: 'var(--color-text-faint)', borderRadius: radius.full },
		marker: {
			outline: { default: 'none', ':focus-visible': '2px solid var(--color-accent)' },
			outlineOffset: 2,
			borderRadius: radius.full,
		},
		code: {
			color: 'var(--color-text-muted)',
			fontSize: text.px11,
			fontWeight: weight.medium,
			lineHeight: 1,
		},
		codeLit: { color: 'var(--color-text-strong)' },
		tooltip: {
			backgroundColor: 'var(--color-raised)',
			borderWidth: '1px',
			borderStyle: 'solid',
			borderColor: 'var(--color-line-strong)',
			borderRadius: radius.lg,
			boxShadow: '0 8px 24px rgb(0 0 0 / 0.35)',
		},
		value: {
			color: 'var(--color-text-strong)',
			fontSize: text.px12,
			fontWeight: weight.semibold,
			fontVariantNumeric: 'tabular-nums',
		},
	});
</script>

{#snippet shape(state: Liveness)}
	<!-- A circle is live, a diamond late and a crossed square gone: never color alone. The ring is
	the surface color painted around the shape. -->
	<svg viewBox="0 0 14 14" class="block size-full overflow-visible" aria-hidden="true">
		{#if state === 'live'}
			<circle
				cx="7"
				cy="7"
				r="4"
				fill="currentColor"
				stroke="var(--color-surface)"
				stroke-width="4"
				paint-order="stroke"
			/>
		{:else if state === 'late'}
			<path
				d="M7 1.8 12.2 7 7 12.2 1.8 7Z"
				fill="currentColor"
				stroke="var(--color-surface)"
				stroke-width="4"
				stroke-linejoin="round"
				paint-order="stroke"
			/>
		{:else}
			<rect
				x="3"
				y="3"
				width="8"
				height="8"
				rx="1"
				fill="currentColor"
				stroke="var(--color-surface)"
				stroke-width="4"
				stroke-linejoin="round"
				paint-order="stroke"
			/>
			<path d="M5.2 5.2 8.8 8.8M8.8 5.2 5.2 8.8" stroke="var(--color-surface)" stroke-width="1.4" />
		{/if}
	</svg>
{/snippet}

<div class="relative w-full select-none">
	<svg viewBox="0 0 {WIDTH} {HEIGHT}" class="block h-auto w-full" aria-hidden="true">
		<path d={LAND} class={stylex.attrs(styles.land).class} />
		{#if !compact}
			<path
				d={GRATICULE}
				fill="none"
				vector-effect="non-scaling-stroke"
				class={stylex.attrs(styles.graticule).class}
			/>
		{/if}
		{#each ARCS.filter((arc) => !linked(arc)) as arc (arc.from + arc.to)}
			<path
				d={arc.d}
				fill="none"
				vector-effect="non-scaling-stroke"
				class={stylex.attrs(styles.arc).class}
			/>
		{/each}
		{#each ARCS.filter(linked) as arc (arc.from + arc.to)}
			<path
				d={arc.d}
				fill="none"
				data-lit
				vector-effect="non-scaling-stroke"
				class={stylex.attrs(styles.arcLit).class}
			/>
		{/each}
	</svg>

	{#each nodes as node (node.code)}
		{@const [dx, dy] = node.place.offset ?? [0, 0]}
		{@const moved = dx !== 0 || dy !== 0}
		<div
			class="absolute size-0"
			style:left={share(node.x, WIDTH)}
			style:top={share(node.y, HEIGHT)}
		>
			{#if moved}
				<span class="absolute -top-px -left-px size-0.5 {stylex.attrs(styles.origin).class}"></span>
				<svg
					class="pointer-events-none absolute top-0 left-0 size-px overflow-visible"
					aria-hidden="true"
				>
					<line x1="0" y1="0" x2={dx} y2={dy} class={stylex.attrs(styles.leader).class} />
				</svg>
			{/if}
			<a
				href="/nodes/{node.code}"
				data-node={node.code}
				data-state={node.state}
				aria-label="{node.code}, {node.place.place}, {WORDS[node.state].toLowerCase()}"
				title={compact ? `${node.code}: ${WORDS[node.state]}` : undefined}
				class="absolute block size-3.5 {stylex.attrs(styles.marker, tones[TONES[node.state]])
					.class}"
				style:left="{dx - 7}px"
				style:top="{dy - 7}px"
				onpointerenter={() => (active = node.code)}
				onpointerleave={() => (active = undefined)}
				onfocus={() => (active = node.code)}
				onblur={() => (active = undefined)}
			>
				{@render shape(node.state)}
				{#if !compact}
					<span
						class="pointer-events-none absolute whitespace-nowrap {SIDES[
							node.place.side
						]} {stylex.attrs(type.mono, styles.code, lit === node.code && styles.codeLit).class}"
						>{node.code}</span
					>
				{/if}
			</a>
		</div>
	{/each}

	{#if card && !compact}
		{@const [dx, dy] = card.place.offset ?? [0, 0]}
		{@const machine = readings(card.held?.snapshot.machine)}
		{@const apps = card.held ? running(card.held) : undefined}
		<div
			role="tooltip"
			class="pointer-events-none absolute z-10 flex min-w-44 flex-col gap-1.5 px-3 py-2.5 {stylex.attrs(
				styles.tooltip,
			).class}"
			style:left="calc({share(card.x, WIDTH)} + {dx}px)"
			style:top="calc({share(card.y, HEIGHT)} + {dy}px)"
			style:transform={card.x > WIDTH * FLIP
				? 'translate(calc(-100% - 12px), 12px)'
				: 'translate(12px, 12px)'}
		>
			<span class="flex items-baseline justify-between gap-3">
				<span class={stylex.attrs(type.name, type.mono).class}>{card.code}</span>
				<span class={stylex.attrs(type.soft).class}>{card.place.place}</span>
			</span>
			<span
				class="flex items-center gap-2 {stylex.attrs(type.soft, tones[TONES[card.state]]).class}"
			>
				<span class="size-3 shrink-0">{@render shape(card.state)}</span>
				{WORDS[card.state]}
				{#if card.held}
					<span class={stylex.attrs(type.soft).class}>{ago(card.held.heard_at, now)}</span>
				{/if}
			</span>
			<dl class="grid grid-cols-[auto_auto] justify-between gap-x-4 gap-y-1">
				<dt class={stylex.attrs(type.soft).class}>Role</dt>
				<dd class={stylex.attrs(styles.value).class}>{ROLES[card.place.role]}</dd>
				{#if machine?.cpu !== undefined}
					<dt class={stylex.attrs(type.soft).class}>CPU</dt>
					<dd class={stylex.attrs(styles.value).class}>{Math.round(machine.cpu)}%</dd>
				{/if}
				{#if machine?.memory?.total}
					<dt class={stylex.attrs(type.soft).class}>Memory</dt>
					<dd class={stylex.attrs(styles.value).class}>
						{Math.round((machine.memory.used / machine.memory.total) * 100)}%
					</dd>
				{/if}
				{#if apps}
					<dt class={stylex.attrs(type.soft).class}>Apps</dt>
					<dd class={stylex.attrs(styles.value).class}>{apps.running} of {apps.total} running</dd>
				{/if}
			</dl>
		</div>
	{/if}
</div>
