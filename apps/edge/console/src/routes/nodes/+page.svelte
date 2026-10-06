<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import Card from '#lib/card.svelte';
	import { running } from '#lib/node.js';
	import { type } from '#lib/style.js';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const nodes = $derived(
		data.cluster.ok
			? Object.entries(data.cluster.data.nodes).toSorted(([a], [b]) => a.localeCompare(b))
			: [],
	);
</script>

{#if !data.cluster.ok}
	<Unread what="The cluster" failure={data.cluster.failure} />
{:else}
	<Card title="{nodes.length} nodes" flush>
		<table>
			<thead><tr><th>Node</th><th>Heard</th><th>Running</th><th>Stale</th></tr></thead>
			<tbody>
				{#each nodes as [name, held] (name)}
					{@const apps = running(held)}
					<tr>
						<td><a href="/nodes/{name}" class={stylex.attrs(type.mono).class}>{name}</a></td>
						<td class={stylex.attrs(type.mono).class}>{held.heard_at}</td>
						<td>{apps.running} of {apps.total}</td>
						<td>{held.snapshot.stale?.join(', ') ?? ''}</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</Card>
{/if}
