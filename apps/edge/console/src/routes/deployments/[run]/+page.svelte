<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import Card from '#lib/card.svelte';
	import { pipeline } from '#lib/pipeline.js';
	import { type } from '#lib/style.js';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const run = $derived(
		data.cluster.ok
			? pipeline(data.cluster.data.nodes).runs.find((held) => held.run === data.run)
			: undefined,
	);
</script>

{#if !data.cluster.ok}
	<Unread what="The cluster" failure={data.cluster.failure} />
{:else if !run}
	<p class={stylex.attrs(type.soft).class}>No node holds an event from run {data.run}.</p>
{:else}
	<Card title="{run.rows.length} apps" flush>
		<table>
			<thead><tr><th>App</th><th>Node</th><th>Outcome</th><th>Stage</th></tr></thead>
			<tbody>
				{#each run.rows as row (row.app)}
					{#each Object.values(row.cells) as cell (cell.node)}
						<tr>
							<td class={stylex.attrs(type.mono).class}>{row.app}</td>
							<td class={stylex.attrs(type.mono).class}>{cell.node}</td>
							<td>{cell.event.outcome}</td>
							<td>{cell.event.stage ?? ''}</td>
						</tr>
					{/each}
				{/each}
			</tbody>
		</table>
	</Card>
{/if}
