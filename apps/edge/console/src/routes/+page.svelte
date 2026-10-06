<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import Card from '#lib/card.svelte';
	import AreaChart from '#lib/chart/area-chart.svelte';
	import { type } from '#lib/style.js';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const nodes = $derived(data.cluster.ok ? Object.entries(data.cluster.data.nodes) : []);
</script>

{#if !data.cluster.ok}
	<Unread what="The cluster" failure={data.cluster.failure} />
{:else}
	<p class={stylex.attrs(type.soft).class}>
		{nodes.length} nodes held by
		<span class={stylex.attrs(type.mono).class}>{data.cluster.node}</span>
	</p>
{/if}

{#if data.cpu}
	<Card title="CPU" description="{data.cpu.node}, the last hour, a point a minute">
		{#if data.cpu.read.ok}
			<AreaChart
				lines={[
					{ key: 'cpu', label: 'Busy', color: 'var(--color-series-2)', points: data.cpu.read.data },
				]}
				since={data.cpu.since}
				until={data.cpu.until}
				ceiling={100}
				format={(value) => `${Math.round(value)}%`}
			/>
		{:else}
			<Unread what="The series" failure={data.cpu.read.failure} />
		{/if}
	</Card>
{/if}

<Card title="Nodes" flush>
	<table>
		<thead><tr><th>Node</th><th>Version</th><th>Heard</th><th>Apps</th><th>Events</th></tr></thead>
		<tbody>
			{#each nodes as [name, held] (name)}
				<tr>
					<td><a href="/nodes/{name}" class={stylex.attrs(type.mono).class}>{name}</a></td>
					<td class={stylex.attrs(type.mono).class}>{held.version}</td>
					<td class={stylex.attrs(type.mono).class}>{held.heard_at}</td>
					<td>{held.snapshot.apps.length}</td>
					<td>{held.snapshot.events.length}</td>
				</tr>
			{/each}
		</tbody>
	</table>
</Card>
