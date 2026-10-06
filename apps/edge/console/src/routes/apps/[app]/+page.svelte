<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import { drifts, latest, lines, merge, placements, total } from '#lib/apps/apps.js';
	import HistoryTable from '#lib/apps/history-table.svelte';
	import StateBadge from '#lib/apps/state-badge.svelte';
	import UsageCharts from '#lib/apps/usage-charts.svelte';
	import Card from '#lib/card.svelte';
	import StatTile from '#lib/chart/stat-tile.svelte';
	import { moment } from '#lib/chart/series.js';
	import { bytes, shortImage } from '#lib/format.js';
	import { surfaces, type } from '#lib/style.js';
	import Badge from '#lib/ui/badge.svelte';
	import PageHeader from '#lib/ui/page-header.svelte';
	import Segmented, { RANGES } from '#lib/ui/segmented.svelte';
	import { timeZone } from '#lib/ui/time-zone.js';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const zone = timeZone();
	const options = RANGES.map(({ key, label }) => ({ key, label, href: `?range=${key}` }));

	const held = $derived(data.cluster.ok ? placements(data.order, data.cluster.data, data.app) : []);
	const running = $derived(held.filter((one) => one.state === 'running').length);
	const images = $derived([...new Set(held.map((one) => one.app.image))]);
	const drift = $derived(drifts(images));
	const history = $derived(merge(data.order, data.events));
	/** Nodes asked that did not answer one of the reads: unknown, not absent. */
	const silent = $derived(
		Object.entries(data.series)
			.filter(([, read]) => !read.ok)
			.map(([node]) => node),
	);

	const sum = (name: string) => total(lines(data.order, data.series, `${data.app}.${name}`).lines);
	const nowOf = (name: string) =>
		Object.values(latest(lines(data.order, data.series, `${data.app}.${name}`).lines)).reduce(
			(a, b) => a + b,
			0,
		);
	const trend = (name: string) =>
		sum(name)
			.slice(-12)
			.map((point) => point.value);
	const known = $derived(Object.values(data.series).some((read) => read.ok));
</script>

<PageHeader
	title={data.app}
	back={{ href: '/apps', label: 'Apps' }}
	description={images.map(shortImage).join(', ')}
>
	{#snippet meta()}
		{#if data.cluster.ok}
			<Badge tone={running === held.length ? 'good' : 'warn'}>
				{running} of {held.length} nodes running
			</Badge>
			{#if drift}<Badge tone="warn">Image drift, {images.length} images</Badge>{/if}
		{/if}
	{/snippet}
	{#snippet actions()}
		<Segmented {options} value={data.range} label="Range" />
	{/snippet}
</PageHeader>

{#if !data.cluster.ok}
	<Unread what="The cluster" failure={data.cluster.failure} />
{/if}

{#if known}
	<div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
		<StatTile label="Processor now" value={nowOf('cpu').toFixed(1)} unit="%" trend={trend('cpu')} />
		<StatTile label="Memory now" value={bytes(nowOf('memory'))} trend={trend('memory')} />
		<StatTile
			label="Network now"
			value={`${bytes(nowOf('network.received'))}/s`}
			unit="in"
			trend={trend('network.received')}
		/>
		<StatTile
			label="Disk now"
			value={`${bytes(nowOf('disk.read'))}/s`}
			unit="read"
			trend={trend('disk.read')}
		/>
	</div>
{/if}

{#if held.length}
	<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
		{#each held as one (one.node)}
			<div class="flex flex-col gap-2 px-5 py-4 {stylex.attrs(surfaces.card).class}">
				<div class="flex items-center justify-between gap-2">
					<a href="/nodes/{one.node}" class={stylex.attrs(type.name).class}>{one.node}</a>
					<StateBadge state={one.state} />
				</div>
				<span class={stylex.attrs(type.mono).class} title={one.app.image}
					>{shortImage(one.app.image)}</span
				>
				<span class={stylex.attrs(type.soft).class}>
					Deployed {moment(Date.parse(one.app.deployed_at) / 1000, zone)}
				</span>
				{#if silent.includes(one.node)}<Badge tone="quiet">Metrics unknown</Badge>{/if}
			</div>
		{/each}
	</div>
{:else if silent.length}
	<p class={stylex.attrs(type.soft).class}>State unknown on {silent.join(', ')}.</p>
{/if}

<UsageCharts
	app={data.app}
	order={data.order}
	reads={data.series}
	since={data.span.since}
	until={data.span.until}
	reveal={data.range}
/>

<Card title="Deploy history" flush>
	<HistoryTable events={history.events} />
</Card>
{#if history.unknown.length}
	<p class={stylex.attrs(type.soft).class}>History unknown on {history.unknown.join(', ')}.</p>
{/if}
