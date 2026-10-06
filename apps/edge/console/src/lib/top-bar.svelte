<script lang="ts">
	/**
	 * The page's title, or on a detail page the section it sits under and the thing it is about;
	 * and on the right the time range, when the page loaded one. The range is a link per span, so
	 * choosing one reloads the page's data before it has even hydrated.
	 */
	import * as stylex from '@stylexjs/stylex';
	import ChevronRight from '@lucide/svelte/icons/chevron-right';
	import { duration } from '@canmi/kit/tokens/vocabulary.stylex';
	import type { Section } from './sections.ts';
	import { surfaces, type } from './style.ts';
	import Segmented, { RANGES, type Range } from './ui/segmented.svelte';

	let {
		title,
		section,
		detail,
		range,
		query,
	}: {
		title: string;
		section?: Section;
		detail?: string;
		/** The span the page is drawn over, when it is drawn over one. */
		range?: Range;
		/** The page's query, kept as each range's link changes only `range`. */
		query: string;
	} = $props();

	const options = $derived(
		RANGES.map((one) => {
			const asked = new URLSearchParams(query);
			asked.set('range', one.key);
			return { key: one.key, label: one.label, href: `?${asked}` };
		}),
	);

	const styles = stylex.create({
		crumb: {
			color: { default: 'var(--color-text-muted)', ':hover': 'var(--color-text-strong)' },
			transitionProperty: 'color',
			transitionDuration: duration.base,
		},
	});
</script>

<header
	class="sticky top-0 z-20 flex h-14 items-center justify-between gap-4 px-8 backdrop-blur {stylex.attrs(
		surfaces.bar,
	).class}"
>
	{#if detail && section}
		<nav aria-label="Breadcrumb" class="flex min-w-0 items-center gap-1.5">
			<a href={section.href} class={stylex.attrs(type.title, styles.crumb).class}>{section.label}</a
			>
			<span class="inline-flex {stylex.attrs(type.soft).class}" aria-hidden="true"
				><ChevronRight size={16} strokeWidth={2} /></span
			>
			<h1 class="truncate {stylex.attrs(type.mono, type.title).class}" aria-current="page">
				{detail}
			</h1>
		</nav>
	{:else}
		<h1 class="truncate {stylex.attrs(type.title).class}">{title}</h1>
	{/if}
	{#if range}
		<Segmented {options} value={range} label="Time range" />
	{/if}
</header>
