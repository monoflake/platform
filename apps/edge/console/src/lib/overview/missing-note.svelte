<script lang="ts">
	/** The nodes a read did not reach, named in one line where their gap would otherwise puzzle. */
	import * as stylex from '@stylexjs/stylex';
	import TriangleAlert from '@lucide/svelte/icons/triangle-alert';
	import { tone, type } from '../style.ts';
	import type { Missing } from './fleet.ts';

	/** `what` opens the sentence: `Series`, `Runs`. */
	let { missing, what }: { missing: Missing[]; what: string } = $props();
</script>

{#if missing.length}
	<p class="flex items-center gap-1.5 {stylex.attrs(type.soft).class}">
		<span class="inline-flex shrink-0 {stylex.attrs(tone.warn).class}"
			><TriangleAlert size={13} strokeWidth={2} /></span
		>
		<span>
			{what} from
			{#each missing as one, index (one.node)}{index ? ', ' : ''}<span
					class={stylex.attrs(type.mono).class}
					title={one.message}>{one.node}</span
				>{/each} could not be read.
		</span>
	</p>
{/if}
