<script lang="ts">
	/** What CI built and where each node is with it; then what no run started. */
	import * as stylex from '@stylexjs/stylex';
	import Badge from './badge.svelte';
	import { ago, localTime } from './format.ts';
	import type { Cell, Pipeline, Run } from './pipeline.ts';
	import { surfaces, type, type Tone } from './style.ts';
	import type { Event } from './wire.ts';

	let { pipeline, nodes, now }: { pipeline: Pipeline; nodes: string[]; now: number } = $props();

	/** The few of what no run started that are worth a glance. */
	const APART = 20;

	function capitalized(word: string): string {
		return word.charAt(0).toUpperCase() + word.slice(1);
	}

	/** An event's word: its stage while it runs, its outcome once it has ended. */
	function said(event: Event): { tone: Tone; word: string } {
		switch (event.outcome) {
			case 'running':
				return { tone: 'busy', word: capitalized(event.stage ?? 'running') };
			case 'succeeded':
				return { tone: 'good', word: 'Succeeded' };
			case 'failed':
				return { tone: 'bad', word: event.stage ? `Failed ${event.stage}` : 'Failed' };
			case 'skipped':
				return { tone: 'quiet', word: 'Skipped' };
			default:
				return { tone: 'quiet', word: capitalized(event.outcome) };
		}
	}

	const RUN_TONE: Record<Run['state'], Tone> = { running: 'busy', failed: 'bad', done: 'good' };
	const RUN_WORD: Record<Run['state'], string> = {
		running: 'Deploying',
		failed: 'Failed',
		done: 'Done',
	};

	function explained(run: Run): Cell[] {
		return run.rows.flatMap((row) =>
			Object.values(row.cells).filter((cell) => cell.event.detail !== undefined),
		);
	}
</script>

<div class="flex flex-col gap-4">
	<!-- No data reaches here yet: `hook` drops every run event but a completed one. See
	     spec/architecture/console.md, "The pipeline". -->
	<div class="flex flex-col gap-1 p-4 {stylex.attrs(surfaces.empty).class}">
		<h3 class={stylex.attrs(type.name).class}>Building on GitHub</h3>
		<p class={stylex.attrs(type.soft).class}>
			Runs still on CI are not reported to the console yet.
		</p>
	</div>

	{#if pipeline.runs.length === 0}
		<p class={stylex.attrs(type.soft).class}>No node holds an event from a CI run.</p>
	{/if}

	{#each pipeline.runs as run (run.run)}
		{@const details = explained(run)}
		<article class="flex min-w-0 flex-col {stylex.attrs(surfaces.card).class}">
			<header class="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 pt-3 pb-2">
				<h3 class={stylex.attrs(type.name).class}>Run {run.run}</h3>
				{#if run.commit}
					<span class={stylex.attrs(type.mono, type.soft).class}>{run.commit.slice(0, 7)}</span>
				{/if}
				<Badge tone={RUN_TONE[run.state]}>{RUN_WORD[run.state]}</Badge>
				<span class="ml-auto {stylex.attrs(type.soft).class}" title={localTime(run.started_at)}>
					{ago(run.started_at, now)}
				</span>
			</header>
			<div class="overflow-x-auto">
				<table class="w-full border-collapse text-left">
					<thead>
						<tr>
							<th class="px-4 py-1.5 font-normal {stylex.attrs(type.label).class}">App</th>
							{#each nodes as node (node)}
								<th class="px-2 py-1.5 font-normal {stylex.attrs(type.label).class}">{node}</th>
							{/each}
						</tr>
					</thead>
					<tbody>
						{#each run.rows as row (row.app)}
							<tr class={stylex.attrs(surfaces.rowRule).class}>
								<td class="px-4 py-2 {stylex.attrs(type.mono, type.body).class}">{row.app}</td>
								{#each nodes as node (node)}
									{@const cell = row.cells[node]}
									<td class="px-2 py-2">
										{#if cell}
											{@const shown = said(cell.event)}
											<Badge
												tone={shown.tone}
												title={cell.event.detail ?? `Started ${localTime(cell.event.started_at)}`}
											>
												{shown.word}
											</Badge>
										{:else}
											<span
												class={stylex.attrs(type.soft).class}
												title="This node holds no event for it">–</span
											>
										{/if}
									</td>
								{/each}
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
			{#if details.length}
				<details class="px-4 pt-1 pb-3">
					<summary class="cursor-pointer {stylex.attrs(type.soft).class}">
						Why ({details.length})
					</summary>
					<ul class="mt-2 flex flex-col gap-1.5 p-3 {stylex.attrs(surfaces.well).class}">
						{#each details as cell (`${cell.node}/${cell.event.id}`)}
							<li class={stylex.attrs(type.body).class}>
								<span class={stylex.attrs(type.mono).class}>{cell.node} · {cell.event.app}</span>:
								{cell.event.detail}
							</li>
						{/each}
					</ul>
				</details>
			{/if}
		</article>
	{/each}

	<section class="flex flex-col gap-2">
		<h3 class={stylex.attrs(type.name).class}>Uploads and panel actions</h3>
		{#if pipeline.apart.length === 0}
			<p class={stylex.attrs(type.soft).class}>None held.</p>
		{:else}
			<ul class="flex flex-col {stylex.attrs(surfaces.card).class}">
				{#each pipeline.apart.slice(0, APART) as { node, event } (`${node}/${event.id}`)}
					{@const shown = said(event)}
					<li
						class="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-2 {stylex.attrs(
							surfaces.listRule,
						).class}"
					>
						<span class={stylex.attrs(type.mono, type.body).class}>{node} · {event.app}</span>
						<span class={stylex.attrs(type.soft).class}>
							{event.action}, by {event.source.kind}
						</span>
						<Badge tone={shown.tone} title={event.detail}>{shown.word}</Badge>
						<span
							class="ml-auto {stylex.attrs(type.soft).class}"
							title={localTime(event.started_at)}
						>
							{ago(event.started_at, now)}
						</span>
					</li>
				{/each}
			</ul>
		{/if}
	</section>
</div>
