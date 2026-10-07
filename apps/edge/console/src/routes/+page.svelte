<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import { page } from '$app/state';
	import Card from '#lib/card.svelte';
	import BarChart from '#lib/chart/bar-chart.svelte';
	import Heatmap from '#lib/chart/heatmap.svelte';
	import StackedBar from '#lib/chart/stacked-bar.svelte';
	import { live as liveOf } from '#lib/live.svelte.js';
	import { PLACES } from '#lib/map/places.js';
	import { HEIGHT, WIDTH } from '#lib/map/land.generated.js';
	import WorldMap from '#lib/map/world-map.svelte';
	import Heard from '#lib/nodes/heard.svelte';
	import FleetCharts from '#lib/overview/fleet-charts.svelte';
	import NowPanel from '#lib/overview/now-panel.svelte';
	import Tiles from '#lib/overview/tiles.svelte';
	import { type } from '#lib/style.js';
	import PageHeader from '#lib/ui/page-header.svelte';
	import Silent from '#lib/ui/silent.svelte';
	import Skeleton from '#lib/ui/skeleton.svelte';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const live = liveOf();

	/** Every node failed, which is a failure to read rather than a quiet month. */
	const unreadOf = (missing: unknown[]) =>
		missing.length === Object.keys(PLACES).length ? 'No node answered.' : undefined;
	const percent = (value: number) => `${Math.round(value)}%`;
	/** Every read's silent nodes, said once at the top rather than under each chart. */
	const silent = $derived(
		Promise.all([data.fleet, data.deploys, data.heat]).then((reads) => [
			...new Map(reads.flatMap((read) => read.missing).map((one) => [one.node, one])).values(),
		]),
	);
	/** Rows of 24 px, an axis and a scale; see src/lib/chart/heatmap.svelte. */
	const HEAT = Object.keys(PLACES).length * 24 + 50;
	/** Rows of 28 px and the axis under them; see src/lib/chart/stacked-bar.svelte. */
	const PLACED = Object.keys(PLACES).length * 28 + 26;
</script>

<PageHeader title="Overview" range={data.range} query={page.url.search} />

{#await silent then nodes}<Silent {nodes} />{/await}

{#await data.cluster then read}
	{#if !read.ok}<Unread what="The cluster" failure={read.failure} />{/if}
{/await}

<Tiles {live} cluster={data.cluster} deploys={data.deploys} />

<div class="grid gap-4 xl:grid-cols-3">
	<div class="flex min-w-0 xl:col-span-2 [&>section]:flex-1">
		<Card title="Nodes">
			<Heard {live} cluster={data.cluster}>
				<WorldMap states={live.view.nodes} now={live.now} />
				{#snippet pending()}<Skeleton ratio="{WIDTH} / {HEIGHT}" />{/snippet}
			</Heard>
		</Card>
	</div>
	<Card title="Now">
		{#await data.moving}
			<Skeleton height={160} />
		{:then seed}
			<NowPanel {live} {seed} />
		{/await}
	</Card>
</div>

<FleetCharts fleet={data.fleet} since={data.span.since} until={data.span.until} span={data.range} />

<section class="flex flex-col gap-3">
	<h2 class={stylex.attrs(type.heading).class}>Deploys</h2>
	<Card title="Deploys per day">
		{#await data.deploys}
			<Skeleton height={200} chart />
		{:then deploys}
			<BarChart
				categories={deploys.daily.labels}
				series={[
					{
						key: 'runs',
						label: 'Runs',
						color: 'var(--color-series-8)',
						values: deploys.daily.runs,
					},
				]}
				height={200}
				error={unreadOf(deploys.missing)}
				label="Runs started per day, the last 30 days"
			/>
		{/await}
	</Card>
	<div class="grid gap-4 xl:grid-cols-2">
		<Card title="Placements by node">
			{#await data.deploys}
				<Skeleton height={PLACED} chart />
			{:then { outcomes, missing }}
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
						{
							key: 'failed',
							label: 'Failed',
							color: 'var(--color-danger)',
							values: outcomes.failed,
						},
						{
							key: 'skipped',
							label: 'Skipped',
							color: 'var(--color-text-faint)',
							values: outcomes.skipped,
						},
					]}
					error={unreadOf(missing)}
					label="Placements per node by outcome, the last 30 days"
				/>
			{/await}
		</Card>
		<Card title="CPU by the hour">
			{#await data.heat}
				<Skeleton height={HEAT} chart />
			{:then heat}
				<Heatmap
					rows={heat.rows}
					times={heat.times}
					values={heat.values}
					low={0}
					high={100}
					format={percent}
					label="CPU per node per hour, the last 24 hours"
				/>
			{/await}
		</Card>
	</div>
</section>
