/**
 * Runs v0's dimensions over the model, `scope.md`: D1 bootstrap, D2 restart, D3 upgrade and D5
 * contract, each printing its question and every violation. D4 recovery models a failure, so it is
 * v1's, and runs only with `--v1`. Exits 1 when any dimension finds a violation.
 */
import { GLOBAL_OPEN, LIBRARIES, PARTS, VENDOR, type Edge } from './graph.ts';

const layerName = (layer: number) =>
	layer === VENDOR ? 'ground' : layer > 0 ? `+${layer}` : String(layer);
const known = (to: string) => !to.startsWith('?');
const tag = (edge: Edge) => `${edge.when}/${edge.hard ? 'hard' : 'soft'}`;
const designed = Object.entries(PARTS).filter(([, p]) => p.kind === undefined);
const line = (from: string, edge: Edge) => `${from} -> ${edge.to} ${tag(edge)}: ${edge.why}`;

/** Every cycle `next` closes among `names`, by a depth-first walk that remembers its path. */
function cycles(next: (name: string) => string[], names: string[]): string[] {
	const found: string[] = [];
	const state = new Map<string, 'on' | 'done'>();
	const walk = (name: string, path: string[]): void => {
		if (state.get(name) === 'done') return;
		if (state.get(name) === 'on') {
			found.push([...path.slice(path.indexOf(name)), name].join(' -> '));
			return;
		}
		state.set(name, 'on');
		for (const n of next(name)) walk(n, [...path, name]);
		state.set(name, 'done');
	};
	for (const name of names) walk(name, []);
	return found;
}

/** The order `edges` allow, the ground first, and what cannot be placed for waiting on a boundary. */
function order(edges: (e: Edge) => boolean): { order: string[]; waiting: string[] } {
	const out: string[] = [];
	const seen = new Set<string>();
	const visit = (n: string): void => {
		if (seen.has(n)) return;
		seen.add(n);
		for (const x of PARTS[n]?.edges ?? []) if (edges(x) && known(x.to)) visit(x.to);
		out.push(n);
	};
	for (const n of Object.keys(PARTS).sort((a, b) => PARTS[a].layer - PARTS[b].layer)) visit(n);
	const waiting = designed.flatMap(([n, p]) =>
		p.edges.filter((x) => edges(x) && !known(x.to)).map((x) => line(n, x)),
	);
	return { order: out, waiting };
}

let failed = false;
function dimension(
	title: string,
	question: string,
	violations: string[],
	notes: string[] = [],
): void {
	console.log(`\n# ${title}\n${question}`);
	console.log(violations.length ? violations.map((v) => `  x ${v}`).join('\n') : '  no violation');
	for (const n of notes) console.log(`  ${n}`);
	if (violations.length) failed = true;
}

// The rules every dimension stands on: a hard edge points to its own layer or below, a library uses
// only libraries, and no hard edge closes a cycle.
const rules: string[] = [];
const softUp: string[] = [];
for (const [name, part] of designed) {
	for (const edge of part.edges) {
		if (!known(edge.to)) continue;
		const target = PARTS[edge.to];
		if (target === undefined) rules.push(`${name} -> ${edge.to}: no such part`);
		else if (target.layer > part.layer && target.kind === undefined)
			(edge.hard ? rules : softUp).push(line(name, edge));
	}
	for (const lib of part.uses)
		if (LIBRARIES[lib] === undefined) rules.push(`${name} uses ${lib}: no such library`);
}
for (const [name, lib] of Object.entries(LIBRARIES))
	for (const use of lib.uses)
		if (LIBRARIES[use] === undefined) rules.push(`${name} uses ${use}: a part`);
const hardNext = (n: string) =>
	(PARTS[n]?.edges ?? []).filter((x) => x.hard && known(x.to)).map((x) => x.to);
for (const c of cycles(hardNext, Object.keys(PARTS))) rules.push(`hard cycle: ${c}`);
for (const c of cycles((n) => LIBRARIES[n]?.uses ?? [], Object.keys(LIBRARIES)))
	rules.push(`library cycle: ${c}`);
dimension(
	'Rules',
	'Does every hard edge point down, and every library use only libraries?',
	rules,
	[`soft edges upward, allowed: ${softUp.length ? softUp.join('; ') : 'none'}`],
);

const d1 = order((x) => x.when === 'start' || x.when === 'deploy');
dimension(
	'D1 Bootstrap',
	'From the ground and the operator alone, can every part come up the first time?',
	[
		...cycles(
			(n) =>
				(PARTS[n]?.edges ?? [])
					.filter((x) => (x.when === 'start' || x.when === 'deploy') && known(x.to))
					.map((x) => x.to),
			Object.keys(PARTS),
		).map((c) => `cycle: ${c}`),
		...d1.waiting.map((w) => `waits on a boundary: ${w}`),
	],
	[`order: ${d1.order.join(' -> ')}`],
);

const d2 = order((x) => x.when === 'start');
const groundOf = (n: string, seen = new Set<string>()): boolean => {
	if (seen.has(n)) return false;
	seen.add(n);
	return (PARTS[n]?.edges ?? []).some(
		(x) => x.hard && known(x.to) && (PARTS[x.to]?.kind === 'ground' || groundOf(x.to, seen)),
	);
};
dimension(
	'D2 Restart',
	'After a planned stop of everything, can every part come back from what it kept?',
	[
		...designed
			.filter(([n, p]) => p.keeps && !groundOf(n))
			.map(([n]) => `${n} keeps state, but no hard edge carries it to the ground`),
		...d2.waiting.map((w) => `waits on a boundary: ${w}`),
	],
	[
		`order: ${d2.order.join(' -> ')}`,
		`keep state of their own: ${designed
			.filter(([, p]) => p.keeps)
			.map(([n]) => n)
			.join(', ')}`,
	],
);

const crossing = designed.flatMap(([n, p]) =>
	p.edges.filter((x) => x.reads !== undefined).map((x) => ({ from: n, edge: x })),
);
dimension(
	'D3 Upgrade',
	'While the rest runs, can one part be replaced by a new version?',
	[
		...designed
			.filter(([, p]) => !p.edges.some((x) => x.when === 'deploy'))
			.map(([n]) => `${n}: no deploy edge, so nothing says what replaces it`),
		...designed.flatMap(([n, p]) =>
			p.edges
				.filter((x) => x.when === 'deploy' && known(x.to) && x.to === n)
				.map((x) => `${n}: replacing it needs itself`),
		),
		...crossing
			.filter(({ from }) => !PARTS[from].uses.includes('compat*'))
			.map(({ from, edge }) => `${from} reads ${edge.reads}'s format without compat*`),
	],
	GLOBAL_OPEN.map((g) => `open: ${g}`),
);

dimension(
	'D5 Contract',
	'Is every format a part reads defined at its own layer or below? Carried unread is exempt.',
	crossing
		.filter(({ from, edge }) => (PARTS[edge.reads!]?.layer ?? 0) > PARTS[from].layer)
		.map(
			({ from, edge }) =>
				`${from} (${layerName(PARTS[from].layer)}) reads ${edge.reads} (${layerName(PARTS[edge.reads!].layer)})'s format: ${edge.why}`,
		),
);

console.log('\n# Boundaries: something needed that no part is yet');
const missing = new Map<string, string[]>();
for (const [name, part] of designed)
	for (const edge of part.edges)
		if (!known(edge.to))
			missing.set(edge.to, [...(missing.get(edge.to) ?? []), `${name} ${tag(edge)}`]);
for (const [to, from] of missing) console.log(`  ${to.padEnd(17)} ${from.join(', ')}`);

if (process.argv.includes('--v1')) {
	console.log('\n# D4 Recovery (v1): lose one running part, and what stops by hard serve edges');
	for (const [lost] of designed) {
		const down = new Set([lost]);
		for (let grew = true; grew;) {
			grew = false;
			for (const [n, p] of designed)
				if (!down.has(n) && p.edges.some((x) => x.hard && x.when === 'serve' && down.has(x.to))) {
					down.add(n);
					grew = true;
				}
		}
		down.delete(lost);
		console.log(`  ${lost.padEnd(9)} -> ${[...down].join(', ') || 'nothing'}`);
	}
}
process.exitCode = failed ? 1 : 0;
