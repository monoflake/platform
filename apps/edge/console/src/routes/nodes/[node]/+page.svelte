<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import Card from '#lib/card.svelte';
	import { bytes } from '#lib/format.js';
	import { type } from '#lib/style.js';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const held = $derived(data.cluster.ok ? data.cluster.data.nodes[data.name] : undefined);
</script>

{#if !data.now.ok}
	<Unread what="The machine" failure={data.now.failure} />
{:else}
	{@const { info, sample } = data.now.data}
	<Card title="Machine" flush>
		<table>
			<tbody>
				<tr><th>Model</th><td>{info.model ?? '–'}</td></tr>
				<tr><th>Kernel</th><td class={stylex.attrs(type.mono).class}>{info.kernel ?? '–'}</td></tr>
				<tr><th>Cores</th><td>{info.cores}</td></tr>
				<tr><th>Memory</th><td>{bytes(info.memory)}</td></tr>
				<tr><th>Metrics this second</th><td>{Object.keys(sample.values).length}</td></tr>
			</tbody>
		</table>
	</Card>
{/if}

{#if !data.cluster.ok}
	<Unread what="The cluster" failure={data.cluster.failure} />
{:else if held}
	<p class={stylex.attrs(type.soft).class}>
		{held.snapshot.apps.length} apps and {held.snapshot.events.length} events, heard at
		<span class={stylex.attrs(type.mono).class}>{held.heard_at}</span>
	</p>
{:else}
	<p class={stylex.attrs(type.soft).class}>The relay holds nothing of {data.name}.</p>
{/if}
