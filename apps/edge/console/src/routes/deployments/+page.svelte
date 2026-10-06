<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import Badge from '#lib/badge.svelte';
	import Card from '#lib/card.svelte';
	import { pipeline } from '#lib/pipeline.js';
	import { type } from '#lib/style.js';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const runs = $derived(data.cluster.ok ? pipeline(data.cluster.data.nodes).runs : []);
	const TONE = { running: 'busy', failed: 'bad', done: 'good' } as const;
</script>

{#if !data.cluster.ok}
	<Unread what="The cluster" failure={data.cluster.failure} />
{:else}
	<Card title="{runs.length} runs held" flush>
		<table>
			<thead><tr><th>Run</th><th>Commit</th><th>State</th><th>Apps</th><th>Started</th></tr></thead>
			<tbody>
				{#each runs as run (run.run)}
					<tr>
						<td>
							<a href="/deployments/{run.run}" class={stylex.attrs(type.mono).class}>{run.run}</a>
						</td>
						<td class={stylex.attrs(type.mono).class}>{run.commit?.slice(0, 7) ?? ''}</td>
						<td><Badge tone={TONE[run.state]}>{run.state}</Badge></td>
						<td>{run.rows.length}</td>
						<td class={stylex.attrs(type.mono).class}>{run.started_at}</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</Card>
{/if}
