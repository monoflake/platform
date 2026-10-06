<script lang="ts">
	import { untrack } from 'svelte';
	import Card from '#lib/card.svelte';
	import { percent } from '#lib/chart/numbers.js';
	import StatTile from '#lib/chart/stat-tile.svelte';
	import { live } from '#lib/live.svelte.js';
	import WorldMap from '#lib/map/world-map.svelte';
	import { Clock } from '#lib/nodes/clock.svelte.js';
	import { CODES, FACTS } from '#lib/nodes/facts.js';
	import { nodeRow, type NodeRow } from '#lib/nodes/machine.js';
	import NodesTable from '#lib/nodes/nodes-table.svelte';
	import { LIVENESS } from '#lib/nodes/words.js';
	import Badge from '#lib/ui/badge.svelte';
	import PageHeader from '#lib/ui/page-header.svelte';
	import Unread from '#lib/unread.svelte';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const held = live();
	// The server's time once, so the first paint agrees; the clock ticks on its own after.
	const clock = new Clock(untrack(() => data.now));

	const rows: NodeRow[] = $derived(
		CODES.map((code) => nodeRow(code, held.view.nodes[code], data.machines[code], clock.now)),
	);
	const counts = $derived(
		(['live', 'late', 'gone'] as const).map((state) => ({
			state,
			count: rows.filter((row) => row.state === state).length,
		})),
	);
	const heard = $derived(rows.filter((row) => row.state !== 'gone'));
	const apps = $derived(
		rows.reduce(
			(sum, row) => ({
				running: sum.running + (row.apps?.running ?? 0),
				total: sum.total + (row.apps?.total ?? 0),
			}),
			{ running: 0, total: 0 },
		),
	);
	const busy = $derived.by(() => {
		const read = heard.flatMap((row) => (row.cpu === undefined ? [] : [row.cpu]));
		return read.length ? read.reduce((a, b) => a + b, 0) / read.length : undefined;
	});
	const memory = $derived.by(() => {
		const read = heard.flatMap((row) => (row.memory?.total ? [row.memory] : []));
		const total = read.reduce((sum, one) => sum + (one.total ?? 0), 0);
		return total ? read.reduce((sum, one) => sum + one.used, 0) / total : undefined;
	});
	const domains = new Set(Object.values(FACTS).map((facts) => facts.domain)).size;
	const unread = $derived(Object.keys(data.failures).length);
</script>

<PageHeader title="Nodes" description="{CODES.length} machines in {domains} failure domains">
	{#snippet meta()}
		{#each counts as { state, count } (state)}
			{#if count}<Badge tone={LIVENESS[state].tone}>{count} {LIVENESS[state].word}</Badge>{/if}
		{/each}
	{/snippet}
</PageHeader>

{#if !data.cluster.ok}
	<Unread what="The cluster" failure={data.cluster.failure} />
{/if}

<div class="grid gap-4 lg:grid-cols-[minmax(0,5fr)_minmax(0,4fr)]">
	<Card title="Where they are" description="Hover a node for its card; a click opens it">
		<WorldMap states={held.view.nodes} now={clock.now} compact />
	</Card>
	<div class="grid grid-cols-2 gap-4">
		<StatTile label="Heard" value="{heard.length} of {CODES.length}" />
		<StatTile label="Apps running" value="{apps.running} of {apps.total}" />
		<StatTile
			label="CPU busy, heard nodes"
			value={busy === undefined ? '–' : percent(busy / 100)}
		/>
		<StatTile
			label="Memory in use, heard nodes"
			value={memory === undefined ? '–' : percent(memory)}
		/>
	</div>
</div>

<Card
	title="Every node"
	description={unread
		? `${unread} of ${CODES.length} did not answer the server; their rows hold what the relay does`
		: 'Live from the relay; CPU over the last hour, a point a minute'}
	flush
>
	<NodesTable {rows} trends={data.trends} now={clock.now} />
</Card>
