<script lang="ts">
	/** Each node's apps as it last listed them. */
	import * as stylex from '@stylexjs/stylex';
	import Badge from './badge.svelte';
	import { ago, localTime, shortImage } from './format.ts';
	import { surfaces, type } from './style.ts';
	import type { Held } from './wire.ts';

	let { nodes, now }: { nodes: [string, Held][]; now: number } = $props();

	const byName = (a: { name: string }, b: { name: string }) => a.name.localeCompare(b.name);
</script>

<div class="grid gap-4 md:grid-cols-2">
	{#each nodes as [node, held] (node)}
		<article class="flex min-w-0 flex-col {stylex.attrs(surfaces.card).class}">
			<header class="flex items-center justify-between gap-2 px-4 pt-3 pb-2">
				<h3 class={stylex.attrs(type.name, type.mono).class}>{node}</h3>
				{#if held.snapshot.stale?.includes('apps')}
					<Badge tone="warn" title="The node's last read of its apps failed.">Stale</Badge>
				{/if}
			</header>
			{#if held.snapshot.apps.length === 0}
				<p class="px-4 pb-3 {stylex.attrs(type.soft).class}">No apps deployed.</p>
			{:else}
				<ul class="flex flex-col">
					{#each held.snapshot.apps.toSorted(byName) as app (app.name)}
						<li
							class="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-2 {stylex.attrs(
								surfaces.rowRule,
							).class}"
						>
							<span class="min-w-24 {stylex.attrs(type.mono, type.body).class}">{app.name}</span>
							{#if app.held}
								<Badge tone="warn">Held</Badge>
							{:else if app.running}
								<Badge tone="good">Running</Badge>
							{:else}
								<Badge tone="bad">Stopped</Badge>
							{/if}
							<span class={stylex.attrs(type.mono, type.soft).class} title={app.image}>
								{shortImage(app.image)}
							</span>
							<span
								class="ml-auto {stylex.attrs(type.soft).class}"
								title={localTime(app.deployed_at)}
							>
								{ago(app.deployed_at, now)}
							</span>
						</li>
					{/each}
				</ul>
			{/if}
		</article>
	{/each}
</div>
