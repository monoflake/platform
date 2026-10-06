<script lang="ts" generics="Row">
	/**
	 * Rows under typed columns: sorted by a header, filtered by the row beneath it, paged, each row
	 * a link where it has one. The server renders the first page whole, unsorted unless `sort` says
	 * otherwise; everything after is the browser's, over rows it already holds. Under `height` the
	 * table scrolls inside itself and its header sticks; without it the table runs its full length
	 * and scrolls across only, which is what a sticky header cannot stick inside.
	 */
	import * as stylex from '@stylexjs/stylex';
	import ChevronDown from '@lucide/svelte/icons/chevron-down';
	import ChevronLeft from '@lucide/svelte/icons/chevron-left';
	import ChevronRight from '@lucide/svelte/icons/chevron-right';
	import ChevronUp from '@lucide/svelte/icons/chevron-up';
	import ChevronsUpDown from '@lucide/svelte/icons/chevrons-up-down';
	import { border, radius, text } from '@canmi/kit/tokens/vocabulary.stylex';
	import { untrack } from 'svelte';
	import { surfaces, type } from '../style.ts';
	import { filterRows, pageOf, sortRows, written, type Column, type Sort } from './table.ts';

	let {
		rows,
		columns,
		key,
		href,
		label,
		sort: initial,
		sizes = [10, 25, 50, 100],
		size: chosen = 25,
		filterable = true,
		height,
		empty = 'Nothing here yet',
		stale = false,
	}: {
		rows: Row[];
		columns: Column<Row>[];
		key: (row: Row) => string;
		/** Where a row leads; the first cell carries the link and the whole row answers it. */
		href?: (row: Row) => string | undefined;
		/** What the table holds, for a reader who does not see it. */
		label: string;
		sort?: Sort;
		sizes?: number[];
		size?: number;
		filterable?: boolean;
		/** The most it grows to in pixels before scrolling inside itself. */
		height?: number;
		empty?: string;
		stale?: boolean;
	} = $props();

	let sort: Sort | undefined = $state(untrack(() => initial));
	let size = $state(untrack(() => chosen));
	let page = $state(1);
	let queries: Record<string, string> = $state({});

	const filtered = $derived(filterRows(rows, columns, queries));
	const shown = $derived(pageOf(sortRows(filtered, columns, sort), page, size));
	const asked = $derived(Object.values(queries).some((query) => query.trim()));

	function order(column: Column<Row>) {
		sort =
			sort?.key !== column.key
				? { key: column.key, direction: column.kind === 'number' ? 'descending' : 'ascending' }
				: {
						key: column.key,
						direction: sort.direction === 'ascending' ? 'descending' : 'ascending',
					};
	}

	function ask(column: Column<Row>, query: string) {
		queries = { ...queries, [column.key]: query };
		page = 1;
	}

	function clear() {
		queries = {};
		page = 1;
	}

	function resize(rows: number) {
		size = rows;
		page = 1;
	}

	const styles = stylex.create({
		frame: { backgroundColor: 'var(--color-surface)' },
		head: {
			backgroundColor: 'var(--color-surface)',
			boxShadow: '0 1px 0 var(--color-line)',
		},
		heading: {
			backgroundColor: 'transparent',
			borderWidth: 0,
			padding: 0,
			color: { default: 'inherit', ':hover': 'var(--color-text-strong)' },
			font: 'inherit',
			letterSpacing: 'inherit',
			textTransform: 'inherit',
		},
		input: {
			backgroundColor: 'var(--color-sunken)',
			borderWidth: border.hairlinePx,
			borderStyle: 'solid',
			borderColor: { default: 'var(--color-line)', ':focus': 'var(--color-line-strong)' },
			borderRadius: radius.md,
			color: 'var(--color-text)',
			fontSize: text.px12,
			fontWeight: 'normal',
			letterSpacing: 'normal',
			textTransform: 'none',
		},
		row: {
			backgroundColor: { default: 'transparent', ':hover': 'var(--color-raised)' },
		},
		link: { color: 'var(--color-text-strong)' },
		control: {
			backgroundColor: 'transparent',
			borderWidth: 0,
			color: {
				default: 'var(--color-text-muted)',
				':hover': 'var(--color-text-strong)',
				':disabled': 'var(--color-text-faint)',
			},
		},
		stale: { opacity: 0.5 },
	});
</script>

<div class="flex min-w-0 flex-col">
	<div
		class="min-w-0 overflow-x-auto {height ? 'overflow-y-auto' : ''} {stylex.attrs(styles.frame)
			.class}"
		style:max-height={height ? `${height}px` : undefined}
	>
		<table aria-busy={stale} class={stylex.attrs(stale && styles.stale).class}>
			<caption class="sr-only">{label}</caption>
			<thead class="sticky top-0 z-10 {stylex.attrs(styles.head).class}">
				<tr>
					{#each columns as column (column.key)}
						{@const sorted = sort?.key === column.key ? sort.direction : undefined}
						<th
							scope="col"
							aria-sort={sorted ?? 'none'}
							class="border-b-0 {column.kind === 'number' ? 'text-right' : ''}"
						>
							{#if column.sortable ?? true}
								<button
									type="button"
									class="inline-flex items-center gap-1 {stylex.attrs(styles.heading).class}"
									onclick={() => order(column)}
								>
									{column.label}
									{#if sorted === 'ascending'}<ChevronUp
											size={12}
											strokeWidth={2.25}
										/>{:else if sorted === 'descending'}<ChevronDown
											size={12}
											strokeWidth={2.25}
										/>{:else}<ChevronsUpDown size={12} strokeWidth={2} />{/if}
								</button>
							{:else}
								{column.label}
							{/if}
						</th>
					{/each}
				</tr>
				{#if filterable}
					<tr>
						{#each columns as column (column.key)}
							<th class="border-b-0 pt-0">
								{#if column.filterable ?? true}
									<input
										type="search"
										aria-label="Filter by {column.label}"
										placeholder={column.kind === 'number' ? '>10' : 'Filter'}
										class="h-7 w-full min-w-16 px-2 {stylex.attrs(styles.input).class}"
										value={queries[column.key] ?? ''}
										oninput={(event) => ask(column, event.currentTarget.value)}
									/>
								{/if}
							</th>
						{/each}
					</tr>
				{/if}
			</thead>
			<tbody>
				{#each shown.rows as row (key(row))}
					{@const link = href?.(row)}
					<tr class="{link ? 'relative' : ''} {stylex.attrs(styles.row).class}">
						{#each columns as column, index (column.key)}
							<td
								class="{column.kind === 'number' ? 'text-right' : ''} {stylex.attrs(type.body)
									.class}"
							>
								{#snippet content()}
									{#if column.cell}{@render column.cell(row)}{:else}{written(column, row)}{/if}
								{/snippet}
								{#if index === 0 && link}
									<a
										href={link}
										class="after:absolute after:inset-0 {stylex.attrs(styles.link).class}"
										>{@render content()}</a
									>
								{:else}
									{@render content()}
								{/if}
							</td>
						{/each}
					</tr>
				{:else}
					<tr>
						<td colspan={columns.length} class="py-10 text-center {stylex.attrs(type.soft).class}">
							{#if rows.length && asked}
								No rows match the filter.
								<button
									type="button"
									class="underline {stylex.attrs(styles.control).class}"
									onclick={clear}>Clear it</button
								>
							{:else}
								{empty}
							{/if}
						</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
	<footer
		class="flex flex-wrap items-center justify-between gap-3 px-5 py-2.5 {stylex.attrs(
			surfaces.rowRule,
			type.soft,
		).class}"
	>
		<span>
			{#if shown.from}{shown.from}&ndash;{shown.to} of {filtered.length}{:else}0 rows{/if}
		</span>
		<div class="flex items-center gap-3">
			<label class="inline-flex items-center gap-2">
				Rows
				<select
					class="h-7 px-1.5 {stylex.attrs(styles.input).class}"
					value={size}
					onchange={(event) => resize(Number(event.currentTarget.value))}
				>
					{#each sizes as option (option)}<option value={option}>{option}</option>{/each}
				</select>
			</label>
			<span>Page {shown.page} of {shown.pages}</span>
			<button
				type="button"
				aria-label="Previous page"
				class="inline-flex size-7 items-center justify-center {stylex.attrs(styles.control).class}"
				disabled={shown.page <= 1}
				onclick={() => (page = shown.page - 1)}><ChevronLeft size={16} /></button
			>
			<button
				type="button"
				aria-label="Next page"
				class="inline-flex size-7 items-center justify-center {stylex.attrs(styles.control).class}"
				disabled={shown.page >= shown.pages}
				onclick={() => (page = shown.page + 1)}><ChevronRight size={16} /></button
			>
		</div>
	</footer>
</div>
