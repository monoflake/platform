<script lang="ts">
	import { applyTheme, currentTheme, themeCookie } from '@canmi/kit/theme';
	import Moon from '@lucide/svelte/icons/moon';
	import Sun from '@lucide/svelte/icons/sun';
	import * as stylex from '@stylexjs/stylex';
	import type { Snippet } from 'svelte';
	import { dev } from '$app/env';
	import { type } from '#lib/style.js';
	import '../app.css';

	let { children }: { children: Snippet } = $props();

	function toggleTheme() {
		const next = currentTheme() === 'dark' ? 'light' : 'dark';
		applyTheme(next);
		document.cookie = themeCookie(next);
	}

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
</script>

<svelte:head>
	<!-- First in the head on purpose: it declares the order the layers below it take. -->
	{#if dev}{@html DEV_STYLEX}{/if}
	<title>Console</title>
</svelte:head>

<div class="mx-auto flex w-[min(100%,80rem)] flex-col gap-8 px-4 py-6 md:px-6">
	<nav class="flex items-center justify-between gap-4">
		<span class={stylex.attrs(type.title).class}>Console</span>
		<button
			type="button"
			onclick={toggleTheme}
			aria-label="Switch between light and dark"
			class="focus-ring inline-flex size-8 items-center justify-center rounded-full"
		>
			<Moon size={16} aria-hidden="true" class="dark:hidden" />
			<Sun size={16} aria-hidden="true" class="hidden dark:block" />
		</button>
	</nav>
	{@render children()}
</div>
