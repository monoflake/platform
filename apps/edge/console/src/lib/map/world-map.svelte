<script lang="ts">
	/**
	 * The nodes on a flat world map: land as a grid of dots and a circle per node, sized by the apps
	 * it runs and as opaque as it is busy (marks.ts), blue while heard, ringed amber when late and
	 * hollow red when gone; its card says the same in words. The geometry is projected at build
	 * time (scripts/land.ts), so the server draws the whole map and nothing is measured; the marks
	 * are HTML placed in percent. Hovering or focusing a mark opens its card, and a click opens the
	 * node. A full map can turn into a globe, drawn in the browser by globe.ts.
	 */
	import * as stylex from '@stylexjs/stylex';
	import { duration, radius, text, weight } from '@canmi/kit/tokens/vocabulary.stylex';
	import { ago } from '../format.ts';
	import { liveness, readings, running, type Liveness } from '../node.ts';
	import { tone as tones, type, type Tone } from '../style.ts';
	import Segmented from '../ui/segmented.svelte';
	import type { Held } from '../wire.ts';
	import type { Globe } from './globe.ts';
	import { DOT, DOTS, HEIGHT, LOCATIONS, PITCH, POINTS, WIDTH } from './land.generated.ts';
	import { opacity, radius as size } from './marks.ts';
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
		/** A node whose code is lit without the pointer, as the one a page is about. */
		selected?: string;
		/** A small card: no labels, no card on hover and no globe. */
		compact?: boolean;
	} = $props();

	/** The node under the pointer or holding focus. */
	let active: string | undefined = $state();
	const lit = $derived(active ?? selected);

	const WORDS: Record<Liveness, string> = { live: 'Live', late: 'Late', gone: 'Gone' };
	const TONES: Record<Liveness, Tone> = { live: 'good', late: 'warn', gone: 'bad' };
	const VIEWS = [
		{ key: 'flat', label: 'Flat' },
		{ key: 'globe', label: 'Globe' },
	] as const;
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
			const apps = held ? running(held) : undefined;
			const cpu = readings(held?.snapshot.machine)?.cpu;
			return {
				code,
				held,
				x,
				y,
				apps,
				cpu,
				radius: size(apps?.running),
				opacity: opacity(cpu),
				place: PLACES[code],
				state: held ? liveness(held.heard_at, now) : ('gone' as Liveness),
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
			nodes.map(({ code, radius, opacity, state }) => ({
				location: LOCATIONS[code],
				radius,
				opacity,
				state,
			})),
		);
	});
	const share = (units: number, whole: number) => `${(units / whole) * 100}%`;
	/** A mark's diameter as a share of the map's width, so it grows and shrinks with the map. */
	const across = (radius: number) => `${((2 * radius) / WIDTH) * 100}cqw`;
	const percent = (cpu: number) => `${cpu < 10 ? cpu.toFixed(1) : Math.round(cpu)}%`;

	const styles = stylex.create({
		land: { stroke: 'var(--color-line-strong)' },
		leader: { stroke: 'var(--color-line-strong)', strokeWidth: 1 },
		origin: { backgroundColor: 'var(--color-text-faint)', borderRadius: radius.full },
		marker: {
			outline: { default: 'none', ':focus-visible': '2px solid var(--color-accent)' },
			outlineOffset: 3,
			borderRadius: radius.full,
			transitionProperty: 'width, height',
			transitionDuration: duration.base,
		},
		fill: {
			backgroundColor: 'var(--color-accent)',
			borderRadius: radius.full,
			transitionProperty: 'opacity',
			transitionDuration: duration.base,
		},
		late: { boxShadow: '0 0 0 2px var(--color-warn)' },
		gone: { borderWidth: '2px', borderStyle: 'solid', borderColor: 'var(--color-danger)' },
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

<div class="@container relative w-full select-none" style:aspect-ratio="{WIDTH} / {HEIGHT}">
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
			{@const [dx, dy] = node.place.offset ?? [0, 0]}
			{@const moved = dx !== 0 || dy !== 0}
			<div
				class="absolute size-0"
				style:left={share(node.x, WIDTH)}
				style:top={share(node.y, HEIGHT)}
			>
				{#if moved}
					<span class="absolute -top-px -left-px size-0.5 {stylex.attrs(styles.origin).class}"
					></span>
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
					data-radius={node.radius}
					class="absolute block -translate-x-1/2 -translate-y-1/2 {stylex.attrs(
						styles.marker,
						node.state === 'late' && styles.late,
						node.state === 'gone' && styles.gone,
					).class}"
					style:left="{dx}px"
					style:top="{dy}px"
					style:width={across(node.radius)}
					style:height={across(node.radius)}
					onpointerenter={() => (active = node.code)}
					onpointerleave={() => (active = undefined)}
					onfocus={() => (active = node.code)}
					onblur={() => (active = undefined)}
				>
					{#if node.state !== 'gone'}
						<span
							class="absolute inset-0 {stylex.attrs(styles.fill).class}"
							style:opacity={node.opacity}
						></span>
					{/if}
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
					class="flex items-center gap-2 {stylex.attrs(
						type.soft,
						card.state !== 'live' && tones[TONES[card.state]],
					).class}"
				>
					<span
						class="relative size-2.5 shrink-0 {stylex.attrs(
							styles.marker,
							card.state === 'late' && styles.late,
							card.state === 'gone' && styles.gone,
						).class}"
					>
						{#if card.state !== 'gone'}
							<span class="absolute inset-0 {stylex.attrs(styles.fill).class}"></span>
						{/if}
					</span>
					{WORDS[card.state]}
					{#if card.held}
						<span class={stylex.attrs(type.soft).class}>{ago(card.held.heard_at, now)}</span>
					{/if}
				</span>
				<dl class="grid grid-cols-[auto_auto] justify-between gap-x-4 gap-y-1">
					<dt class={stylex.attrs(type.soft).class}>Role</dt>
					<dd class={stylex.attrs(styles.value).class}>{ROLES[card.place.role]}</dd>
					<dt class={stylex.attrs(type.soft).class}>Apps running</dt>
					<dd class={stylex.attrs(styles.value).class}>
						{card.apps ? `${card.apps.running} of ${card.apps.total}` : '–'}
					</dd>
					<dt class={stylex.attrs(type.soft).class}>CPU now</dt>
					<dd class={stylex.attrs(styles.value).class}>
						{card.cpu === undefined ? '–' : percent(card.cpu)}
					</dd>
					{#if machine?.memory?.total}
						<dt class={stylex.attrs(type.soft).class}>Memory</dt>
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
