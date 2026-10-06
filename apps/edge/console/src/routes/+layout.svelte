<script lang="ts">
	import { onMount, untrack, type Snippet } from 'svelte';
	import { dev } from '$app/env';
	import { page } from '$app/state';
	import { Live, provideLive } from '#lib/live.svelte.js';
	import { sectionOf } from '#lib/sections.js';
	import Sidebar from '#lib/sidebar.svelte';
	import TopBar from '#lib/top-bar.svelte';
	import { RANGES } from '#lib/ui/segmented.svelte';
	import { setTimeZone } from '#lib/ui/time-zone.js';
	import '../app.css';
	import type { LayoutData } from './$types';

	let { children, data }: { children: Snippet; data: LayoutData } = $props();

	// Once, from the server's load: every chart and time below writes the reader's zone.
	setTimeZone(untrack(() => data.zone));

	/**
	 * The visual layer in development, linked as the panel links it: the layer order first, then the
	 * sheet. See web's spec/architecture/css/layers.md, "In development the visual layer arrives with
	 * its runtime, and must not be linked".
	 */
	const DEV_STYLEX =
		'<style>@layer properties, theme, base, components, utilities;</style>' +
		'<link rel="stylesheet" href="/virtual:stylex.css">';

	if (dev) {
		$effect(() => {
			void import('virtual:stylex:runtime');
		});
	}

	const live = provideLive(new Live());

	/** Every page loads the cluster on the server, and what it read is taken in. */
	function seed() {
		const read = page.data.cluster;
		if (read?.ok) untrack(() => live.seed(read.data));
	}
	// Once now, so the server's render already shows it, and again on each load after.
	seed();
	$effect.pre(seed);

	// On mount, not in an effect: an effect reruns on what it reads, reopening the socket.
	onMount(() => live.start());

	const section = $derived(sectionOf(page.url.pathname));
	const detail = $derived(page.params.node ?? page.params.run ?? page.params.app);
	/** A page drawn over a span says so by loading `range`; the top bar then offers the others. */
	const range = $derived(RANGES.find((one) => one.key === page.data.range)?.key);
	const title = $derived(
		typeof page.data.title === 'string' ? page.data.title : (section?.label ?? 'Console'),
	);
</script>

<svelte:head>
	<!-- First in the head on purpose: it declares the order the layers below it take. -->
	{#if dev}{@html DEV_STYLEX}{/if}
	<title>{section ? `${section.label} · Console` : 'Console'}</title>
</svelte:head>

<div class="flex min-h-screen">
	<Sidebar current={section} {live} />
	<main class="min-w-0 flex-1">
		<TopBar {title} {section} {detail} {range} query={page.url.search} />
		<div class="mx-auto flex w-full max-w-[90rem] flex-col gap-6 px-8 py-7">
			{@render children()}
		</div>
	</main>
</div>
