<script lang="ts">
	/**
	 * A node's machine: how full it is now, as meters against its totals, and how it got there, as
	 * charts over the chosen span that share one crosshair, its deploys marked down each of them.
	 */
	import * as stylex from '@stylexjs/stylex';
	import Card from '../card.svelte';
	import AreaChart from '../chart/area-chart.svelte';
	import Heatmap from '../chart/heatmap.svelte';
	import Meter from '../chart/meter.svelte';
	import { percent } from '../chart/numbers.ts';
	import Sync from '../chart/sync.svelte';
	import { bytes } from '../format.ts';
	import type { Now } from '../host.ts';
	import type { Read } from '../server/read.ts';
	import type { Span } from '../server/reads.ts';
	import { type } from '../style.ts';
	import Unread from '../unread.svelte';
	import type { NodeCharts } from './charts.ts';

	let {
		machine,
		charts,
		marks,
		span,
		reveal,
	}: {
		/** The latest reading, live where the relay carries it. */
		machine?: Now;
		charts: Read<NodeCharts>;
		marks: { at: number; label: string }[];
		span: Span;
		/** The range chosen, so the charts draw in again when it changes. */
		reveal: string;
	} = $props();

	const values = $derived(machine?.sample.values ?? {});
	const info = $derived(machine?.info);
	const grain = $derived(span.grain === 'minute' ? 'a point a minute' : 'a point an hour');
	const rate = (value: number) => `${bytes(value)}/s`;
	const share = (value: number) => percent(value / 100);
	const common = $derived({ since: span.since, until: span.until, events: marks, reveal });
</script>

{#if info}
	<Card title="Now">
		<div class="grid gap-x-8 gap-y-5 sm:grid-cols-2 xl:grid-cols-4">
			<Meter
				label="CPU, in cores busy"
				value={((values['cpu.usage'] ?? 0) / 100) * info.cores}
				limit={info.cores}
				format={(value) => value.toFixed(1).replace(/\.0$/, '')}
			/>
			<Meter label="Memory" value={values['memory.used'] ?? 0} limit={info.memory} format={bytes} />
			{#if info.swap}
				<Meter label="Swap" value={values['swap.used'] ?? 0} limit={info.swap} format={bytes} />
			{:else}
				<p class="flex flex-col gap-1.5 {stylex.attrs(type.soft).class}">
					Swap<span>None configured</span>
				</p>
			{/if}
			{#if info.storage}
				<Meter
					label="Storage"
					value={values['storage.used'] ?? 0}
					limit={info.storage}
					format={bytes}
				/>
			{/if}
		</div>
	</Card>
{/if}

{#if !charts.ok}
	<Unread what="The machine's series" failure={charts.failure} />
{:else}
	{@const drawn = charts.data}
	<Sync>
		<div class="grid gap-4 xl:grid-cols-2">
			<Card title="CPU">
				<AreaChart lines={drawn.cpu} ceiling={100} format={share} {...common} />
			</Card>
			{#if drawn.cores.rows.length}
				<Card title="CPU per core">
					<Heatmap
						rows={drawn.cores.rows}
						times={drawn.cores.times}
						values={drawn.cores.values}
						low={0}
						high={100}
						format={share}
						label="CPU per core"
					/>
				</Card>
			{/if}
			<Card title="Memory">
				<AreaChart
					lines={drawn.memory}
					bytes
					format={bytes}
					thresholds={info ? [{ value: info.memory, label: 'Total' }] : []}
					{...common}
				/>
			</Card>
			<Card title="Load">
				<AreaChart
					lines={drawn.load}
					format={(value) => value.toFixed(2)}
					thresholds={info ? [{ value: info.cores, label: 'Cores', tone: 'warn' }] : []}
					{...common}
				/>
			</Card>
			<Card title="Network">
				<AreaChart lines={drawn.network} bytes format={rate} {...common} />
			</Card>
			<Card title="Disk">
				<AreaChart lines={drawn.disk} bytes format={rate} {...common} />
			</Card>
			{#if drawn.temperature.length}
				<Card title="Temperature">
					<AreaChart
						lines={drawn.temperature}
						format={(value) => `${value.toFixed(1)} °C`}
						{...common}
					/>
				</Card>
			{/if}
		</div>
	</Sync>
{/if}
