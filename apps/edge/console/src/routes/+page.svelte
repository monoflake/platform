<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import { page } from '$app/state';
	import Card from '#lib/card.svelte';
	import BarChart from '#lib/chart/bar-chart.svelte';
	import Heatmap from '#lib/chart/heatmap.svelte';
	import StackedBar from '#lib/chart/stacked-bar.svelte';
	import { live as liveOf } from '#lib/live.svelte.js';
	import { PLACES } from '#lib/map/places.js';
	import WorldMap from '#lib/map/world-map.svelte';
	import { liveness, type Liveness } from '#lib/node.js';
	import FleetCharts from '#lib/overview/fleet-charts.svelte';
	import NowPanel from '#lib/overview/now-panel.svelte';
	import Tiles from '#lib/overview/tiles.svelte';
	import { type } from '#lib/style.js';
	import Badge from '#lib/ui/badge.svelte';
	import PageHeader from '#lib/ui/page-header.svelte';
	import Silent from '#lib/ui/silent.svelte';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const live = liveOf();

	const STATES = [
		{ state: 'live', word: 'Live', tone: 'good' },
		{ state: 'late', word: 'Late', tone: 'warn' },
		{ state: 'gone', word: 'Gone', tone: 'bad' },
	] as const;
	const counts = $derived.by(() => {
		const tally: Record<Liveness, number> = { live: 0, late: 0, gone: 0 };
		for (const code of Object.keys(PLACES)) {
			const held = live.view.nodes[code];
			tally[held ? liveness(held.heard_at, live.now) : 'gone'] += 1;
		}
		return tally;
	});
	const outcomes = $derived(data.deploys.outcomes);
	/** Every node failed, which is a failure to read rather than a quiet month. */
	const unread = $derived(
		data.deploys.missing.length === Object.keys(PLACES).length ? 'No node answered.' : undefined,
	);
	const percent = (value: number) => `${Math.round(value)}%`;
	/** Every read's silent nodes, said once at the top rather than under each chart. */
	const silent = $derived([
		...new Map(
			[...data.fleet.missing, ...data.deploys.missing, ...data.heat.missing].map((one) => [
				one.node,
				one,
			]),
		).values(),
	]);
</script>

<PageHeader title="Overview" range={data.range} query={page.url.search} />

<Silent nodes={silent} />

{#if !data.cluster.ok}
	<Unread what="The cluster" failure={data.cluster.failure} />
{/if}

<Tiles {live} figures={data.deploys.figures} daily={data.deploys.daily.runs} />

<div class="grid gap-4 xl:grid-cols-3">
	<div class="flex min-w-0 xl:col-span-2 [&>section]:flex-1">
		<Card title="Nodes">
			{#snippet aside()}
				<div class="flex flex-wrap items-center gap-2">
					{#each STATES as one (one.state)}
						<Badge tone={one.tone}>{counts[one.state]} {one.word.toLowerCase()}</Badge>
					{/each}
				</div>
			{/snippet}
			<WorldMap states={live.view.nodes} now={live.now} />
		</Card>
	</div>
	<Card title="Now">
		<NowPanel {live} seed={data.moving} />
	</Card>
</div>

<FleetCharts fleet={data.fleet} since={data.span.since} until={data.span.until} span={data.range} />

<section class="flex flex-col gap-3">
	<h2 class={stylex.attrs(type.heading).class}>Deploys</h2>
	<Card title="Deploys per day">
		<BarChart
			categories={data.deploys.daily.labels}
			series={[
				{
					key: 'runs',
					label: 'Runs',
					color: 'var(--color-series-8)',
					values: data.deploys.daily.runs,
				},
			]}
			height={200}
			error={unread}
			label="Runs started per day, the last 30 days"
		/>
	</Card>
	<div class="grid gap-4 xl:grid-cols-2">
		<Card title="Placements by node">
			<StackedBar
				categories={outcomes.nodes}
				orientation="horizontal"
				series={[
					{
						key: 'succeeded',
						label: 'Succeeded',
						color: 'var(--color-good)',
						values: outcomes.succeeded,
					},
					{ key: 'failed', label: 'Failed', color: 'var(--color-danger)', values: outcomes.failed },
					{
						key: 'skipped',
						label: 'Skipped',
						color: 'var(--color-text-faint)',
						values: outcomes.skipped,
					},
				]}
				error={unread}
				label="Placements per node by outcome, the last 30 days"
			/>
		</Card>
		<Card title="CPU by the hour">
			<Heatmap
				rows={data.heat.rows}
				times={data.heat.times}
				values={data.heat.values}
				low={0}
				high={100}
				format={percent}
				label="CPU per node per hour, the last 24 hours"
			/>
		</Card>
	</div>
</section>
