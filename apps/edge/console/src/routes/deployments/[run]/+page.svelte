<script lang="ts">
	import * as stylex from '@stylexjs/stylex';
	import Card from '#lib/card.svelte';
	import { duration } from '#lib/chart/numbers.js';
	import { moment } from '#lib/chart/series.js';
	import Timeline from '#lib/chart/timeline.svelte';
	import Events from '#lib/deployments/events.svelte';
	import { Fresh } from '#lib/deployments/fresh.svelte.js';
	import Matrix from '#lib/deployments/matrix.svelte';
	import { TONE, matrix, runState, said } from '#lib/deployments/state.js';
	import { stirring } from '#lib/deployments/stir.js';
	import { STAGE_KEYS, tracks } from '#lib/deployments/tracks.js';
	import { live } from '#lib/live.svelte.js';
	import type { Node } from '#lib/server/nodes.js';
	import { surfaces, tone, type } from '#lib/style.js';
	import Badge from '#lib/ui/badge.svelte';
	import PageHeader from '#lib/ui/page-header.svelte';
	import { timeZone } from '#lib/ui/time-zone.js';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	const zone = timeZone();
	const held = live();
	const fresh = new Fresh(
		() => data.now,
		() =>
			(data.found?.running ?? 0) > 0 ||
			stirring(held.view.nodes, data.found ? data.run : data.run - 1, data.run),
	);

	const run = $derived(data.found);
	const unknown = $derived(new Set(Object.keys(data.failures) as Node[]));
	const missing = $derived(Object.keys(data.failures));
	const state = $derived(run && runState(run));
	const took = $derived(
		run && (run.duration ?? Math.max(0, fresh.now - Date.parse(run.first_start))),
	);
	const summary = $derived(
		run
			? [
					run.commit ? `Commit ${run.commit.slice(0, 7)}` : 'No commit recorded',
					`started ${moment(Date.parse(run.first_start) / 1000, zone)}`,
					`${duration((took ?? 0) / 1000)}${run.running ? ' so far' : ''}`,
				].join(' · ')
			: undefined,
	);
	/** Stage times are not recorded; see src/lib/deployments/tracks.ts. */
	const SPANS =
		'host records when a deploy started and ended and the last stage it reached, not when each ' +
		'stage began: each bar is one whole deploy, in the color of the stage it reached. A skip ' +
		'takes no time and is in the matrix only.';
	const failures = $derived(run?.placements.filter((one) => one.outcome === 'failed') ?? []);
</script>

<PageHeader
	title="Run #{data.run}"
	description={summary}
	back={{ href: '/deployments', label: 'Deployments' }}
>
	{#snippet meta()}
		{#if state}<Badge tone={TONE[state]}>{said(state)}</Badge>{/if}
	{/snippet}
</PageHeader>

{#if missing.length}
	<p class="p-4 {stylex.attrs(surfaces.empty, type.body).class}" role="status">
		{missing.join(', ')} did not answer, so {missing.length === 1 ? 'its' : 'their'} part of this run
		is unknown.
	</p>
{/if}

{#if !run}
	<p class="p-4 {stylex.attrs(surfaces.empty, type.soft).class}">
		No node that answered holds an event from run #{data.run}. Each node answers with its last 500
		events, so an older run is no longer seen.
	</p>
{:else}
	<Card
		title="Where each app got to"
		description="Each app on each node: hover a cell for its reason, click it for the node."
		flush
	>
		<Matrix rows={matrix(run, data.nodes, unknown)} nodes={data.nodes} />
	</Card>

	<Card title="Timeline" description={SPANS}>
		<Timeline
			tracks={tracks(run, data.nodes)}
			stages={STAGE_KEYS}
			until={run.running ? fresh.now / 1000 : undefined}
			label="Each deploy of run #{data.run} over time"
		/>
	</Card>

	{#if failures.length}
		<Card title="Failures" description="Where each failed deploy stopped, and why." flush>
			<ul>
				{#each failures as one (`${one.node}/${one.app}`)}
					<li class="flex flex-col gap-1 px-5 py-3 {stylex.attrs(surfaces.listRule).class}">
						<span class="flex flex-wrap items-center gap-2 {stylex.attrs(type.name).class}">
							<span class={stylex.attrs(type.mono).class}>{one.app}</span> on
							<a href="/nodes/{one.node}" class={stylex.attrs(type.mono).class}>{one.node}</a>
							<span class={stylex.attrs(tone.bad).class}>{said('failed', one.stage)}</span>
						</span>
						<span class="whitespace-pre-wrap {stylex.attrs(type.soft).class}"
							>{one.detail ?? 'host recorded no reason.'}</span
						>
					</li>
				{/each}
			</ul>
		</Card>
	{/if}

	<Card title="Events" description="Every event of this run, as each node kept it." flush>
		<Events
			events={data.events}
			label="Every event of run #{data.run}, newest first"
			empty="No events."
		/>
	</Card>
{/if}
