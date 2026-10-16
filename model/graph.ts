/**
 * Every part and every library the drafts name, each part's dependencies as typed edges. An edge says
 * when it is needed and whether its loss is `hard` -- wrong or stopped -- or `soft` -- slower, staler,
 * more garbage, never wrong. A `hard` edge points to its own layer or below; a `soft` one may point up.
 * A target beginning `?` is something the drafts need and no part is yet: a boundary not drawn.
 * Drafts: 13ixj storage, zn3u5 database, 49qyg functions, vuanj parts, b8f35 root and backing, wnqvu
 * compat; the rules they are checked by, `scope.md`. Every `hard`/`soft` here is proposed, not
 * decided; `open` marks the ones in question.
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
	/**
	 * Who defines the format the source reads across this edge, when it is not the target. A format
	 * carried unread is no one's to name here: a tablet holding another part's rows reads none of them.
	 */
	reads?: string;
	/** Whether this edge is how its part is itself replaced by a new version, D3. */
	replaces?: boolean;
}

export interface Part {
	layer: number;
	/** The ground and the operator are outside the design: trusted as written, never built. */
	kind?: 'ground' | 'operator';
	/** Whether it keeps state of its own, which must reach the ground to outlast a restart. */
	keeps?: boolean;
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
const REPLACED: Edge = {
	...e('?deployer', 'deploy', H, 'replaced by a new version while the rest runs'),
	replaces: true,
};
const KEY = (to = 'root') =>
	e(to, 'start', H, 'the root public key, deployed, to verify capabilities');

export const PARTS: Record<string, Part> = {
	app: {
		layer: 1,
		edges: [
			{
				...e('function', 'deploy', H, 'an app is deployed as functions, its types checked'),
				replaces: true,
			},
			e('function', 'serve', H, 'it runs as functions'),
			e('store', 'serve', H, 'the datasets it is bound to'),
			e('database', 'serve', H, 'the database bound to it'),
		],
		uses: [],
	},
	console: {
		layer: 1,
		edges: [
			{
				...e('function', 'deploy', H, 'an app like any other, deployed as functions'),
				replaces: true,
			},
			e('function', 'serve', H, 'an app like any other'),
			e('store', 'serve', H, 'idem'),
			e('database', 'serve', H, 'idem'),
		],
		uses: [],
	},

	store: {
		layer: 0,
		edges: [
			REPLACED,
			e('tablet', 'serve', H, 'its metadata per scope'),
			e('blob', 'serve', H, 'content'),
			e('scope', 'serve', H, 'a dataset belongs to one'),
			KEY(),
			e('blob', 'background', S, 'sweep: bytes nothing names, hashes nothing counts'),
			e('?clock', 'background', S, 'starts the sweep at set times'),
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
			REPLACED,
			e('tablet', 'serve', H, 'a database is a tablet, its directory one'),
			e('scope', 'serve', H, 'ids belong to one'),
			KEY(),
		],
		uses: ['capability*', 'compat*'],
	},
	function: {
		layer: 0,
		edges: [
			REPLACED,
			e('issuer', 'serve', H, "a call's capabilities"),
			e('executor', 'serve', H, 'runs the code'),
			e('tablet', 'serve', H, 'calls and status(id), queues, schedules, the derive index'),
			e('blob', 'deploy', H, 'code kept by its hash'),
			e('blob', 'serve', S, 'derive outputs: a miss runs it again'),
			e('scope', 'deploy', H, 'the allowance a declaration must fit'),
			e('?entry', 'serve', H, "a request trigger: HTTP reaches an app's function, 49qyg"),
			e('?entry', 'deploy', H, "writes an app's routes, in the entry's format"),
			{
				...e(
					'scope',
					'deploy',
					H,
					"writes an app's grants, derived from its bindings, before the version takes a call",
				),
				reads: 'issuer',
			},
			e(
				'database',
				'deploy',
				H,
				'a deployment opens the migration window',
				'not in the old graph; whether the call graph also holds bindings is open, 49qyg',
			),
			KEY(),
			e('?clock', 'serve', H, 'schedule fires at set times, queue retries wait between tries'),
			e('?clock', 'deploy', H, "writes an app's schedules, in the clock's format"),
		],
		uses: ['capability*', 'vocabulary*', 'wit*', 'compat*'],
	},

	scope: {
		layer: -1,
		edges: [
			REPLACED,
			e('tablet', 'serve', H, "configuration and allowance in the scope's own tablet"),
			e('anchor', 'serve', H, 'exists while its anchor row does'),
		],
		uses: ['compat*'],
	},
	issuer: {
		layer: -1,
		edges: [
			REPLACED,
			e('tablet', 'serve', H, "reads the scope's grants and allowance, in its own format, vuanj"),
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
		keeps: true,
		layer: -1,
		edges: [
			REPLACED,
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
		keeps: true,
		layer: -1,
		edges: [
			REPLACED,
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
			REPLACED,
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
		keeps: true,
		layer: -2,
		edges: [
			REPLACED,
			e('anchor', 'serve', H, "where a scope's backing is"),
			e('vendor', 'serve', H, "its group's log on its copies' own stores"),
			e('root', 'start', H, "the platform's own stores and their secrets"),
			KEY(),
		],
		uses: ['quorum*', 'capability*', 'compat*'],
	},
	extent: {
		keeps: true,
		layer: -2,
		edges: [
			REPLACED,
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
		edges: [REPLACED, e('vendor', 'serve', H, 'runs sandboxes on a machine or a runtime')],
		uses: ['vocabulary*', 'compat*'],
	},

	anchor: {
		keeps: true,
		layer: -3,
		edges: [
			REPLACED,
			e('vendor', 'serve', H, "its group's copies on vendors' stores"),
			e('root', 'start', H, "the grades of the platform's stores"),
		],
		uses: ['quorum*', 'compat*'],
	},

	root: {
		layer: -4,
		edges: [
			{
				...e(
					'?source',
					'deploy',
					H,
					'what it holds reaches each part',
					'where the source is kept and how it is delivered, b8f35',
				),
				replaces: true,
			},
		],
		uses: [],
	},
	vendor: { layer: VENDOR, kind: 'ground', edges: [], uses: [] },
	operator: { layer: VENDOR, kind: 'operator', edges: [], uses: [] },
};

/**
 * Every boundary, and the contract it must keep once written: what it provides, and what the
 * dimensions require of it through the parts that need it. Without a contract an edge to it is a
 * violation; with one it is an assumption the next layer down must keep. See `scope.md`.
 */
export const BOUNDARIES: Record<string, { contract?: string }> = {
	'?deployer': {},
	'?entry': {
		contract:
			"an HTTP request addressed to an app is delivered to the function product as a call of that app's request function, and its response returned; a URL under the entry's link prefix is delivered whole to the storage, which answers it. It delivers by a route table in its own format, written by the function product at deployment, and reads only that envelope -- the app a request is for, the link prefix -- carrying the rest of a request and of a link unread. It starts without the function product or the storage running and answers unavailable while either is down; it is the data plane's, and never authenticates an app's users. Who may read a private link is open, 13ixj",
	},
	'?clock': {
		contract:
			"at the times a schedule sets, and once at a time asked for, a tick is delivered to the part that wrote it -- a function's schedule, a queue's retry, the storage's sweep. It delivers by a table of schedules and timers in its own format, written by that part, at deployment for a schedule; a tick carries only the row's id, unread. Times missed are merged in it, one tick pending per schedule however many passed. A tick is delivered at least once, never exactly once; the part it reaches drops a repeat by the schedule and the time it was due. Its table is kept on disk, so a restart loses no schedule; it starts without anything it delivers to. How precise its times are is open",
	},
	'?intermediate': {},
	'?runner': {},
	'?repair': {},
	'?trigger': {},
	'?roster': {},
	'?egress': {},
	'?scope-or-global': {},
	'?source': {},
};

/** What reads a running build's range: the write version is the lowest of every reader's highest. */
export const GLOBAL_OPEN = [
	'compat: who knows every running build to compute the write version, wnqvu',
	'control plane: a caller of scope and backing -- creating a scope, setting its allowance, adding a store -- never a need of theirs; where it stands is undiscussed',
	"function: a deployment checks an app's types and the call graph; who runs a deployment is the control plane's",
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
