/**
 * Runs s0's dimensions over the model, `scope.md`: D0 serve, D1 bootstrap, D2 restart, D3 upgrade
 * and D5 contract, each printing its question, every violation, and every assumption -- an edge to
 * a boundary whose contract is written -- and then the bootstrap path, RFC 94y0d, and the
 * checklist. D4 recovery models a failure, so it is s1's, and runs only with `--s1`. With
 * `--ready`, or `--ready=N`, the checklist fails while a row that blocks step 0, or step N, is
 * open, or an open question names no row. Exits 1 when any dimension finds a violation.
 */
import { readdirSync, readFileSync } from 'node:fs';
import { STEPS, STOPS, VERSIONS, WINDOW, type Deployment } from './bootstrap.ts';
import { CHECKLIST } from './checklist.ts';
import { CLASS, NEEDS, extensionKinds, footingKinds, type Class } from './resources.ts';
import { ALLOWED, ASSUMED, KEPT, ROWS } from './footing.ts';
import { BOUNDARIES, GLOBAL_OPEN, LIBRARIES, PARTS, RECORDS, VENDOR, type Edge } from './graph.ts';

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
// The platform runs on itself only while the graph is clean: nothing at layer 0 or below has an edge,
// hard or soft, to what it runs as an owner, RFC vuanj.
for (const [name, part] of designed)
	if (part.layer <= 0)
		for (const edge of part.edges)
			if (PARTS[edge.to]?.asOwner)
				rules.push(`runs as an owner, needed below: ${line(name, edge)}`);
// The organization's half runs on while the platform's cannot be reached: none of its parts needs the
// platform's to serve or to start, and reads a bundle instead, RFC v7v3w.
const halfOf = (to: string) => (known(to) ? PARTS[to]?.half : BOUNDARIES[to]?.half);
for (const [name, part] of designed)
	if (part.half === 'organization')
		for (const edge of part.edges)
			if ((edge.when === 'serve' || edge.when === 'start') && halfOf(edge.to) === 'platform')
				rules.push(`the organization's half needs the platform's: ${line(name, edge)}`);
// What the platform's half holds is configuration, written on the control plane alone, so the data
// plane runs on while the control plane is lost, `scope.md`.
for (const [name, r] of Object.entries(RECORDS)) {
	const config = r.half === 'platform' || r.writes.some((w) => PARTS[w]?.control);
	for (const w of r.writes) {
		if (PARTS[w] === undefined) rules.push(`${w} writes ${name}: no such part`);
		else if (config && !PARTS[w].control)
			rules.push(`the data plane writes configuration: ${w} writes ${name}, ${r.from}`);
		else if (r.half === 'platform' && PARTS[w].half !== 'platform')
			rules.push(`an organization writes the platform's: ${w} writes ${name}, ${r.from}`);
	}
}
// A footing is the platform's or an organization's, and each half stands on its own alone, by any
// edge, RFC vr5lw.
for (const [name, part] of designed)
	for (const edge of part.edges) {
		const to = PARTS[edge.to];
		if (to?.kind === 'ground' && to.half !== undefined && to.half !== part.half)
			rules.push(`stands on the other half's footing: ${line(name, edge)}`);
	}
const hardNext = (n: string) =>
	(PARTS[n]?.edges ?? []).filter((x) => x.hard && known(x.to)).map((x) => x.to);
for (const c of cycles(hardNext, Object.keys(PARTS))) rules.push(`hard cycle: ${c}`);
for (const c of cycles((n) => LIBRARIES[n]?.uses ?? [], Object.keys(LIBRARIES)))
	rules.push(`library cycle: ${c}`);
dimension(
	'Rules',
	"Does every hard edge point down, every library use only libraries, nothing below need an owner, no organization need the platform's half to serve or start, the data plane write no configuration, and each half stand on its own footing alone?",
	rules,
	[
		`soft edges upward, allowed: ${softUp.length ? softUp.join('; ') : 'none'}`,
		`no half, since they run nothing: ${
			designed
				.filter(([, p]) => p.half === undefined)
				.map(([n]) => n)
				.join(', ') || 'none'
		}`,
	],
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

// The bootstrap path, RFC 94y0d: each step holds, and each deployment came to it by a move it may
// take. A version, v, is the Platform's release; a stage, s, is the model's, `scope.md`.
const path: string[] = [];
const stops: string[] = [];
STEPS.forEach((step, i) => {
	const at = `step ${i}`;
	const before = STEPS[i - 1];
	const sides: [string, Deployment | undefined, Deployment | undefined][] = [
		['internal', step.internal, before?.internal],
		['external', step.external, before?.external],
	];
	for (const [name, d, was] of sides) {
		if (!d) continue;
		for (const f of d.on)
			if (!VERSIONS[d.version]?.includes(f))
				path.push(`${at}: the ${name} platform turns on ${f}, which v${d.version} lacks`);
		if (was === undefined) {
			const first = name === 'internal' ? 'by hand' : 'new organization';
			if (d.move !== first)
				path.push(`${at}: the ${name} platform first comes up by ${d.move}, not ${first}`);
		} else if (d.version === was.version) {
			if (d.move !== 'none')
				path.push(`${at}: the ${name} platform moves by ${d.move} with no new version`);
		} else if (d.move === 'rolling' && !was.on.includes('rolling'))
			path.push(
				`${at}: the ${name} platform rolls from v${was.version}, which cannot replace a part while the rest run`,
			);
		else if (d.move === 'planned stop') {
			stops.push(`${at}, the ${name} platform, v${was.version} -> v${d.version}`);
			if (was.on.includes('rolling'))
				path.push(`${at}: the ${name} platform stops, though v${was.version} can roll`);
		} else if (d.move !== 'rolling')
			path.push(`${at}: the ${name} platform changes version by ${d.move}`);
		if (d.ground.includes('provider') && !d.on.includes('hosts'))
			path.push(`${at}: the ${name} platform stands on machines without hosts turned on`);
		// What its ground gives, RFC vr5lw: a footing of one kind of each class, for the platform's
		// control and each organization's alike, and extensions that give what the products need.
		const held = new Set([...footingKinds(d)].map((k) => CLASS[k]));
		for (const c of ['compute', 'storage', 'database'] as Class[])
			if (!held.has(c)) path.push(`${at}: the ${name} platform's footing has no ${c}`);
		if (d.on.includes('products')) {
			const given = extensionKinds(d);
			for (const n of NEEDS)
				if (!given.has(n.kind))
					path.push(`${at}: the ${name} platform's extensions give no ${n.kind}: ${n.why}`);
		}
	}
	const { internal: a, external: b } = step;
	for (const g of a.ground)
		if (g === 'home' || g === 'internal') path.push(`${at}: the internal platform stands on ${g}`);
	if (b && a.version > b.version)
		path.push(
			`${at}: the internal platform runs v${a.version}, newer than the external's v${b.version}`,
		);
	if (b && b.version - a.version > WINDOW)
		path.push(`${at}: the external platform runs more than ${WINDOW} ahead of the internal's pin`);
	const ran = STEPS.slice(0, i);
	if (before && a.version !== before.internal.version)
		if (!ran.some((s) => s.external?.version === a.version))
			path.push(`${at}: the pin moves to v${a.version}, which the external platform never ran`);
	if (before)
		for (const f of a.on)
			if (!before.internal.on.includes(f) && !ran.some((s) => s.external?.on.includes(f)))
				path.push(`${at}: the internal platform turns on ${f}, never proven on the external`);
	if (a.plan === 'paid' && !a.on.includes('metering'))
		path.push(`${at}: the paid plan taken before the internal platform meters its use`);
	if (before?.internal.plan === 'paid' && a.plan !== 'paid')
		path.push(`${at}: the paid plan given up again`);
	if (step.cells && !b) path.push(`${at}: cells, with no external platform`);
	if (step.cells === 'database organization' && !a.on.includes('replicated'))
		path.push(
			`${at}: a database organization without a replicated log, so every footing on it writes through one`,
		);
});
if (stops.length > STOPS)
	path.push(`the bootstrap stops ${stops.length} times, more than ${STOPS}`);
dimension(
	'Bootstrap path',
	'From day one by hand, does every step hold, and does each deployment reach it by a move it may take?',
	path,
	[
		...STEPS.map(
			(s, i) =>
				`${i}: internal v${s.internal.version}${s.internal.plan === 'paid' ? ' paid' : ''}${s.external ? `, external v${s.external.version}` : ''}${s.cells ? `, cells ${s.cells}` : ''} -- ${s.what}`,
		),
		...STEPS.map(
			(s, i) =>
				`${i}: extensions give, internal ${[...extensionKinds(s.internal)].sort().join(' ')}${s.external ? `; external ${[...extensionKinds(s.external)].sort().join(' ')}` : ''}`,
		),
		`planned stops: ${stops.length ? stops.join('; ') : 'none'}`,
	],
);

// The footing, RFC b8f35: what it keeps must be bounded, and what each step asks of the vendor's
// plan is counted in rows a day, the load of an idle platform alone a violation past the plan.
const footing: string[] = [];
for (const [name, k] of Object.entries(KEPT))
	if (k.grows !== 'bounded' && !k.open) footing.push(`${name} grows with ${k.grows}: ${k.what}`);
const load = STEPS.map((step, i) => {
	const external = ASSUMED.external(i);
	const replicated =
		step.cells === 'database organization' && step.internal.on.includes('replicated');
	const organizations =
		ASSUMED.internal + (step.cells === 'one each' ? external : replicated ? 1 : 0);
	const own = organizations * ASSUMED.tablets * ROWS.idleTablet;
	// An external organization's footing is a database of its cell, so each of its writes is a commit
	// there, until a replicated log keeps it off the vendor's footing.
	const theirs = replicated ? 0 : external * ASSUMED.tablets * ROWS.idleTablet * ROWS.commit;
	const idle = own + theirs;
	const allowed = ALLOWED[step.internal.plan ?? 'free'];
	if (idle > allowed)
		footing.push(
			`step ${i}: an idle platform writes ${Math.round(idle)} rows a day, past the ${step.internal.plan ?? 'free'} plan's ${Math.round(allowed)}`,
		);
	const left = Math.max(allowed - idle, 0);
	return `${i}: idle ${Math.round(idle)} of ${Math.round(allowed)} rows a day (${Math.round((idle / allowed) * 100)}%); what is left holds ${Math.floor(left / ROWS.smallWrite)} small writes, or ${Math.floor(left / ROWS.commit)} commits, or ${Math.floor(left / ROWS.largeMiB / 1024)} GiB written large`;
});
dimension(
	'Footing',
	'Is what each footing keeps bounded, and does each step fit the rows a day its plan allows?',
	footing,
	[
		...Object.entries(KEPT).map(
			([name, k]) => `${name}: ${k.grows}${k.bound ? `, by ${k.bound}` : ''} -- ${k.what}`,
		),
		`assumed: ${ASSUMED.tablets} tablets an organization, each writing ${ROWS.idleTablet} rows a day idle, ${ASSUMED.internal} organizations of the internal platform's own`,
		...load,
	],
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

// The completion rule of theory, `spec/process.md`: every boundary is kept by someone and sorted.
const unsorted = [...needed.keys()].filter(
	(to) => !BOUNDARIES[to]?.keptBy || !BOUNDARIES[to]?.triage,
);
console.log(
	`\n# Completion\n  ${unsorted.length ? `not yet kept and sorted: ${unsorted.join(', ')}` : 'every boundary is kept and sorted'}`,
);

// The checklist, `model/checklist.ts`, grows by itself: every open question a draft lists and every
// open mark in the model names its row in brackets, `[B12]`, and one that names none is unfiled
// until it is, so a new structure's new questions reach the checklist without being copied there.
const TAG = /\[([A-E]\d+)\]/g;
const marks: { where: string; text: string }[] = [];
const rfcs = new URL('../rfcs/', import.meta.url);
for (const file of readdirSync(rfcs)
	.filter((f) => f.endsWith('.md'))
	.sort()) {
	const text = readFileSync(new URL(file, rfcs), 'utf8');
	const at = text.indexOf('Open, for the discussion that follows:');
	if (at < 0) continue;
	const id = /-([a-z0-9]{5})\.md$/.exec(file)?.[1] ?? file;
	let bullet: string[] | undefined;
	for (const l of text.slice(at).split('\n').slice(1)) {
		if (l.startsWith('- ')) marks.push({ where: id, text: (bullet = [l.slice(2)]).join(' ') });
		else if (l.startsWith('  ') && bullet) {
			bullet.push(l.trim());
			marks[marks.length - 1].text = bullet.join(' ');
		} else if (l.trim() === '') bullet = undefined;
		else break;
	}
}
for (const [name, part] of Object.entries(PARTS))
	for (const edge of part.edges)
		if (edge.open) marks.push({ where: `${name} -> ${edge.to}`, text: edge.open });
for (const g of GLOBAL_OPEN) marks.push({ where: 'GLOBAL_OPEN', text: g });
for (const [name, k] of Object.entries(KEPT)) {
	if (k.open) marks.push({ where: `footing ${name}`, text: k.open });
	if (k.bound && TAG.test(k.bound)) marks.push({ where: `footing ${name}`, text: k.bound });
	TAG.lastIndex = 0;
}
const openWords = /\b(is|are) open\b|\bOpen:/;
for (const [name, b] of Object.entries(BOUNDARIES)) {
	for (const text of [b.contract, b.keptBy])
		if (text && openWords.test(text)) marks.push({ where: name, text });
	if (b.triage === 'later' && ![b.contract, b.keptBy].some((t) => t && TAG.test(t)))
		marks.push({ where: name, text: `left for later: ${b.keptBy ?? ''}` });
	TAG.lastIndex = 0;
}

const rows: string[] = [];
const ids = new Set<string>();
for (const item of CHECKLIST) {
	if (ids.has(item.id)) rows.push(`${item.id}: listed twice`);
	ids.add(item.id);
	if (!item.id.startsWith(item.group)) rows.push(`${item.id}: filed under ${item.group}`);
	if (item.group === 'C' && (item.step === undefined || STEPS[item.step] === undefined))
		rows.push(`${item.id}: names no step of the bootstrap path`);
	if (item.group !== 'C' && item.step !== undefined)
		rows.push(`${item.id}: only a row of group C waits for a later step`);
}
const unfiled: string[] = [];
for (const m of marks) {
	const named = [...m.text.matchAll(TAG)].map((x) => x[1]);
	if (named.length === 0) unfiled.push(`unfiled, ${m.where}: ${m.text}`);
	for (const id of named) {
		const item = CHECKLIST.find((x) => x.id === id);
		if (item === undefined) rows.push(`${m.where} names ${id}, no row of the checklist`);
		else if (item.done !== undefined)
			rows.push(`${m.where} still lists ${id} open, though it was decided in ${item.done}`);
	}
}

const readyArg = process.argv.find((a) => a === '--ready' || a.startsWith('--ready='));
const ready = readyArg !== undefined;
const upTo = readyArg?.includes('=') ? Number(readyArg.split('=')[1]) : 0;
if (ready && (!Number.isInteger(upTo) || STEPS[upTo] === undefined))
	rows.push(`--ready=${upTo} names no step of the bootstrap path`);
const open = CHECKLIST.filter((x) => x.done === undefined);
const blocking = open.filter(
	(x) =>
		x.group === 'A' || x.group === 'B' || x.group === 'E' || (x.group === 'C' && x.step! <= upTo),
);
dimension(
	'Checklist',
	ready
		? `Is every row that blocks step ${upTo} crossed off, and every open question filed, so it may begin?`
		: 'Is every row well formed, and every open question filed? Run with --ready to ask whether building may begin.',
	[
		...rows,
		...unfiled,
		...(ready ? blocking.map((x) => `open ${x.id}: ${x.what} (${x.from})`) : []),
	],
	[
		`open: ${(['A', 'B', 'C', 'D', 'E'] as const)
			.map((g) => `${g} ${open.filter((x) => x.group === g).length}`)
			.join(
				', ',
			)}; crossed off: ${CHECKLIST.length - open.length}; open questions filed: ${marks.length - unfiled.length} of ${marks.length}`,
		`blocking step ${upTo}: ${blocking.length ? blocking.map((x) => x.id).join(' ') : 'none, it may begin'}`,
		...(ready
			? open
					.filter((x) => !blocking.includes(x))
					.map(
						(x) =>
							`later ${x.id}${x.step !== undefined ? ` (before step ${x.step})` : ''}: ${x.what}`,
					)
			: []),
	],
);

if (process.argv.includes('--s1')) {
	console.log('\n# D4 Recovery (s1): lose one running part, and what stops by hard serve edges');
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
