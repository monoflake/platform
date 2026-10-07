<script lang="ts">
	import { untrack } from 'svelte';
	import Card from '#lib/card.svelte';
	import { live } from '#lib/live.svelte.js';
	import { Clock } from '#lib/nodes/clock.svelte.js';
	import { machineFor, nodeRow } from '#lib/nodes/machine.js';
	import NodeApps from '#lib/nodes/node-apps.svelte';
	import NodeDisk from '#lib/nodes/node-disk.svelte';
	import NodeEvents from '#lib/nodes/node-events.svelte';
	import NodeHeader from '#lib/nodes/node-header.svelte';
	import NodeOverview from '#lib/nodes/node-overview.svelte';
	import { TABS, hrefOf } from '#lib/nodes/view.js';
	import Segmented, { RANGES } from '#lib/ui/segmented.svelte';
	import Tabs from '#lib/ui/tabs.svelte';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const held = live();
	// The server's time once, so the first paint agrees; the clock ticks on its own after.
	const clock = new Clock(untrack(() => data.now));

	const server = $derived(data.machine.ok ? data.machine.data : undefined);
	const machine = $derived(machineFor(held.view.nodes[data.name], server));
	const row = $derived(nodeRow(data.name, held.view.nodes[data.name], server, clock.now));
	const tabs = $derived(
		TABS.map((tab) => ({
			...tab,
			href: hrefOf({ ...data.view, tab: tab.key, before: undefined }),
		})),
	);
	const ranges = $derived(
		RANGES.map((range) => ({ ...range, href: hrefOf({ ...data.view, range: range.key }) })),
	);
</script>

<NodeHeader {row} info={machine?.info} now={clock.now}>
	{#snippet actions()}
		{#if data.view.tab === 'overview'}
			<Segmented options={ranges} value={data.view.range} label="Time range" />
		{/if}
	{/snippet}
</NodeHeader>

{#if !data.machine.ok}
	<Unread what="The machine" failure={data.machine.failure} />
{/if}

<div>
	<Tabs {tabs} current={data.view.tab} label="{data.name}'s views" />

	{#if data.view.tab === 'overview' && data.charts}
		<div class="flex flex-col gap-4">
			<NodeOverview
				{machine}
				charts={data.charts}
				marks={data.marks}
				span={data.span}
				reveal={data.view.range}
			/>
		</div>
	{:else if data.view.tab === 'apps' && data.apps}
		{#if data.apps.ok}
			<Card title="{data.apps.data.length} apps" flush>
				<NodeApps apps={data.apps.data} now={clock.now} />
			</Card>
		{:else}
			<Unread what="The apps" failure={data.apps.failure} />
		{/if}
	{:else if data.view.tab === 'events' && data.events}
		{#if data.events.read.ok}
			<Card title="Events" flush>
				<NodeEvents
					events={data.events.read.data}
					newer={data.view.before === undefined
						? undefined
						: hrefOf({ ...data.view, before: undefined })}
					older={data.events.older === undefined
						? undefined
						: hrefOf({ ...data.view, before: data.events.older })}
				/>
			</Card>
		{:else}
			<Unread what="The events" failure={data.events.read.failure} />
		{/if}
	{:else if data.view.tab === 'disk' && data.disk}
		{#if data.disk.ok}
			<div class="flex flex-col gap-4"><NodeDisk disk={data.disk.data} /></div>
		{:else}
			<Unread what="The disk" failure={data.disk.failure} />
		{/if}
	{/if}
</div>
