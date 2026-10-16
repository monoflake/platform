/**
 * Holds the drafts' graph to its rules and asks it four questions. Rules: a `hard` edge points to its
 * own layer or below, a `soft` one anywhere; a library uses only libraries; no cycle among libraries.
 * Then: the boundaries not drawn (targets beginning `?`, edges marked `open`); bootstrap, the order
 * `start` edges allow; upgrade, the parts with no `deploy` edge; recovery, what stops when one part
 * is lost while running, following `hard` `serve` edges.
 */
import { GLOBAL_OPEN, LIBRARIES, PARTS, VENDOR, type Edge } from './graph.ts';

const layerName = (layer: number) =>
	layer === VENDOR ? 'vendor' : layer > 0 ? `+${layer}` : String(layer);
const known = (to: string) => !to.startsWith('?');
const tag = (edge: Edge) => `${edge.when}/${edge.hard ? 'hard' : 'soft'}`;

const violations: string[] = [];
const softUp: string[] = [];
for (const [name, part] of Object.entries(PARTS)) {
	for (const edge of part.edges) {
		if (!known(edge.to)) continue;
		const below = PARTS[edge.to];
		if (below === undefined) violations.push(`missing: ${name} -> ${edge.to}, no part`);
		else if (below.layer > part.layer)
			(edge.hard ? violations : softUp).push(
				`${name} (${layerName(part.layer)}) -> ${edge.to} (${layerName(below.layer)}) ${tag(edge)}: ${edge.why}`,
			);
	}
	for (const lib of part.uses)
		if (LIBRARIES[lib] === undefined) violations.push(`missing: ${name} uses ${lib}, no library`);
}
for (const [name, lib] of Object.entries(LIBRARIES))
	for (const use of lib.uses)
		if (LIBRARIES[use] === undefined) violations.push(`library on a part: ${name} uses ${use}`);

/** Every cycle `edges` closes among `names`, by a depth-first walk that remembers its path. */
function cycles(edges: (name: string) => string[], names: string[]): string[] {
	const found: string[] = [];
	const state = new Map<string, 'on' | 'done'>();
	const walk = (name: string, path: string[]): void => {
		if (state.get(name) === 'done') return;
		if (state.get(name) === 'on') {
			found.push([...path.slice(path.indexOf(name)), name].join(' -> '));
			return;
		}
		state.set(name, 'on');
		for (const next of edges(name)) walk(next, [...path, name]);
		state.set(name, 'done');
	};
	for (const name of names) walk(name, []);
	return found;
}
const hardEdges = (n: string) =>
	(PARTS[n]?.edges ?? []).filter((x) => x.hard && known(x.to)).map((x) => x.to);
for (const c of cycles(hardEdges, Object.keys(PARTS))) violations.push(`hard cycle: ${c}`);
for (const c of cycles((n) => LIBRARIES[n]?.uses ?? [], Object.keys(LIBRARIES)))
	violations.push(`library cycle: ${c}`);

console.log('# Rules');
console.log(
	violations.length
		? violations.join('\n')
		: 'no hard edge upward, no hard cycle, no library on a part',
);
console.log(`\nsoft edges upward (allowed): ${softUp.length ? `\n${softUp.join('\n')}` : 'none'}`);

console.log('\n# Boundaries not drawn: something needed that no part is');
const missing = new Map<string, string[]>();
for (const [name, part] of Object.entries(PARTS))
	for (const edge of part.edges)
		if (!known(edge.to))
			missing.set(edge.to, [
				...(missing.get(edge.to) ?? []),
				`${name} ${tag(edge)}: ${edge.why}${edge.open ? ` -- ${edge.open}` : ''}`,
			]);
for (const [to, from] of missing) console.log(`\n${to}\n  ${from.join('\n  ')}`);

console.log('\n# Boundaries in question: an edge to a part, but its kind or its owner unclear');
for (const [name, part] of Object.entries(PARTS))
	for (const edge of part.edges)
		if (known(edge.to) && edge.open)
			console.log(`${name} -> ${edge.to} ${tag(edge)}: ${edge.open}`);
for (const line of GLOBAL_OPEN) console.log(line);

console.log('\n# Bootstrap: the order start edges allow, from the ground up');
const startOf = (n: string) =>
	(PARTS[n]?.edges ?? []).filter((x) => x.when === 'start' && known(x.to)).map((x) => x.to);
const order: string[] = [];
const seen = new Set<string>();
const visit = (n: string): void => {
	if (seen.has(n)) return;
	seen.add(n);
	for (const d of startOf(n)) visit(d);
	order.push(n);
};
for (const n of Object.keys(PARTS).sort((a, b) => PARTS[a].layer - PARTS[b].layer)) visit(n);
console.log(order.join(' -> '));
const blockedStart = Object.entries(PARTS)
	.filter(([, p]) => p.edges.some((x) => x.when === 'start' && !known(x.to)))
	.map(
		([n, p]) =>
			`${n} (waits on ${p.edges
				.filter((x) => x.when === 'start' && !known(x.to))
				.map((x) => x.to)
				.join(', ')})`,
	);
console.log(`cannot start until a boundary is drawn: ${blockedStart.join('; ') || 'none'}`);

console.log('\n# Upgrade: parts with no deploy edge, so nothing says what replaces them');
console.log(
	Object.entries(PARTS)
		.filter(([n, p]) => n !== 'vendor' && !p.edges.some((x) => x.when === 'deploy'))
		.map(([n]) => n)
		.join(', '),
);

console.log('\n# Recovery: lose one running part, and what stops by hard serve edges');
for (const lost of Object.keys(PARTS)) {
	if (lost === 'vendor') continue;
	const down = new Set([lost]);
	for (let grew = true; grew;) {
		grew = false;
		for (const [n, p] of Object.entries(PARTS))
			if (!down.has(n) && p.edges.some((x) => x.hard && x.when === 'serve' && down.has(x.to))) {
				down.add(n);
				grew = true;
			}
	}
	down.delete(lost);
	console.log(`${lost.padEnd(9)} -> ${[...down].join(', ') || 'nothing'}`);
}
process.exitCode = violations.length ? 1 : 0;
