<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import Card from '#lib/card.svelte';
	import { type } from '#lib/style.js';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const events = $derived(
		data.cluster.ok
			? Object.entries(data.cluster.data.nodes)
					.flatMap(([node, held]) => held.snapshot.events.map((event) => ({ node, event })))
					.toSorted((a, b) => Date.parse(b.event.started_at) - Date.parse(a.event.started_at))
			: [],
	);
</script>

{#if !data.cluster.ok}
	<Unread what="The cluster" failure={data.cluster.failure} />
{:else}
	<Card title="{events.length} events held" flush>
		<table>
			<thead>
				<tr><th>Started</th><th>Node</th><th>App</th><th>Action</th><th>Outcome</th></tr>
			</thead>
			<tbody>
				{#each events as { node, event } (`${node}/${event.id}`)}
					<tr>
						<td class={stylex.attrs(type.mono).class}>{event.started_at}</td>
						<td class={stylex.attrs(type.mono).class}>{node}</td>
						<td class={stylex.attrs(type.mono).class}>{event.app}</td>
						<td>{event.action}, by {event.source.kind}</td>
						<td>{event.outcome}</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</Card>
{/if}
