<script lang="ts">
	/**
	 * Where the console goes: its five sections, the one being read marked as the panel marks it,
	 * and at the foot whether it is live or polling, through which node, and how many it hears.
	 */
	import * as stylex from '@stylexjs/stylex';
	import Radio from '@lucide/svelte/icons/radio-tower';
	import { radius, text, weight } from '@canmi/kit/tokens/vocabulary.stylex';
	import type { Live } from './live.svelte.ts';
	import { PLACES } from './map/places.ts';
	import { liveness } from './node.ts';
	import { SECTIONS, type Section } from './sections.ts';
	import { surfaces, type } from './style.ts';
	import Badge from './ui/badge.svelte';
	import { CONTRACT } from './wire.ts';

	let { current, live }: { current: Section | undefined; live: Live } = $props();

	const WORD = { connecting: 'Connecting', live: 'Live', polling: 'Polling every 5 s' } as const;
	const TONE = { connecting: 'quiet', live: 'good', polling: 'warn' } as const;
	const TOTAL = Object.keys(PLACES).length;
	const heard = $derived(
		Object.values(live.view.nodes).filter((held) => liveness(held.heard_at, live.now) === 'live')
			.length,
	);

	const styles = stylex.create({
		brandMark: {
			backgroundColor: 'var(--color-primary)',
			color: 'var(--nord6)',
			borderRadius: radius.lg,
		},
		brandName: {
			color: 'var(--color-text-strong)',
			fontSize: text.px14,
			fontWeight: weight.semibold,
			lineHeight: 1.2,
		},
		link: {
			borderRadius: radius.md,
			color: {
				default: 'var(--color-text-muted)',
				':hover': 'var(--color-text-strong)',
			},
			fontSize: text.px13,
			fontWeight: weight.medium,
			transitionProperty: 'color',
			transitionDuration: '120ms',
		},
		here: {
			backgroundColor: 'var(--color-selected)',
			color: 'var(--color-text-strong)',
		},
		edge: {
			backgroundColor: 'var(--color-accent)',
			borderRadius: radius.full,
		},
	});
</script>

<aside
	class="sticky top-0 flex h-screen w-56 shrink-0 flex-col {stylex.attrs(surfaces.sidebar).class}"
>
	<div class="flex items-center gap-3 px-4 pt-5 pb-6">
		<span
			class="flex size-8 shrink-0 items-center justify-center {stylex.attrs(styles.brandMark)
				.class}"
		>
			<Radio size={16} strokeWidth={2} />
		</span>
		<span class="flex min-w-0 flex-col gap-0.5">
			<span class={stylex.attrs(styles.brandName).class}>console</span>
			<span class="truncate {stylex.attrs(type.label).class}">every node</span>
		</span>
	</div>

	<nav class="flex flex-col gap-0.5 px-2">
		{#each SECTIONS as section (section.href)}
			{@const here = section === current}
			<a
				href={section.href}
				aria-current={here ? 'page' : undefined}
				class="relative flex h-9 items-center gap-2.5 px-3 {stylex.attrs(
					styles.link,
					here && styles.here,
				).class}"
			>
				{#if here}
					<span class="absolute top-2 bottom-2 left-0 w-0.5 {stylex.attrs(styles.edge).class}"
					></span>
				{/if}
				<section.icon size={16} strokeWidth={1.75} />
				{section.label}
			</a>
		{/each}
	</nav>

	<footer class="mt-auto flex flex-col gap-2 px-4 py-4 {stylex.attrs(surfaces.rowRule).class}">
		<div class="flex items-center justify-between gap-2">
			<Badge tone={TONE[live.mode]}>{WORD[live.mode]}</Badge>
			<span class={stylex.attrs(type.soft).class}>{heard} of {TOTAL} live</span>
		</div>
		{#if live.view.via}
			<span class={stylex.attrs(type.soft).class}>
				Through <span class={stylex.attrs(type.mono).class}>{live.view.via}</span>
			</span>
		{/if}
		{#if live.mode === 'polling' && live.failure}
			<span class="truncate {stylex.attrs(type.soft).class}" title={live.failure}>
				Last poll failed
			</span>
		{/if}
		{#if live.view.refused !== undefined}
			<span class={stylex.attrs(type.soft).class}>
				The relay speaks contract {live.view.refused}; this console reads {CONTRACT}.
			</span>
		{/if}
	</footer>
</aside>
