<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import { onMount } from 'svelte';
	import Apps from '#lib/apps.svelte';
	import { listen, type Mode } from '#lib/feed.js';
	import NodeCard from '#lib/node-card.svelte';
	import Pipeline from '#lib/pipeline.svelte';
	import { pipeline } from '#lib/pipeline.js';
	import { type } from '#lib/style.js';
	import { EMPTY, merge, mergeCluster } from '#lib/view.js';
	import { CONTRACT } from '#lib/wire.js';

	/** Replaced whole on every message that holds anything newer; see src/lib/view.ts. */
	let view = $state.raw(EMPTY);
	let mode: Mode = $state('connecting');
	let failure: string | undefined = $state();
	/** The clock relative times and liveness are read against, a tick a second. */
	let now = $state(Date.now());

	// On mount, not in an effect: an effect reruns on what it reads, reopening the socket.
	onMount(() => {
		const stop = listen({
			live: (message) => (view = merge(view, message)),
			polled: (cluster) => (view = mergeCluster(view, cluster)),
			mode: (next) => (mode = next),
			failure: (why) => (failure = why),
		});
		const clock = setInterval(() => (now = Date.now()), 1000);
		return () => {
			stop();
			clearInterval(clock);
		};
	});

	const nodes = $derived(Object.entries(view.nodes).toSorted(([a], [b]) => a.localeCompare(b)));
	const names = $derived(nodes.map(([name]) => name));
	const runs = $derived(pipeline(view.nodes));

	const MODE_WORD: Record<Mode, string> = {
		connecting: 'Connecting',
		live: 'Live',
		polling: 'Polling every 5 s',
	};
</script>

<p class="flex flex-wrap gap-x-3 {stylex.attrs(type.soft).class}">
	<span>
		{MODE_WORD[mode]}{#if view.via && mode !== 'connecting'}, through {view.via}{/if}
	</span>
	{#if mode === 'polling' && failure}<span title={failure}>Last poll failed</span>{/if}
	{#if view.refused !== undefined}
		<span>The relay speaks contract {view.refused}; this console reads {CONTRACT}.</span>
	{/if}
</p>

<section class="flex flex-col gap-3" aria-labelledby="nodes">
	<h2 id="nodes" class={stylex.attrs(type.heading).class}>Nodes</h2>
	{#if nodes.length === 0}
		<p class={stylex.attrs(type.soft).class}>
			{mode === 'connecting' ? 'Waiting for the first answer.' : 'No node heard yet.'}
		</p>
	{:else}
		<div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
			{#each nodes as [name, held] (name)}
				<NodeCard {name} {held} {now} />
			{/each}
		</div>
	{/if}
</section>

<section class="flex flex-col gap-3" aria-labelledby="pipeline">
	<h2 id="pipeline" class={stylex.attrs(type.heading).class}>Pipeline</h2>
	<Pipeline pipeline={runs} nodes={names} {now} />
</section>

<section class="flex flex-col gap-3" aria-labelledby="apps">
	<h2 id="apps" class={stylex.attrs(type.heading).class}>Apps</h2>
	{#if nodes.length === 0}
		<p class={stylex.attrs(type.soft).class}>No node heard yet.</p>
	{:else}
		<Apps {nodes} {now} />
	{/if}
</section>
