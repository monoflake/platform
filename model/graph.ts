/**
 * Every part and every library the drafts name, each part's dependencies as typed edges. An edge
 * says when it is needed and whether its loss is `hard` -- wrong or stopped -- or `soft` -- slower,
 * staler, more garbage, never wrong. A `hard` edge points to its own layer or below; a `soft` one
 * may point up. A target beginning `?` is something the drafts need and no part is yet: a boundary
 * not drawn. Drafts: 13ixj storage, zn3u5 database, 49qyg functions, vuanj parts, b8f35 root and
 * backing, wnqvu compat; v7v3w the two halves; 94y0d the internal and external platforms; the rules
 * they are checked by, `scope.md`. Every `hard`/`soft` here is proposed, not decided; `open` marks
 * the ones in question.
 */
export const VENDOR = -9;

export type When = 'start' | 'serve' | 'deploy' | 'background';

export type Half = 'platform' | 'organization';

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
	/** Whether the platform runs it as an owner, in an organization of its own, RFC vuanj. */
	asOwner?: boolean;
	/** Which half runs it, RFC v7v3w; the root runs nothing, so it has none. */
	half?: Half;
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
		half: 'organization',
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
		half: 'organization',
		asOwner: true,
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
		half: 'organization',
		edges: [
			REPLACED,
			e('?runner', 'serve', H, "where a tablet's writer and copies are"),
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
		half: 'organization',
		edges: [
			REPLACED,
			e('?runner', 'serve', H, "where a tablet's writer and copies are"),
			e('tablet', 'serve', H, 'a database is a tablet, its directory one'),
			e('scope', 'serve', H, 'ids belong to one'),
			KEY(),
		],
		uses: ['capability*', 'compat*'],
	},
	function: {
		layer: 0,
		half: 'organization',
		edges: [
			REPLACED,
			e('?runner', 'serve', H, "where a tablet's writer and copies are"),
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
		half: 'organization',
		edges: [
			REPLACED,
			e('tablet', 'serve', H, "configuration and allowance in the scope's own tablet"),
			e(
				'anchor',
				'deploy',
				H,
				'its anchor row, compiled into the bundle; it exists by its certificate',
			),
		],
		uses: ['compat*'],
	},
	issuer: {
		layer: -1,
		half: 'organization',
		edges: [
			REPLACED,
			e('tablet', 'serve', H, "reads the scope's grants and allowance, in its own format, vuanj"),
			e(
				'?intermediate',
				'deploy',
				H,
				'its signing key, certified for seven days and renewed each day, in the bundle, v7v3w',
			),
		],
		uses: ['capability*', 'vocabulary*', 'compat*'],
	},
	tablet: {
		keeps: true,
		layer: -1,
		half: 'organization',
		edges: [
			REPLACED,
			e('backing', 'start', H, "its copies' stores and their grades"),
			e('footing', 'serve', H, 'its log, until a snapshot in the blob holds it'),
			e('blob', 'background', S, 'archives its log and snapshots'),
			e(
				'blob',
				'start',
				H,
				'a writer or read copy starts from the last snapshot',
				'if snapshots live only in the blob, archiving falling behind is not soft: how long the footing keeps its log decides',
			),
			KEY(),
			e('?runner', 'start', H, 'its writer and read copies are placed, and a handover decided'),
		],
		uses: ['sqlite*', 'capability*', 'compat*'],
	},
	blob: {
		keeps: true,
		layer: -1,
		half: 'organization',
		edges: [
			REPLACED,
			e('backing', 'serve', H, "the scope's stores"),
			e('extent', 'serve', H, 'which pieces a content is made of, and where each is packed'),
			e('footing', 'serve', H, "an open container's journal"),
			e(
				'vendor',
				'serve',
				H,
				"containers written to the scope's stores",
				'missing from the old graph: whether the blob or the extent writes to a store',
			),
			e(
				'root',
				'start',
				H,
				"a scope's salt and key, derived from the masters and kept in the bundle",
			),
			KEY(),
			e(
				'extent',
				'background',
				H,
				'repair after a store is lost: until done, data is held below its tier',
			),
			e('?clock', 'background', S, 'paces a migration the control plane started, b8f35'),
		],
		uses: ['placement*', 'layout*', 'keys*', 'capability*', 'compat*'],
	},
	executor: {
		layer: -1,
		half: 'organization',
		edges: [
			REPLACED,
			e('host', 'serve', H, 'hands each call to a host'),
			e('blob', 'serve', H, 'code by hash, the first time on a host; kept after'),
			e('?roster', 'start', H, 'which hosts exist, what each offers'),
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
		half: 'organization',
		edges: [
			REPLACED,
			e('anchor', 'deploy', H, 'its backing, compiled into the bundle the footing keeps, v7v3w'),
			e('footing', 'serve', H, "kept in the scope's footing"),
			e('root', 'start', H, "the platform's own stores and their secrets"),
			KEY(),
		],
		uses: ['capability*', 'compat*'],
	},
	extent: {
		keeps: true,
		layer: -2,
		half: 'organization',
		edges: [
			REPLACED,
			e('backing', 'serve', H, "a container's place from the scope's stores"),
			e('footing', 'serve', H, "its records, in the scope's footing"),
		],
		uses: ['placement*', 'compat*'],
	},
	host: {
		layer: -2,
		half: 'organization',
		edges: [REPLACED, e('vendor', 'serve', H, 'runs sandboxes on a machine or a runtime')],
		uses: ['vocabulary*', 'compat*'],
	},

	anchor: {
		keeps: true,
		layer: -3,
		half: 'platform',
		edges: [REPLACED, e('footing', 'serve', H, "its rows, in the platform's footing")],
		uses: ['compat*'],
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
	footing: { layer: VENDOR, kind: 'ground', edges: [], uses: [] },
	vendor: { layer: VENDOR, kind: 'ground', edges: [], uses: [] },
	operator: { layer: VENDOR, kind: 'operator', edges: [], uses: [] },
};

/**
 * Every boundary, and the contract it must keep once written: what it provides, and what the
 * dimensions require of it through the parts that need it. Without a contract an edge to it is a
 * violation; with one it is an assumption the next layer down must keep. See `scope.md`.
 */
export interface Boundary {
	contract?: string;
	/** Who keeps the contract, once the layer beneath has said; absent while it is undecided. */
	keptBy?: string;
	/** Decided now, since a mistake is written into data; by hand on day one; or later. */
	triage?: 'decided now' | 'by hand on day one' | 'later';
	/** Which half keeps it, where one does, RFC v7v3w. */
	half?: Half;
}

export const BOUNDARIES: Record<string, Boundary> = {
	'?deployer': {
		half: 'platform',
		keptBy:
			'the operator, standing on the ground: on day one the deployment the operator runs by hand, since what replaces every part can stand on none of them',
		triage: 'by hand on day one',
		contract:
			"installs each part the first time, in the order bootstrap allows, and replaces one part's build by a new one while the rest run, one part at a time. It keeps which build runs where and the version range each reads, on disk, so a planned restart brings each part back at the build recorded, and computes the version each format is written at, wnqvu. Before a replacement it checks the new build reads what its neighbors write now and they read what it will write, and refuses naming the format when either fails. Replacing a part never needs that part, so neither its records nor the builds it delivers rest on any part it replaces. It reads a build's manifest, in compat's format, and carries the build unread. It reads where a part may go from the roster. It starts from the ground and the operator alone; the operator installs it and replaces it. It is the control plane's: while it is lost, everything running goes on running",
	},
	'?entry': {
		half: 'organization',
		keptBy:
			"the organization's half: a request comes in by the resources bound to the organization or shared with it, a node's network or a third-party account the platform operates through its API, v7v3w; on day one the operator sets each app's routes by hand in the organization's account",
		triage: 'by hand on day one',
		contract:
			"an HTTP request addressed to an app is delivered to the function product as a call of that app's request function, and its response returned; a URL under the entry's link prefix is delivered whole to the storage, which answers it. It delivers by a route table in its own format, written by the function product at deployment, and reads only that envelope -- the app a request is for, the link prefix -- carrying the rest of a request and of a link unread. It starts without the function product or the storage running and answers unavailable while either is down; it is the data plane's, and never authenticates an app's users. Who may read a private link is open, 13ixj",
	},
	'?clock': {
		half: 'organization',
		keptBy:
			"the organization's half: its table is configuration the platform keeps and copies down, and each tick is fired by the scheduler of the resource bound to the organization it fires on, written there at deployment, the platform firing it only where a resource has none, v7v3w; later: until it is built no schedule or retry is offered, and the storage's sweep waits, which costs only garbage kept longer",
		triage: 'later',
		contract:
			"at the times a schedule sets, and once at a time asked for, a tick is delivered to the part that wrote it -- a function's schedule, a queue's retry, the storage's sweep. It delivers by a table of schedules and timers in its own format, written by that part, at deployment for a schedule; a tick carries only the row's id, unread. Times missed are merged in it, one tick pending per schedule however many passed. A tick is delivered at least once, never exactly once; the part it reaches drops a repeat by the schedule and the time it was due. Its table is kept in the footing, so a restart loses no schedule; it starts without anything it delivers to. How precise its times are is open",
	},
	'?intermediate': {
		half: 'platform',
		keptBy:
			"the platform's half, since what it holds spans organizations; it certifies each organization's own signing key for seven days and renews it every day, v7v3w; on day one the operator certifies the intermediate with the root private key, and renews each organization's certificate every day, by hand",
		triage: 'by hand on day one',
		contract:
			"certifies each new working key the issuer gives it, with an expiry, in a chain to the root, and signs the issuer's standing capability to read grants and allowances, b8f35. Its own private key and the certificate the root signed for it come from what the root delivers, put there by the operator. It is the platform's half's: an organization's issuer signs on without it for seven days, and it is needed once a day and never on a call. It starts without the issuer; its key and certificate are kept as secrets on disk; its program is replaced by the deployer. The intermediate key itself is rotated by the operator, offline, with the root private key. Open: how often it is rotated; whether a system apart from the platform, such as a machine the author keeps, may rotate it unattended on the author's authority; how a leaked intermediate key is revoked, s1's; how long a working key lives",
	},
	'?runner': {
		half: 'organization',
		keptBy:
			"the organization's half: placement decides at run time by a policy the platform keeps and copies down, on the resources bound to the organization or shared with it, v7v3w; on day one the operator pins each database's writer to one resource by hand",
		triage: 'by hand on day one',
		contract:
			"places each tablet's writer and read copies at run time, on places the roster lists that offer instance, 49qyg, and answers where a tablet's writer and copies are now; it decides when a writer is handed over. Creating a tablet, as an app creating a database while it runs, is the data plane's, so it goes on while the control plane is lost. It promises at least one writer, never exactly one: two may be placed for a moment, and the generation the footing keeps refuses all but one, vuanj. Its record of what is placed where is kept in the footing and never in a tablet, which needs it to start, and a planned restart brings each tablet back where it was. It reads only that record, never a tablet's contents. Keyed daemons, one per key, may come to be placed the same way, 49qyg",
	},
	'?roster': {
		keptBy:
			"the operator: on day one a static list of hosts, delivered with what the root delivers, ?source; what each offers, each host reports itself, b8f35; the places an organization's work may go are the resources bound to it or shared with it, v7v3w",
		triage: 'by hand on day one',
		contract:
			"lists the places that can run something, each with its address and what it offers, in the vocabulary of capabilities -- the sandboxes, the network and the rest, 49qyg. The executor, the runner and the deployer read it. Reading it is the data plane's: while the control plane is lost, the last list is still read. Changing it, a place added or removed, is the control plane's, and on day one the operator's. The list is kept on disk, and it is up before any of its readers",
	},
	'?egress': {
		half: 'organization',
		keptBy:
			"the organization's half: a request leaves by the resource its call runs on, a node's network or a third-party account, v7v3w; later: until the check is built into what the platform deploys, a request leaves unchecked, which on an organization's own resources costs only the guard",
		triage: 'later',
		contract:
			"an effect's HTTP request to the world leaves through it, and the response returns. Each request carries a capability showing its call declared network http, and it checks it, trusting no caller. It reads an HTTP request's envelope -- where it goes, its method, its headers -- whose format is a published standard, the ground's; bodies are carried unread. It sees each request's destination and size and limits them by the scope's allowance; what it counts to limit is soft, so a restart that loses it loosens a limit for a moment and keeps nothing on disk; the amounts are open. Only http goes through it: tcp, udp and icmp leave from the host that offers them, as the roster lists. It starts without the executor or the function product, and is the data plane's: while the control plane is lost, effects still reach the world",
	},
	'?source': {
		keptBy:
			"the operator, standing on the ground: the root private key and the masters' shares held offline by hand, and the rest deployed by the operator as secrets on the platform's own vendor accounts, b8f35",
		triage: 'by hand on day one',
		contract:
			"what the root holds reaches each part that reads it: the root public key every part in both halves, the organization's inside what the platform deploys there; the intermediate's key and certificate, the masters, the platform's own stores and their secrets, and the roster of the platform's own vendor accounts, the platform's half alone. All but the root private key and the masters' shares, held offline, is kept on the platform's own vendor accounts as secrets deployed with the parts that read them, through a vendor contract the platform writes, never in a repository or in a store the platform runs, which needs them to start. A change is the operator's, by hand, and deploys again what reads it. It is the control plane's: while it is lost, every part keeps what it was given",
	},
};

/** What reads a running build's range: the write version is the lowest of every reader's highest. */
export const GLOBAL_OPEN = [
	"control plane: a caller of scope, backing and blob -- creating a scope, setting its allowance, adding a store, starting a migration of layout or key -- never a need of theirs; it is the platform's half and stands on the vendor contracts directly, never on layer 0, v7v3w",
	"function: a deployment checks an app's types and the call graph; who runs a deployment is the control plane's",
];

export const LIBRARIES: Record<string, Library> = {
	'compat*': {
		what: 'versions: a frozen core, and ranges, features and refusals on it, wnqvu',
		agrees: true,
		uses: [],
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
		what: 'where a container goes, scored by its id and each store, vuanj',
		agrees: true,
		uses: ['compat*'],
	},
	'layout*': {
		what: 'content cut by FastCDC into pieces, packed into containers, parity, b8f35',
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
