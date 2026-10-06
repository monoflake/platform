<script lang="ts">
	/** The page's title, whether the console is live or polling, and the node it hears through. */
	import * as stylex from '@stylexjs/stylex';
	import Badge from './badge.svelte';
	import type { Live } from './live.svelte.ts';
	import { surfaces, type } from './style.ts';
	import { CONTRACT } from './wire.ts';

	let { title, detail, live }: { title: string; detail?: string; live: Live } = $props();

	const WORD = { connecting: 'Connecting', live: 'Live', polling: 'Polling every 5 s' } as const;
	const TONE = { connecting: 'quiet', live: 'good', polling: 'warn' } as const;
</script>

<header
	class="sticky top-0 z-20 flex h-14 items-center justify-between gap-4 px-8 backdrop-blur {stylex.attrs(
		surfaces.bar,
	).class}"
>
	<h1 class="flex min-w-0 items-baseline gap-2 truncate {stylex.attrs(type.title).class}">
		{title}
		{#if detail}<span class={stylex.attrs(type.mono, type.soft).class}>{detail}</span>{/if}
	</h1>
	<div class="flex shrink-0 items-center gap-3">
		{#if live.view.refused !== undefined}
			<span class={stylex.attrs(type.soft).class}>
				The relay speaks contract {live.view.refused}; this console reads {CONTRACT}.
			</span>
		{/if}
		{#if live.mode === 'polling' && live.failure}
			<span class={stylex.attrs(type.soft).class} title={live.failure}>Last poll failed</span>
		{/if}
		{#if live.view.via}
			<span class={stylex.attrs(type.soft).class}>
				through <span class={stylex.attrs(type.mono).class}>{live.view.via}</span>
			</span>
		{/if}
		<Badge tone={TONE[live.mode]}>{WORD[live.mode]}</Badge>
	</div>
</header>
