<script lang="ts">
	/**
	 * Where the reader is, the section down to the thing open; and on the right whether the
	 * console is live, how many nodes it hears and through which one. Fixed right of the sidebar.
	 */
	import * as stylex from '@stylexjs/stylex';
	import { duration, text } from '@canmi/kit/tokens/vocabulary.stylex';
	import type { Live } from './live.svelte.ts';
	import { PLACES } from './map/places.ts';
	import { liveness } from './node.ts';
	import type { Section } from './sections.ts';
	import { surfaces, tone, type } from './style.ts';
	import Badge from './ui/badge.svelte';
	import { CONTRACT } from './wire.ts';

	let { section, detail, live }: { section?: Section; detail?: string; live: Live } = $props();

	const WORD = { connecting: 'Connecting', live: 'Live', polling: 'Polling' } as const;
	const TONE = { connecting: 'quiet', live: 'good', polling: 'warn' } as const;
	const TOTAL = Object.keys(PLACES).length;
	const heard = $derived(
		Object.values(live.view.nodes).filter((held) => liveness(held.heard_at, live.now) === 'live')
			.length,
	);
	const through = $derived(
		[
			live.view.via && `Through ${live.view.via}`,
			live.mode === 'polling' && 'every 5 s',
			live.failure && `last poll failed: ${live.failure}`,
		]
			.filter(Boolean)
			.join(', '),
	);

	const styles = stylex.create({
		crumb: {
			color: { default: 'var(--color-text-muted)', ':hover': 'var(--color-text-strong)' },
			fontSize: text.px14,
			transitionProperty: 'color',
			transitionDuration: duration.base,
		},
		here: {
			color: 'var(--color-text-strong)',
			fontSize: text.px14,
		},
		slash: {
			color: 'var(--color-line-strong)',
		},
	});
</script>

{#snippet slash()}
	<svg
		class={stylex.attrs(styles.slash).class}
		width="16"
		height="16"
		viewBox="0 0 16 16"
		fill="none"
		aria-hidden="true"
	>
		<path d="M10.5 2.5 5.5 13.5" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" />
	</svg>
{/snippet}

<header
	class="fixed top-0 right-0 left-60 z-30 flex h-14 items-center justify-between gap-4 px-8 {stylex.attrs(
		surfaces.bar,
	).class}"
>
	<nav aria-label="Breadcrumb" class="flex min-w-0 items-center gap-2">
		{#if section}
			{#if detail}
				<a href={section.href} class={stylex.attrs(styles.crumb).class}>{section.label}</a>
				{@render slash()}
				<span class="truncate {stylex.attrs(styles.here, type.mono).class}" aria-current="page"
					>{detail}</span
				>
			{:else}
				<span class={stylex.attrs(styles.here).class} aria-current="page">{section.label}</span>
			{/if}
		{/if}
	</nav>
	<div class="flex items-center gap-3">
		{#if live.view.refused !== undefined}
			<Badge tone="warn">Relay contract {live.view.refused}, console {CONTRACT}</Badge>
		{/if}
		<span class="inline-flex items-center gap-2 {stylex.attrs(type.soft).class}" title={through}>
			<span class="size-2 rounded-full bg-current {stylex.attrs(tone[TONE[live.mode]]).class}"
			></span>
			{WORD[live.mode]}
			<span class={stylex.attrs(type.figure).class}>{heard}/{TOTAL}</span>
		</span>
	</div>
</header>
