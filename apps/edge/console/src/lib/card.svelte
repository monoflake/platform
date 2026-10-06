<script lang="ts">
	/** A titled surface on the ground; `flush` runs its content to the edges, as a table does. */
	import * as stylex from '@stylexjs/stylex';
	import type { Snippet } from 'svelte';
	import { surfaces, type } from './style.ts';

	let {
		title,
		description,
		flush = false,
		children,
	}: { title?: string; description?: string; flush?: boolean; children: Snippet } = $props();
</script>

<section class="flex min-w-0 flex-col {stylex.attrs(surfaces.card).class}">
	{#if title}
		<header class="flex flex-col gap-1 px-5 pt-4 {flush ? 'pb-3' : ''}">
			<h2 class={stylex.attrs(type.heading).class}>{title}</h2>
			{#if description}<p class={stylex.attrs(type.soft).class}>{description}</p>{/if}
		</header>
	{/if}
	<div class={flush ? 'overflow-x-auto' : 'px-5 pt-3 pb-5'}>
		{@render children()}
	</div>
</section>
