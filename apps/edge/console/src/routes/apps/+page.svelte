<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import Card from '#lib/card.svelte';
	import { type } from '#lib/style.js';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	/** Each app once, with the nodes that run it. */
	const apps = $derived.by(() => {
		if (!data.cluster.ok) return [];
		const placed = new Map<string, string[]>();
		for (const [node, held] of Object.entries(data.cluster.data.nodes)) {
			for (const app of held.snapshot.apps) {
				placed.set(app.name, [...(placed.get(app.name) ?? []), node]);
			}
		}
		return [...placed].toSorted(([a], [b]) => a.localeCompare(b));
	});
</script>

{#if !data.cluster.ok}
	<Unread what="The cluster" failure={data.cluster.failure} />
{:else}
	<Card title="{apps.length} apps" flush>
		<table>
			<thead><tr><th>App</th><th>Nodes</th></tr></thead>
			<tbody>
				{#each apps as [name, nodes] (name)}
					<tr>
						<td><a href="/apps/{name}" class={stylex.attrs(type.mono).class}>{name}</a></td>
						<td class={stylex.attrs(type.mono).class}>{nodes.toSorted().join(' ')}</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</Card>
{/if}
