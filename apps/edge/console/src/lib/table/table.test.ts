import { describe, expect, it } from 'vitest';
import { filterRows, matches, pageOf, sortRows, type Column } from './table.ts';

interface App {
	name: string;
	cpu: number;
}

const name: Column<App> = { key: 'name', label: 'Name', value: (app) => app.name };
const cpu: Column<App> = {
	key: 'cpu',
	label: 'CPU',
	kind: 'number',
	value: (app) => app.cpu,
	text: (app) => `${app.cpu}%`,
};
const columns = [name, cpu];
const web10: App = { name: 'web10', cpu: 4 };
const web2: App = { name: 'Web2', cpu: Number.NaN };
const api: App = { name: 'api', cpu: 40 };
const apps = [web10, web2, api];

describe('sortRows', () => {
	it('sorts text the way a reader counts, case aside', () => {
		const sorted = sortRows(apps, columns, { key: 'name', direction: 'ascending' });
		expect(sorted.map((app) => app.name)).toEqual(['api', 'Web2', 'web10']);
	});

	it('sorts numbers as numbers, and an unread cell last in either order', () => {
		const down = sortRows(apps, columns, { key: 'cpu', direction: 'descending' });
		expect(down.map((app) => app.name)).toEqual(['api', 'web10', 'Web2']);
		const up = sortRows(apps, columns, { key: 'cpu', direction: 'ascending' });
		expect(up.map((app) => app.name)).toEqual(['web10', 'api', 'Web2']);
	});

	it('leaves the rows as given with no sort, and never sorts them in place', () => {
		expect(sortRows(apps, columns)).toBe(apps);
		sortRows(apps, columns, { key: 'name', direction: 'descending' });
		expect(apps[0]?.name).toBe('web10');
	});
});

describe('filters', () => {
	it('searches the written cell, case aside', () => {
		expect(filterRows(apps, columns, { name: 'WEB' }).map((app) => app.name)).toEqual([
			'web10',
			'Web2',
		]);
		// `40%` is what the reader sees, so `%` finds it.
		expect(filterRows(apps, columns, { cpu: '40%' }).map((app) => app.name)).toEqual(['api']);
	});

	it('compares a number column given an operator, and an unread cell never matches one', () => {
		expect(matches(cpu, web10, '>3')).toBe(true);
		expect(matches(cpu, web10, '<= 3')).toBe(false);
		expect(matches(cpu, api, '=40')).toBe(true);
		expect(matches(cpu, web2, '>0')).toBe(false);
	});

	it('takes every column asked at once, and blank queries as none', () => {
		expect(filterRows(apps, columns, { name: 'web', cpu: '>1' }).map((app) => app.name)).toEqual([
			'web10',
		]);
		expect(filterRows(apps, columns, { name: '  ' })).toBe(apps);
	});
});

describe('pageOf', () => {
	const rows = Array.from({ length: 23 }, (_, index) => index);

	it('cuts a page and says which rows it holds, from 1', () => {
		expect(pageOf(rows, 3, 10)).toEqual({ rows: [20, 21, 22], page: 3, pages: 3, from: 21, to: 23 });
	});

	it('holds the page inside the pages there are, as a filter shrinks them', () => {
		expect(pageOf(rows, 9, 10).page).toBe(3);
		expect(pageOf(rows, 0, 10).page).toBe(1);
	});

	it('has one empty page for no rows', () => {
		expect(pageOf([], 1, 25)).toEqual({ rows: [], page: 1, pages: 1, from: 0, to: 0 });
	});
});
