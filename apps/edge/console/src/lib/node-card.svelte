<script lang="ts">
	/** One node: whether it is heard, its machine, how many of its apps run, and what is stale. */
	import * as stylex from '@stylexjs/stylex';
	import Badge from './badge.svelte';
	import { ago, bytes, localTime } from './format.ts';
	import { liveness, readings, running } from './node.ts';
	import { surfaces, type } from './style.ts';
	import type { Held } from './wire.ts';

	let { name, held, now }: { name: string; held: Held; now: number } = $props();

	const heard = $derived(liveness(held.heard_at, now));
	const machine = $derived(readings(held.snapshot.machine));
	const apps = $derived(running(held));
	const stale = $derived(held.snapshot.stale ?? []);

	function share(used: number, total: number | undefined): string {
		return total ? `${Math.round((used / total) * 100)}%` : bytes(used);
	}

	function of(reading: { used: number; total?: number } | undefined): string | undefined {
		return reading?.total ? `${bytes(reading.used)} of ${bytes(reading.total)}` : undefined;
	}
</script>

<article class="flex flex-col gap-3 p-4 {stylex.attrs(surfaces.card).class}">
	<header class="flex items-center justify-between gap-2">
		<h3 class={stylex.attrs(type.name, type.mono).class}>{name}</h3>
		<Badge
			tone={heard === 'live' ? 'good' : heard === 'late' ? 'warn' : 'bad'}
			title="Heard {localTime(held.heard_at)}"
		>
			{heard === 'live' ? 'Live' : heard === 'late' ? 'Late' : 'Gone'}
		</Badge>
	</header>

	{#if machine}
		<dl class="grid grid-cols-3 gap-2">
			<div class="flex flex-col gap-0.5">
				<dt class={stylex.attrs(type.label).class}>CPU</dt>
				<dd class={stylex.attrs(type.figure).class}>
					{machine.cpu === undefined ? '–' : `${Math.round(machine.cpu)}%`}
				</dd>
			</div>
			<div class="flex flex-col gap-0.5">
				<dt class={stylex.attrs(type.label).class}>Memory</dt>
				<dd class={stylex.attrs(type.figure).class} title={of(machine.memory)}>
					{machine.memory ? share(machine.memory.used, machine.memory.total) : '–'}
				</dd>
			</div>
			<div class="flex flex-col gap-0.5">
				<dt class={stylex.attrs(type.label).class}>Disk</dt>
				<dd class={stylex.attrs(type.figure).class} title={of(machine.disk)}>
					{machine.disk ? share(machine.disk.used, machine.disk.total) : '–'}
				</dd>
			</div>
		</dl>
	{:else}
		<p class={stylex.attrs(type.soft).class}>No machine readings: no meter answers here.</p>
	{/if}

	<footer class="flex flex-wrap items-center justify-between gap-2">
		<span class={stylex.attrs(type.soft).class}>
			{apps.running} of {apps.total} apps running
		</span>
		<span class={stylex.attrs(type.soft).class} title={localTime(held.heard_at)}>
			{ago(held.heard_at, now)}
		</span>
	</footer>

	{#if stale.length}
		<Badge tone="warn" title="The node's last read of these failed; shown as read before.">
			Stale: {stale.join(', ')}
		</Badge>
	{/if}
</article>
