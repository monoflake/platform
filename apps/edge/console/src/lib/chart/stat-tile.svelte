<script lang="ts">
	/**
	 * One figure as the headline: its name, the value large, how it moved against a named period,
	 * and a sparkline of how it got here. The number is the chart; there is no plot to hover.
	 */
	import * as stylex from '@stylexjs/stylex';
	import ArrowDown from '@lucide/svelte/icons/arrow-down';
	import ArrowUp from '@lucide/svelte/icons/arrow-up';
	import Minus from '@lucide/svelte/icons/minus';
	import { line, weight } from '@canmi/kit/tokens/vocabulary.stylex';
	import { surfaces, tone, type } from '../style.ts';
	import { compact, signed } from './numbers.ts';
	import Sparkline from './sparkline.svelte';

	let {
		label,
		value,
		unit,
		delta,
		trend = [],
	}: {
		label: string;
		/** A number is written compact, `12.9K`; a string as it is. */
		value: number | string;
		unit?: string;
		/** The change against `period`, and which way is good, which decides its tone. */
		delta?: {
			value: number;
			period: string;
			good: 'up' | 'down';
			format?: (value: number) => string;
		};
		/** About a dozen recent values, the last of them `value`. */
		trend?: number[];
	} = $props();

	const shown = $derived(typeof value === 'number' ? compact(value) : value);
	const direction = $derived(
		delta === undefined || delta.value === 0 ? 'flat' : delta.value > 0 ? 'up' : 'down',
	);
	const verdict = $derived(
		direction === 'flat' ? 'quiet' : direction === delta?.good ? 'good' : 'bad',
	);

	const styles = stylex.create({
		figure: {
			fontSize: '3rem', // unnamed: the hero step, which the ladder stops below
			fontWeight: weight.semibold,
			lineHeight: line.none,
			color: 'var(--color-text-strong)',
		},
	});
</script>

<div class="flex min-w-0 flex-col gap-3 px-5 pt-4 pb-4 {stylex.attrs(surfaces.card).class}">
	<span class={stylex.attrs(type.label).class}>{label}</span>
	<div class="flex items-baseline gap-1.5">
		<span class={stylex.attrs(styles.figure).class}>{shown}</span>
		{#if unit}<span class={stylex.attrs(type.soft).class}>{unit}</span>{/if}
	</div>
	{#if delta}
		<span class="inline-flex items-center gap-1 {stylex.attrs(type.soft).class}">
			<span class="inline-flex items-center gap-0.5 {stylex.attrs(tone[verdict]).class}">
				{#if direction === 'up'}<ArrowUp
						size={12}
						strokeWidth={2.25}
					/>{:else if direction === 'down'}<ArrowDown size={12} strokeWidth={2.25} />{:else}<Minus
						size={12}
						strokeWidth={2.25}
					/>{/if}
				{signed(delta.value, delta.format)}
			</span>
			vs {delta.period}
		</span>
	{/if}
	{#if trend.length > 1}<Sparkline values={trend} label="{label}, recent trend" />{/if}
</div>
