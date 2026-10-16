/**
 * Every part and every library the drafts name, each part's dependencies as typed edges. An edge says
 * when it is needed and whether its loss is `hard` -- wrong or stopped -- or `soft` -- slower, staler,
 * more garbage, never wrong. A `hard` edge points to its own layer or below; a `soft` one may point up.
 * A target beginning `?` is something the drafts need and no part is yet: a boundary not drawn.
 * Drafts: 13ixj storage, zn3u5 database, 49qyg functions, vuanj parts, b8f35 root and backing, wnqvu
 * compat. Every `hard`/`soft` here is proposed, not decided; `open` marks the ones in question.
 */
export const VENDOR = -9;

export type When = 'start' | 'serve' | 'deploy' | 'background';

export interface Edge {
	to: string;
	when: When;
	hard: boolean;
	why: string;
	/** Why this edge's boundary is not yet clear. */
	open?: string;
}

export interface Part {
	layer: number;
	edges: Edge[];
	uses: string[];
}

export interface Library {
	what: string;
	/** Whether its output must agree between parts, so its version goes into what it writes. */
	agrees: boolean;
	uses: string[];
}

const e = (to: string, when: When, hard: boolean, why: string, open?: string): Edge => ({
	to,
	when,
	hard,
	why,
	...(open ? { open } : {}),
});
const H = true;
const S = false;
const KEY = (to = 'root') =>
	e(to, 'start', H, 'the root public key, deployed, to verify capabilities');

export const PARTS: Record<string, Part> = {
	app: {
		layer: 1,
		edges: [
			e('function', 'deploy', H, 'an app is deployed as functions, its types checked'),
			e('function', 'serve', H, 'it runs as functions'),
			e('store', 'serve', H, 'the datasets it is bound to'),
			e('database', 'serve', H, 'the database bound to it'),
			e(
				'?entry',
				'serve',
				H,
				'a request reaches its functions; a link is answered through the gateway',
				'the entry is no part: control is a reserved name, its extent undiscussed, b8f35',
			),
		],
		uses: [],
	},
	console: {
		layer: 1,
		edges: [
			e('function', 'serve', H, 'an app like any other'),
			e('store', 'serve', H, 'idem'),
			e('database', 'serve', H, 'idem'),
		],
		uses: [],
	},

	store: {
		layer: 0,
		edges: [
			e('tablet', 'serve', H, 'its metadata per scope'),
			e('blob', 'serve', H, 'content'),
			e('scope', 'serve', H, 'a dataset belongs to one'),
			KEY(),
			e(
				'blob',
				'background',
				S,
				'sweep: bytes nothing names, hashes nothing counts',
				'what starts the sweep: no part keeps time below layer 0',
			),
			e(
				'?entry',
				'serve',
				H,
				'link(): the content answered through the gateway, public or private',
				'the gateway is no part; who checks a private reader is open, 13ixj',
			),
		],
		uses: ['capability*', 'compat*'],
	},
	database: {
		layer: 0,
		edges: [
			e('tablet', 'serve', H, 'a database is a tablet, its directory one'),
			e('scope', 'serve', H, 'ids belong to one'),
			KEY(),
		],
		uses: ['capability*', 'compat*'],
	},
	function: {
		layer: 0,
		edges: [
			e('issuer', 'serve', H, "a call's capabilities"),
			e('executor', 'serve', H, 'runs the code'),
			e('tablet', 'serve', H, 'calls and status(id), queues, schedules, the derive index'),
			e('blob', 'deploy', H, 'code kept by its hash'),
			e('blob', 'serve', S, 'derive outputs: a miss runs it again'),
			e('scope', 'deploy', H, 'the allowance a declaration must fit'),
			e(
				'database',
				'deploy',
				H,
				'a deployment opens the migration window',
				'not in the old graph; whether the call graph also holds bindings is open, 49qyg',
			),
			KEY(),
			e(
				'?clock',
				'serve',
				H,
				'schedule fires at set times, queue retries wait between tries',
				'nothing in the graph keeps time',
			),
		],
		uses: ['capability*', 'vocabulary*', 'wit*', 'compat*'],
	},

	scope: {
		layer: -1,
		edges: [
			e('tablet', 'serve', H, "configuration and allowance in the scope's own tablet"),
			e('anchor', 'serve', H, 'exists while its anchor row does'),
			e(
				'?control',
				'serve',
				H,
				'creating a scope, setting its allowance',
				'"setting it is the control plane\'s", vuanj; the control plane is no part',
			),
		],
		uses: ['compat*'],
	},
	issuer: {
		layer: -1,
		edges: [
			e(
				'tablet',
				'serve',
				H,
				"reads each scope's function tablet for bindings",
				"the tablet is -1, but the rows are function's (0): a schema the issuer must read, so function's migration reaches down to it",
			),
			e('tablet', 'serve', H, "reads the scope's allowance"),
			e(
				'?intermediate',
				'start',
				H,
				'its working keys are certified by the intermediate key, online',
				'nothing holds the intermediate key: no part, not root (offline)',
			),
		],
		uses: ['capability*', 'vocabulary*', 'compat*'],
	},
	tablet: {
		layer: -1,
		edges: [
			e('backing', 'start', H, "its copies' stores and their grades"),
			e('vendor', 'serve', H, "its group's log on its copies' own stores"),
			e('blob', 'background', S, 'archives its log and snapshots'),
			e(
				'blob',
				'start',
				H,
				'a writer or read copy starts from the last snapshot',
				'if snapshots live only in the blob, archiving falling behind is not soft: how long the quorum keeps its log decides',
			),
			KEY(),
			e(
				'?runner',
				'start',
				H,
				'a writer and read copies are processes somewhere; who places them and who decides a handover',
				'where parts run is open, vuanj',
			),
		],
		uses: ['quorum*', 'sqlite*', 'capability*', 'compat*'],
	},
	blob: {
		layer: -1,
		edges: [
			e('backing', 'serve', H, "the scope's stores"),
			e('extent', 'serve', H, 'which blocks a content is made of'),
			e(
				'vendor',
				'serve',
				H,
				"pieces written to the scope's stores",
				'missing from the old graph: whether the blob or the extent writes to a store',
			),
			e('root', 'start', H, 'the masters a scope key and salt are derived from'),
			KEY(),
			e(
				'?repair',
				'background',
				H,
				'repair after a store is lost: until done, data is held below its tier',
				'hard, so it must start from this layer or below; no part does',
			),
			e(
				'?trigger',
				'background',
				S,
				'tier migration and re-encryption, both readable meanwhile',
				'what starts them',
			),
		],
		uses: ['placement*', 'layout*', 'keys*', 'capability*', 'compat*'],
	},
	executor: {
		layer: -1,
		edges: [
			e('host', 'serve', H, 'hands each call to a host'),
			e('blob', 'serve', H, 'code by hash, the first time on a host; kept after'),
			e(
				'?roster',
				'start',
				H,
				'which hosts exist, what each offers',
				'gap 1: anchor is to hold scopes alone, root changes by an operator',
			),
			e(
				'?egress',
				'serve',
				H,
				"an effect's http leaves through the platform's own request interface",
				'that interface is no part, 49qyg',
			),
		],
		uses: ['vocabulary*', 'compat*'],
	},

	backing: {
		layer: -2,
		edges: [
			e('anchor', 'serve', H, "where a scope's backing is"),
			e('vendor', 'serve', H, "its group's log on its copies' own stores"),
			e('root', 'start', H, "the platform's own stores and their secrets"),
			KEY(),
			e('?control', 'serve', H, 'adding a store to a scope', 'deferred by the author, b8f35'),
		],
		uses: ['quorum*', 'capability*', 'compat*'],
	},
	extent: {
		layer: -2,
		edges: [
			e('backing', 'serve', H, "a block's place from the scope's stores"),
			e('vendor', 'serve', H, "its group's log on its copies' own stores"),
			e(
				'?scope-or-global',
				'start',
				H,
				'what one extent covers',
				'gap 2: per scope or one for all',
			),
		],
		uses: ['quorum*', 'placement*', 'compat*'],
	},
	host: {
		layer: -2,
		edges: [e('vendor', 'serve', H, 'runs sandboxes on a machine or a runtime')],
		uses: ['vocabulary*', 'compat*'],
	},

	anchor: {
		layer: -3,
		edges: [
			e('vendor', 'serve', H, "its group's copies on vendors' stores"),
			e('root', 'start', H, "the grades of the platform's stores"),
		],
		uses: ['quorum*', 'compat*'],
	},

	root: {
		layer: -4,
		edges: [
			e(
				'?source',
				'deploy',
				H,
				'what it holds reaches each part',
				'where the source is kept and how it is delivered, b8f35',
			),
		],
		uses: [],
	},
	vendor: { layer: VENDOR, edges: [], uses: [] },
};

/** What reads a running build's range: the write version is the lowest of every reader's highest. */
export const GLOBAL_OPEN = [
	'compat: who knows every running build to compute the write version, wnqvu',
	'deploy: no part has a deploy edge of its own; who replaces a part below layer 0 is unwritten',
];

export const LIBRARIES: Record<string, Library> = {
	'compat*': {
		what: 'versions: a frozen core, and ranges, features and refusals on it, wnqvu',
		agrees: true,
		uses: [],
	},
	'quorum*': {
		what: 'a group of copies, a majority of voters confirming, b8f35',
		agrees: false,
		uses: ['compat*'],
	},
	'capability*': {
		what: 'a capability and its chain to the root, checked, vuanj',
		agrees: false,
		uses: ['compat*'],
	},
	'vocabulary*': {
		what: 'capabilities by name, type and rule; declared, allowed, offered compared, 49qyg',
		agrees: false,
		uses: ['compat*'],
	},
	'placement*': {
		what: 'where a block goes, scored by its hash and each store, vuanj',
		agrees: true,
		uses: ['compat*'],
	},
	'layout*': {
		what: 'content cut into blocks, small packed, parity, b8f35',
		agrees: true,
		uses: ['compat*'],
	},
	'keys*': {
		what: "a scope's salt and key, derived from the masters and its id, b8f35",
		agrees: true,
		uses: ['compat*'],
	},
	'wit*': {
		what: "an export's types, and a call checked against them, 49qyg",
		agrees: false,
		uses: ['compat*'],
	},
	'sqlite*': {
		what: 'the engine a tablet runs',
		agrees: false,
		uses: [],
	},
};
