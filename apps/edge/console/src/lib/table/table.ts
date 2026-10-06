/**
 * A table's rows as the reader asked for them: filtered, sorted, then cut to a page. Pure, so the
 * server's first page is the browser's, and every step is tested apart from the markup.
 */

export interface Column<Row> {
	key: string;
	label: string;
	/** What the column sorts by and compares a filter against. */
	value: (row: Row) => string | number;
	/** The cell as written, which a text filter searches; the value as it is when not given. */
	text?: (row: Row) => string;
	/** A number sorts as one, sets right, and takes `>10`, `<=2`, `=0` as a filter. */
	kind?: 'text' | 'number';
	sortable?: boolean;
	filterable?: boolean;
}

/** The two orders, named as `aria-sort` names them. */
export interface Sort {
	key: string;
	direction: 'ascending' | 'descending';
}

const collator = new Intl.Collator('en-US', { numeric: true, sensitivity: 'base' });

export function written<Row>(column: Column<Row>, row: Row): string {
	return column.text?.(row) ?? String(column.value(row));
}

/** Nothing to compare -- an empty cell, a NaN -- goes last in either order. */
function blank(value: string | number): boolean {
	return value === '' || (typeof value === 'number' && Number.isNaN(value));
}

export function sortRows<Row>(rows: Row[], columns: Column<Row>[], sort?: Sort): Row[] {
	const column = sort && columns.find((one) => one.key === sort.key);
	if (!sort || !column) return rows;
	const sign = sort.direction === 'ascending' ? 1 : -1;
	return rows.toSorted((a, b) => {
		const left = column.value(a);
		const right = column.value(b);
		if (blank(left) || blank(right)) return Number(blank(left)) - Number(blank(right));
		if (typeof left === 'number' && typeof right === 'number') return (left - right) * sign;
		return collator.compare(String(left), String(right)) * sign;
	});
}

const COMPARISON = /^(>=|<=|>|<|=)\s*(-?\d+(?:\.\d+)?)$/;

/**
 * Whether a row's cell answers a filter: a comparison for a number column given one, otherwise
 * the written cell containing the query, case aside.
 */
export function matches<Row>(column: Column<Row>, row: Row, query: string): boolean {
	const wanted = query.trim();
	if (!wanted) return true;
	const compared = column.kind === 'number' ? COMPARISON.exec(wanted) : null;
	if (compared) {
		const [, operator, figure] = compared;
		const value = column.value(row);
		const bound = Number(figure);
		if (typeof value !== 'number' || Number.isNaN(value)) return false;
		if (operator === '>') return value > bound;
		if (operator === '<') return value < bound;
		if (operator === '>=') return value >= bound;
		if (operator === '<=') return value <= bound;
		return value === bound;
	}
	return written(column, row).toLowerCase().includes(wanted.toLowerCase());
}

export function filterRows<Row>(
	rows: Row[],
	columns: Column<Row>[],
	queries: Record<string, string>,
): Row[] {
	const asked = columns.filter((column) => queries[column.key]?.trim());
	if (asked.length === 0) return rows;
	return rows.filter((row) =>
		asked.every((column) => matches(column, row, queries[column.key] ?? '')),
	);
}

export interface Page<Row> {
	rows: Row[];
	/** The page shown, from 1, held inside the pages there are. */
	page: number;
	pages: number;
	/** The first and last row shown, from 1; both 0 when there are none. */
	from: number;
	to: number;
}

export function pageOf<Row>(rows: Row[], page: number, size: number): Page<Row> {
	const per = Math.max(1, Math.floor(size));
	const pages = Math.max(1, Math.ceil(rows.length / per));
	const held = Math.min(pages, Math.max(1, Math.floor(page)));
	const start = (held - 1) * per;
	const shown = rows.slice(start, start + per);
	return {
		rows: shown,
		page: held,
		pages,
		from: shown.length ? start + 1 : 0,
		to: start + shown.length,
	};
}
