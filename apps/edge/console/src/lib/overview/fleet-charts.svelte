<script lang="ts">
	/**
	 * The fleet over the chosen span: CPU, memory and network, a line per node in each node's own
	 * color, one crosshair across all four, and every run started in the span marked down each.
	 */
	import * as stylex from '@stylexjs/stylex';
	import Card from '../card.svelte';
	import AreaChart from '../chart/area-chart.svelte';
	import type { Line } from '../chart/series.ts';
	import Sync from '../chart/sync.svelte';
	import { bytes } from '../format.ts';
	import { type } from '../style.ts';
	import type { Missing } from './fleet.ts';
	import MissingNote from './missing-note.svelte';

	let {
		fleet,
		since,
		until,
		span,
	}: {
		fleet: {
			cpu: Line[];
			memory: Line[];
			received: Line[];
			sent: Line[];
			missing: Missing[];
			marks: { at: number; label: string }[];
		};
		since: number;
		until: number;
		/** The span's name, which draws the plots in again when it changes. */
		span: string;
	} = $props();

	const WORDS: Record<string, string> = {
		'1h': 'the last hour, a point a minute',
		'6h': 'the last 6 hours, a point an hour',
		'24h': 'the last 24 hours, a point an hour',
		'7d': 'the last 7 days, a point an hour',
		'30d': 'the last 30 days, a point an hour',
	};
	const over = $derived(WORDS[span] ?? '');
	/** Every node failed, which is a failure to read rather than a quiet span. */
	const unread = $derived(
		fleet.cpu.length === 0 && fleet.missing.length ? 'No node answered.' : undefined,
	);
	const rate = (value: number) => `${bytes(value)}/s`;
	const charts = $derived([
		{ title: 'CPU', what: 'Share of all cores busy', lines: fleet.cpu, ceiling: 100 },
		{ title: 'Memory', what: 'In use', lines: fleet.memory, bytes: true, format: bytes },
		{ title: 'Received', what: 'Network in', lines: fleet.received, bytes: true, format: rate },
		{ title: 'Sent', what: 'Network out', lines: fleet.sent, bytes: true, format: rate },
	]);
</script>

<section class="flex flex-col gap-3">
	<div class="flex flex-wrap items-baseline justify-between gap-2">
		<h2 class={stylex.attrs(type.heading).class}>Fleet</h2>
		<p class={stylex.attrs(type.soft).class}>Every node, {over}; marks are runs started</p>
	</div>
	<MissingNote missing={fleet.missing} what="Series" />
	<Sync>
		<div class="grid gap-4 xl:grid-cols-2">
			{#each charts as chart (chart.title)}
				<Card title={chart.title} description={chart.what}>
					<AreaChart
						lines={chart.lines}
						{since}
						{until}
						ceiling={chart.ceiling}
						bytes={chart.bytes ?? false}
						band={false}
						format={chart.format ?? ((value) => `${Math.round(value)}%`)}
						events={fleet.marks}
						reveal={span}
						error={unread}
						label="{chart.title}, {chart.what.toLowerCase()}, per node"
					/>
				</Card>
			{/each}
		</div>
	</Sync>
</section>
