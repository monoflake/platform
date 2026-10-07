<script lang="ts">
	/**
	 * The account, then where the console goes: its five sections, the one being read held in a
	 * raised row. Fixed down the whole left edge; see spec/architecture/console.md.
	 */
	import * as stylex from '@stylexjs/stylex';
	import { radius, text, weight } from '@canmi/kit/tokens/vocabulary.stylex';
	import { SECTIONS, type Section } from './sections.ts';
	import { surfaces } from './style.ts';

	let { current }: { current: Section | undefined } = $props();

	const styles = stylex.create({
		link: {
			borderRadius: radius.md,
			backgroundColor: {
				default: 'transparent',
				':hover': 'color-mix(in srgb, var(--color-raised) 55%, transparent)',
			},
			color: {
				default: 'var(--color-text-muted)',
				':hover': 'var(--color-text-strong)',
			},
			fontSize: text.px14,
			fontWeight: weight.medium,
			transitionProperty: 'color, background-color',
			transitionDuration: '120ms',
		},
		here: {
			backgroundColor: { default: 'var(--color-raised)', ':hover': 'var(--color-raised)' },
			color: { default: 'var(--color-text-strong)', ':hover': 'var(--color-text-strong)' },
		},
		account: {
			color: 'var(--color-text-strong)',
			fontSize: text.px14,
			fontWeight: weight.semibold,
		},
	});
</script>

<aside
	class="fixed inset-y-0 left-0 z-30 flex w-60 flex-col {stylex.attrs(surfaces.sidebar).class}"
>
	<a href="/" class="flex h-14 shrink-0 items-center px-6 {stylex.attrs(styles.account).class}"
		>canmi</a
	>
	<nav class="flex flex-col gap-0.5 overflow-y-auto px-3 pb-3">
		{#each SECTIONS as section (section.href)}
			{@const here = section === current}
			<a
				href={section.href}
				aria-current={here ? 'page' : undefined}
				class="flex h-9 items-center gap-2.5 px-3 {stylex.attrs(styles.link, here && styles.here)
					.class}"
			>
				<section.icon size={16} strokeWidth={1.75} />
				{section.label}
			</a>
		{/each}
	</nav>
</aside>
