<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import Card from '#lib/card.svelte';
	import { duration, percent } from '#lib/chart/numbers.js';
	import StackedBar from '#lib/chart/stacked-bar.svelte';
	import StatTile from '#lib/chart/stat-tile.svelte';
	import { daily, within } from '#lib/deployments/daily.js';
	import Events from '#lib/deployments/events.svelte';
	import { Fresh } from '#lib/deployments/fresh.svelte.js';
	import Queue from '#lib/deployments/queue.svelte';
	import { stirring } from '#lib/deployments/stir.js';
	import { live } from '#lib/live.svelte.js';
	import type { Node } from '#lib/server/nodes.js';
	import { surfaces, type } from '#lib/style.js';
	import Silent from '#lib/ui/silent.svelte';
	import PageHeader from '#lib/ui/page-header.svelte';
	import Tabs from '#lib/ui/tabs.svelte';
	import { timeZone } from '#lib/ui/time-zone.js';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const zone = timeZone();
	const held = live();
	const newest = $derived(
		data.runs.length ? Math.max(...data.runs.map((run) => run.run)) : undefined,
	);
	const fresh = new Fresh(
		() => data.now,
		() => data.runs.some((run) => run.running > 0) || stirring(held.view.nodes, newest),
	);

	let tab: 'runs' | 'apart' = $state('runs');

	const unknown = $derived(new Set(Object.keys(data.failures) as Node[]));
	const missing = $derived(Object.entries(data.failures));
	const bars = $derived(daily(data.runs, fresh.now, data.days, zone));
	const day = $derived(within(data.runs, fresh.now, 24));
	const going = $derived(data.runs.filter((run) => run.running > 0).length);
	const seconds = (ms: number | null) => (ms === null ? '-' : duration(ms / 1000));
</script>

<PageHeader title="Deployments" />

<Silent nodes={missing.map(([node, failure]) => ({ node, message: failure.message }))} />

<div class="grid grid-cols-2 gap-4 xl:grid-cols-5">
	<StatTile label="Runs, last 24 h" value={day} />
	<StatTile
		label="Success rate, {data.days} days"
		value={data.aggregates.success_rate === null ? '-' : percent(data.aggregates.success_rate)}
	/>
	<StatTile label="Median duration" value={seconds(data.aggregates.median)} />
	<StatTile label="p95 duration" value={seconds(data.aggregates.p95)} />
	<StatTile label="Deploying now" value={going} />
</div>

<Card title="Runs per day">
	<StackedBar
		categories={bars.categories}
		series={bars.series}
		label="Runs per day over the last {data.days} days, by state"
	/>
</Card>

<section class="flex min-w-0 flex-col">
	<Tabs
		bind:current={tab}
		label="What the nodes deployed"
		tabs={[
			{ key: 'runs', label: `CI runs (${data.runs.length})` },
			{ key: 'apart', label: `Uploads and panel (${data.apart.length})` },
		]}
	/>
	<div class="overflow-hidden {stylex.attrs(surfaces.card).class}">
		{#if tab === 'runs'}
			<Queue runs={data.runs} nodes={data.nodes} {unknown} now={fresh.now} />
		{:else}
			<Events
				events={data.apart}
				label="Uploads and panel actions across every node, newest first"
				empty="No node holds an upload or a panel action."
			/>
		{/if}
	</div>
</section>
