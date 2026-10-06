<script lang="ts">
	/**
	 * The fleet in four figures: nodes live and apps running, from the live store so they move as
	 * the nodes do; deploys in the last day and how long one takes, from the runs the page loaded.
	 */
	import StatTile from '../chart/stat-tile.svelte';
	import { duration, percent } from '../chart/numbers.ts';
	import type { Live } from '../live.svelte.ts';
	import { PLACES } from '../map/places.ts';
	import { liveness, running } from '../node.ts';
	import type { Figures } from './deploys.ts';

	let { live, figures, daily }: { live: Live; figures: Figures; daily: number[] } = $props();

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
	<StatTile label="Nodes live" value={heard} unit="of {TOTAL}" />
	<StatTile label="Apps running" value={apps.running} unit="of {apps.total}, across every node" />
	<StatTile
		label="Deploys, last 24 h"
		value={figures.day}
		unit={figures.rate === null ? 'none finished' : `${percent(figures.rate)} succeeded`}
		trend={daily.slice(-14)}
	/>
	<StatTile
		label="Median deploy"
		value={figures.median === null ? 'None' : seconds(figures.median)}
		unit={figures.p95 === null ? '30 days' : `p95 ${seconds(figures.p95)}, 30 days`}
		trend={figures.durations}
	/>
</div>
