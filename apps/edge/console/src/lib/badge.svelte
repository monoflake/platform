<script lang="ts">
	/** A state, as a dot and a word in its tone. */
	import * as stylex from '@stylexjs/stylex';
	import type { Snippet } from 'svelte';
	import { surfaces, tone as tones, wash, type, type Tone } from './style.ts';

	let { tone, title, children }: { tone: Tone; title?: string; children: Snippet } = $props();
</script>

<span
	{title}
	class="inline-flex h-5 items-center gap-1.5 px-2 whitespace-nowrap {stylex.attrs(
		surfaces.pill,
		type.soft,
		tones[tone],
		wash[tone],
	).class}"
>
	<span class="size-1.5 shrink-0 {stylex.attrs(surfaces.dot).class}"></span>
	{@render children()}
</span>
