<script lang="ts">
	/** Where the console goes: its five sections, the one being read marked as the panel marks it. */
	import * as stylex from '@stylexjs/stylex';
	import Radio from '@lucide/svelte/icons/radio-tower';
	import { radius, text, weight } from '@canmi/kit/tokens/vocabulary.stylex';
	import { SECTIONS, type Section } from './sections.ts';
	import { surfaces, type } from './style.ts';

	let { current }: { current: Section | undefined } = $props();

	const styles = stylex.create({
		brandMark: {
			backgroundColor: 'var(--color-primary)',
			color: 'var(--nord6)',
			borderRadius: radius.lg,
		},
		brandName: {
			color: 'var(--color-text-strong)',
			fontSize: text.px14,
			fontWeight: weight.semibold,
			lineHeight: 1.2,
		},
		link: {
			borderRadius: radius.md,
			color: {
				default: 'var(--color-text-muted)',
				':hover': 'var(--color-text-strong)',
			},
			fontSize: text.px13,
			fontWeight: weight.medium,
			transitionProperty: 'color',
			transitionDuration: '120ms',
		},
		here: {
			backgroundColor: 'var(--color-selected)',
			color: 'var(--color-text-strong)',
		},
		edge: {
			backgroundColor: 'var(--color-accent)',
			borderRadius: radius.full,
		},
	});
</script>

<aside
	class="sticky top-0 flex h-screen w-56 shrink-0 flex-col {stylex.attrs(surfaces.sidebar).class}"
>
	<div class="flex items-center gap-3 px-4 pt-5 pb-6">
		<span
			class="flex size-8 shrink-0 items-center justify-center {stylex.attrs(styles.brandMark)
				.class}"
		>
			<Radio size={16} strokeWidth={2} />
		</span>
		<span class="flex min-w-0 flex-col gap-0.5">
			<span class={stylex.attrs(styles.brandName).class}>console</span>
			<span class="truncate {stylex.attrs(type.label).class}">every node</span>
		</span>
	</div>

	<nav class="flex flex-col gap-0.5 px-2">
		{#each SECTIONS as section (section.href)}
			{@const here = section === current}
			<a
				href={section.href}
				aria-current={here ? 'page' : undefined}
				class="relative flex h-9 items-center gap-2.5 px-3 {stylex.attrs(
					styles.link,
					here && styles.here,
				).class}"
			>
				{#if here}
					<span class="absolute top-2 bottom-2 left-0 w-0.5 {stylex.attrs(styles.edge).class}"
					></span>
				{/if}
				<section.icon size={16} strokeWidth={1.75} />
				{section.label}
			</a>
		{/each}
	</nav>
</aside>
