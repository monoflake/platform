<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import Badge from '#lib/badge.svelte';
	import Card from '#lib/card.svelte';
	import { type } from '#lib/style.js';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const placed = $derived(
		data.cluster.ok
			? Object.entries(data.cluster.data.nodes).flatMap(([node, held]) =>
					held.snapshot.apps.filter((app) => app.name === data.app).map((app) => ({ node, app })),
				)
			: [],
	);
</script>

{#if !data.cluster.ok}
	<Unread what="The cluster" failure={data.cluster.failure} />
{:else if placed.length === 0}
	<p class={stylex.attrs(type.soft).class}>No node runs {data.app}.</p>
{:else}
	<Card title="On {placed.length} nodes" flush>
		<table>
			<thead><tr><th>Node</th><th>State</th><th>Image</th><th>Deployed</th></tr></thead>
			<tbody>
				{#each placed as { node, app } (node)}
					<tr>
						<td class={stylex.attrs(type.mono).class}>{node}</td>
						<td>
							{#if app.held}<Badge tone="warn">Held</Badge>
							{:else if app.running}<Badge tone="good">Running</Badge>
							{:else}<Badge tone="bad">Stopped</Badge>{/if}
						</td>
						<td class={stylex.attrs(type.mono).class}>{app.image}</td>
						<td class={stylex.attrs(type.mono).class}>{app.deployed_at}</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</Card>
{/if}
