<script lang="ts">
	/**
	 * The fleet in four figures: nodes live and apps running, from the live store so they move as
	 * the nodes do; deploys in the last day and how long one takes, from the runs the page streams.
	 * Each pair holds a placeholder figure until its read lands.
	 */
	import StatTile from '../chart/stat-tile.svelte';
	import { duration, percent } from '../chart/numbers.ts';
	import type { Live } from '../live.svelte.ts';
	import { PLACES } from '../map/places.ts';
	import { liveness, running } from '../node.ts';
	import Heard from '../nodes/heard.svelte';
	import type { Figures } from './deploys.ts';

	let {
		live,
		cluster,
		deploys,
	}: {
		live: Live;
		cluster: Promise<unknown>;
		deploys: Promise<{ figures: Figures; daily: { runs: number[] } }>;
	} = $props();

	const TOTAL = Object.keys(PLACES).length;
	const held = $derived(Object.values(live.view.nodes));
	const heard = $derived(held.filter((one) => liveness(one.heard_at, live.now) === 'live').length);
	const apps = $derived(
		held
			.map(running)
			.reduce(
				(sum, one) => ({ running: sum.running + one.running, total: sum.total + one.total }),
				{ running: 0, total: 0 },
			),
	);
	const seconds = (ms: number | null) => (ms === null ? '' : duration(ms / 1000));
</script>

<div class="grid grid-cols-2 gap-4 xl:grid-cols-4">
	<Heard {live} {cluster}>
		<StatTile label="Nodes live" value={heard} unit="of {TOTAL}" />
		<StatTile label="Apps running" value={apps.running} unit="of {apps.total}" />
		{#snippet pending()}
			<StatTile label="Nodes live" pending />
			<StatTile label="Apps running" pending />
		{/snippet}
	</Heard>
	{#await deploys}
		<StatTile label="Deploys, 24 h" pending="trend" />
		<StatTile label="Median deploy, 30 d" pending="trend" />
	{:then { figures, daily }}
		<StatTile
			label="Deploys, 24 h"
			value={figures.day}
			unit={figures.rate === null ? undefined : `${percent(figures.rate)} succeeded`}
			trend={daily.runs.slice(-14)}
		/>
		<StatTile
			label="Median deploy, 30 d"
			value={figures.median === null ? '–' : seconds(figures.median)}
			unit={figures.p95 === null ? undefined : `p95 ${seconds(figures.p95)}`}
			trend={figures.durations}
		/>
	{/await}
</div>
