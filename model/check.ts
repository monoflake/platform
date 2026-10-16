/**
 * Runs v0's dimensions over the model, `scope.md`: D0 serve, D1 bootstrap, D2 restart, D3 upgrade
 * and D5 contract, each printing its question, every violation, and every assumption -- an edge to a
 * boundary whose contract is written. D4 recovery models a failure, so it is v1's, and runs only with
 * `--v1`. Exits 1 when any dimension finds a violation.
 */
import { BOUNDARIES, GLOBAL_OPEN, LIBRARIES, PARTS, VENDOR, type Edge } from './graph.ts';

const layerName = (layer: number) =>
	layer === VENDOR ? 'ground' : layer > 0 ? `+${layer}` : String(layer);
const known = (to: string) => !to.startsWith('?');
const tag = (edge: Edge) => `${edge.when}/${edge.hard ? 'hard' : 'soft'}`;
const designed = Object.entries(PARTS).filter(([, p]) => p.kind === undefined);
const line = (from: string, edge: Edge) => `${from} -> ${edge.to} ${tag(edge)}: ${edge.why}`;
const contracted = (to: string) => BOUNDARIES[to]?.contract !== undefined;

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

/** The order the edges `when` selects allow, the ground first. */
function order(when: (e: Edge) => boolean): string[] {
	const out: string[] = [];
	const seen = new Set<string>();
	const visit = (n: string): void => {
		if (seen.has(n)) return;
		seen.add(n);
		for (const x of PARTS[n]?.edges ?? []) if (when(x) && known(x.to)) visit(x.to);
		out.push(n);
	};
	for (const n of Object.keys(PARTS).sort((a, b) => PARTS[a].layer - PARTS[b].layer)) visit(n);
	return out;
}

/** The edges `when` selects that end at a boundary, split by whether its contract is written. */
function atBoundaries(when: (e: Edge) => boolean): { violations: string[]; assumed: string[] } {
	const hits = designed.flatMap(([n, p]) =>
		p.edges.filter((x) => when(x) && !known(x.to)).map((x) => ({ n, x })),
	);
	return {
		violations: hits
			.filter(({ x }) => !contracted(x.to))
			.map(({ n, x }) => `no contract: ${line(n, x)}`),
		assumed: hits
			.filter(({ x }) => contracted(x.to))
			.map(({ n, x }) => `${n} assumes ${x.to}: ${BOUNDARIES[x.to].contract}`),
	};
}

let failed = false;
function dimension(
	title: string,
	question: string,
	violations: string[],
	notes: string[] = [],
	assumed: string[] = [],
): void {
	console.log(`\n# ${title}\n${question}`);
	console.log(violations.length ? violations.map((v) => `  x ${v}`).join('\n') : '  no violation');
	for (const a of assumed) console.log(`  ~ ${a}`);
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

const serve = (x: Edge) => x.when === 'serve';
const d0 = atBoundaries(serve);
dimension(
	'D0 Serve',
	'On the correct path, does every operation the products promise reach the ground?',
	d0.violations,
	[],
	d0.assumed,
);

const firstUp = (x: Edge) => x.when === 'start' || x.when === 'deploy';
const d1 = atBoundaries(firstUp);
dimension(
	'D1 Bootstrap',
	'From the ground and the operator alone, can every part come up the first time?',
	[
		...cycles(
			(n) => (PARTS[n]?.edges ?? []).filter((x) => firstUp(x) && known(x.to)).map((x) => x.to),
			Object.keys(PARTS),
		).map((c) => `cycle: ${c}`),
		...d1.violations,
	],
	[`order: ${order(firstUp).join(' -> ')}`],
	d1.assumed,
);

const start = (x: Edge) => x.when === 'start';
const d2 = atBoundaries(start);
const reachesGround = (n: string, seen = new Set<string>()): boolean => {
	if (seen.has(n)) return false;
	seen.add(n);
	return (PARTS[n]?.edges ?? []).some(
		(x) => x.hard && known(x.to) && (PARTS[x.to]?.kind === 'ground' || reachesGround(x.to, seen)),
	);
};
dimension(
	'D2 Restart',
	'After a planned stop of everything, can every part come back from what it kept?',
	[
		...designed
			.filter(([n, p]) => p.keeps && !reachesGround(n))
			.map(([n]) => `${n} keeps state, but no hard edge carries it to the ground`),
		...d2.violations,
	],
	[
		`order: ${order(start).join(' -> ')}`,
		`keep state of their own: ${designed
			.filter(([, p]) => p.keeps)
			.map(([n]) => n)
			.join(', ')}`,
	],
	d2.assumed,
);

const crossing = designed.flatMap(([n, p]) =>
	p.edges.filter((x) => x.reads !== undefined).map((x) => ({ from: n, edge: x })),
);
// What replaces a part is the edge marked `replaces`; an edge it deploys others by says nothing.
const d3 = atBoundaries((x) => x.replaces === true);
dimension(
	'D3 Upgrade',
	'While the rest runs, can one part be replaced by a new version?',
	[
		...designed
			.filter(([, p]) => !p.edges.some((x) => x.replaces))
			.map(([n]) => `${n}: nothing says what replaces it`),
		...designed.flatMap(([n, p]) =>
			p.edges.filter((x) => x.replaces && x.to === n).map(() => `${n}: replacing it needs itself`),
		),
		...d3.violations,
		...crossing
			.filter(({ from }) => !PARTS[from].uses.includes('compat*'))
			.map(({ from, edge }) => `${from} reads ${edge.reads}'s format without compat*`),
	],
	GLOBAL_OPEN.map((g) => `open: ${g}`),
	d3.assumed,
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

console.log('\n# Boundaries, and whether each has its contract');
const needed = new Map<string, string[]>();
for (const [name, part] of designed)
	for (const edge of part.edges)
		if (!known(edge.to))
			needed.set(edge.to, [...(needed.get(edge.to) ?? []), `${name} ${tag(edge)}`]);
for (const [to, from] of needed) {
	const b = BOUNDARIES[to];
	console.log(`  ${contracted(to) ? 'contract' : 'none    '} ${to.padEnd(14)} ${from.join(', ')}`);
	console.log(
		`           kept by: ${b?.keptBy ? `${b.keptBy}${b.triage ? ` [${b.triage}]` : ''}` : 'undecided'}`,
	);
}
for (const to of Object.keys(BOUNDARIES))
	if (!needed.has(to)) console.log(`  unused   ${to}: no edge needs it`);
for (const to of needed.keys())
	if (!(to in BOUNDARIES)) console.log(`  unlisted ${to}: add it to BOUNDARIES`);

if (process.argv.includes('--v1')) {
	console.log('\n# D4 Recovery (v1): lose one running part, and what stops by hard serve edges');
	for (const [lost] of designed) {
		const down = new Set([lost]);
		for (let grew = true; grew;) {
			grew = false;
			for (const [n, p] of designed)
				if (!down.has(n) && p.edges.some((x) => x.hard && serve(x) && down.has(x.to))) {
					down.add(n);
					grew = true;
				}
		}
		down.delete(lost);
		console.log(`  ${lost.padEnd(9)} -> ${[...down].join(', ') || 'nothing'}`);
	}
}
process.exitCode = failed ? 1 : 0;
