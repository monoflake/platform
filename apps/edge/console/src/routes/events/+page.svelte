<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import Card from '#lib/card.svelte';
	import StackedBar from '#lib/chart/stacked-bar.svelte';
	import Heatmap from '#lib/chart/heatmap.svelte';
	import { moment } from '#lib/chart/series.js';
	import { OUTCOMES } from '#lib/events/counts.js';
	import EventsTable from '#lib/events/events-table.svelte';
	import Filters from '#lib/events/filters.svelte';
	import { search } from '#lib/events/query.js';
	import { type } from '#lib/style.js';
	import PageHeader from '#lib/ui/page-header.svelte';
	import { timeZone } from '#lib/ui/time-zone.js';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const zone = timeZone();
	const COLORS = {
		succeeded: 'var(--color-good)',
		failed: 'var(--color-danger)',
		skipped: 'var(--color-text-muted)',
		running: 'var(--color-busy)',
	};
	const dayLabel = new Intl.DateTimeFormat('en-US', {
		timeZone: zone,
		month: 'short',
		day: 'numeric',
	});

	const failed = $derived(Object.entries(data.failures));
	const bars = $derived(
		OUTCOMES.map((outcome, row) => ({
			key: outcome,
			label: outcome[0]?.toUpperCase() + outcome.slice(1),
			color: COLORS[outcome],
			values: data.charts.days.values[row] ?? [],
		})),
	);
	const paged = $derived(Object.keys(data.query.before).length > 0);
	const range = $derived(
		data.events.length
			? `${moment(Date.parse(data.events.at(-1)?.started_at ?? '') / 1000, zone)} back to ${moment(Date.parse(data.events[0]?.started_at ?? '') / 1000, zone)}`
			: '',
	);
</script>

<PageHeader title="Events" description="Every event every node has kept, newest first." />

{#if failed.length}
	<div class="mb-4 flex flex-col gap-1 p-4 {stylex.attrs(type.body).class}" role="status">
		{#each failed as [name, failure] (name)}
			<p>
				<span class={stylex.attrs(type.mono).class}>{name}</span> is unreachable and its events are
				missing: {failure.message}
			</p>
		{/each}
	</div>
{/if}

<div class="mb-4"><Filters query={data.query} nodes={data.nodes} options={data.options} /></div>

<div class="mb-4 grid gap-4 xl:grid-cols-2">
	<Card title="Events per hour" description="By node, over the last 24 hours, in your time zone.">
		<Heatmap
			rows={data.nodes.map((node) => ({ key: node, label: node }))}
			times={data.charts.hours.times}
			values={data.charts.hours.values}
			steps={5}
			low={0}
			label="Events per hour per node over the last 24 hours"
		/>
	</Card>
	<Card title="Outcomes per day" description="Over the last 7 days.">
		<StackedBar
			categories={data.charts.days.times.map((at) => dayLabel.format(new Date(at * 1000)))}
			series={bars}
			label="Event outcomes per day over the last 7 days"
		/>
	</Card>
</div>
<p class="mb-4 {stylex.attrs(type.soft).class}">
	The charts count {data.charts.covered} of the {data.charts.loaded} newest events loaded, matching the
	filters{#if data.charts.full.length}; {data.charts.full.join(', ')} serve at most 500 events each, so
		their older hours may be undercounted{/if}.
</p>

<Card title="Log" flush>
	<EventsTable events={data.events} />
	<footer
		class="flex flex-wrap items-center justify-between gap-3 px-5 py-2.5 {stylex.attrs(type.soft)
			.class}"
	>
		<span>{data.events.length} events{range ? `, ${range}` : ''}</span>
		<span class="flex items-center gap-4">
			{#if paged}<a href="/events{search(data.query, {})}">Newest</a>{/if}
			{#if data.more}<a href="/events{search(data.query, data.next)}" rel="next">Older</a>{/if}
		</span>
	</footer>
</Card>
