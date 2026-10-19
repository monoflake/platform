/**
 * Every question left before the Platform is built, one row each, gathered from the drafts' Open
 * lists, the model's open marks and what the discussion found. A row is crossed off by naming where
 * it was decided. `node model/check.ts --ready` fails while a row that blocks step 0 is open: that
 * is when building begins, `scope.md`.
 */

export type Group =
	/** Written into data or published, so a mistake is never undone: decided before step 0. */
	| 'A'
	/** Blocks building v0, step 0. */
	| 'B'
	/** Blocks a later step, which `blocks` names. */
	| 'C'
	/** Commercial and operational, needed before users or when it is reached. */
	| 'D'
	/** Text gone stale or inconsistent, to fix or drop. */
	| 'E';

export interface Item {
	id: string;
	group: Group;
	what: string;
	/** The drafts or files it comes from, or `found` when the discussion found it. */
	from: string;
	/** For group C, the step of `model/bootstrap.ts` it must be decided before. */
	step?: number;
	/** Where it was decided, once it is; an open row has none. */
	done?: string;
}

export const CHECKLIST: Item[] = [
	// A -- written into data or published: decided before the first byte.
	{
		id: 'A1',
		group: 'A',
		what: "a parcel's header, byte by byte: a magic, the suite, the encryption master's version, the 32 random bytes, and what is authenticated with what it seals",
		from: 'b8f35',
		done: 'b8f35',
	},
	{
		id: 'A2',
		group: 'A',
		what: "STREAM's nonce, bit by bit: a segment's index and the flag for the last, and how a short last segment is told apart",
		from: 'b8f35',
		done: 'b8f35',
	},
	{
		id: 'A3',
		group: 'A',
		what: "every context string BLAKE3's derive_key is given -- a scope's salt, its key, a parcel's key, the gear table -- fixed forever",
		from: 'found',
		done: 'b8f35',
	},
	{
		id: 'A4',
		group: 'A',
		what: "how FastCDC's gear table is derived from the salt, exactly; level 2 is decided, b8f35",
		from: 'found',
		done: 'b8f35',
	},
	{
		id: 'A5',
		group: 'A',
		what: "a scope id's bytes, as the salt and key derivations read them: its form can never change, since the salt would",
		from: 'found',
		done: 'b8f35',
	},
	{
		id: 'A6',
		group: 'A',
		what: "placement's hash: which function scores a parcel against a store, since changing it moves every parcel",
		from: 'vuanj',
		done: 'b8f35',
	},
	{
		id: 'A7',
		group: 'A',
		what: "what each level of a store's durability means, and the levels' codes as buckets and stores record them; the attributes and their names are decided, 13ixj",
		from: 'b8f35, 13ixj',
		done: '13ixj',
	},
	{
		id: 'A8',
		group: 'A',
		what: "an object's extension: the spellings rewritten to one, and the extensions known when served with each one's type; an object takes an extension and never a type, and its type is never stored",
		from: '13ixj',
		done: '13ixj: full spellings unless the short is recognized; IANA types, sandboxed but PDF',
	},
	{
		id: 'A9',
		group: 'A',
		what: "the operations' names, as layer 0's published contract; the products are compute, database and storage, vr5lw",
		from: '13ixj, vr5lw',
		done: 'vr5lw: write, read, describe, list, delete and link; execute; status and submit',
	},
	{
		id: 'A10',
		group: 'A',
		what: "a new name for the storage's 16 MiB unit of sealed data, apart from compute's container, and the context strings that carry it, before any is written",
		from: 'vr5lw',
		done: 'b8f35: a parcel, its context strings monoflake:parcel:key:1 and monoflake:parcel:placement:1',
	},
	{
		id: 'A11',
		group: 'A',
		what: "the labels of the claims the platform adds to CWT's; what each signed record holds and the rights' bits are decided, b8f35",
		from: 'b8f35, v7v3w',
	},

	// B -- blocks building v0.
	{
		id: 'B2',
		group: 'B',
		what: 'the placement rules: where a deployment, a database writer and a parcel go, and how a call finds its way; the extent index is B17',
		from: 'item 4',
		done: 'vr5lw: one model of availability and durability, placed by one function, each item solved on its own',
	},
	{
		id: 'B3',
		group: 'B',
		what: "each record a control holds, field by field -- buckets, databases, apps, bindings, names, schedules, members, extensions, leases, accounts -- and what a control calls beneath it: opening a scope, adding a store, starting a migration; who holds which and how a change is taken are v7v3w's",
		from: 'item 5',
	},
	{
		id: 'B4',
		group: 'B',
		what: "the bundle's format, and how each of the two is signed; a secret never enters one, v7v3w",
		from: 'v7v3w',
		done: "v7v3w: each bundle is CBOR, signed by the control that compiles it, as b8f35's signed record",
	},
	{
		id: 'B5',
		group: 'B',
		what: 'which vendor primitive each part stands on in v0, behind which contract: a Worker, D1, R2, a host on a machine a provider runs',
		from: 'vuanj, v7v3w',
		done: 'vr5lw: a platform takes nothing but what a driver gives, in its own contract',
	},
	{
		id: 'B6',
		group: 'B',
		what: "how the executor runs an app's code on Cloudflare, since a Worker refuses code it is handed at run time: a vendor's way of uploading each app's code, or the hosts alone; to be verified first",
		from: 'found',
		done: 'b8f35, lessons.md',
	},
	{
		id: 'B7',
		group: 'B',
		what: "the driver: how a machine's driver and Cloudflare's are enrolled by hand at step 0, and the CPU and memory reserved for the internal platform's; the primitives' contracts, code's delivery and how a typed value is written are vr5lw's",
		from: '94y0d, vr5lw',
	},
	{
		id: 'B8',
		group: 'B',
		what: "the footing's tables and how their schema is versioned, by compat, as a mixed-version upgrade reads them",
		from: 'found',
		done: 'b8f35: a table is its keys and one versioned CBOR record, and a key changed is a new table',
	},
	{
		id: 'B9',
		group: 'B',
		what: "the entry in v0: where the entry runs and how it routes a public request to an app's deployment, and the record of which organization holds a name, the platform control's, kept beside the anchor in the platform's footing; a machine's certificate is the certificate service's, vr5lw",
		from: 'b8f35, 13ixj, vr5lw',
		done: "vr5lw: an entry is a name bound to an app, served by its host, and a gateway is the organization's, never an app",
	},
	{
		id: 'B10',
		group: 'B',
		what: 'the control plane: what it is, how far it reaches, and its name, and how a person is authenticated to it, since step 0 runs one',
		from: 'b8f35, v7v3w',
		done: "v7v3w: a person signs in to the platform's control, and is a member by their organization's",
	},
	{
		id: 'B11',
		group: 'B',
		what: "day one's commands, written step by step: the deployer, the roster, the source, the entry, the runner, the intermediate",
		from: 'scope.md',
	},
	{
		id: 'B12',
		group: 'B',
		what: "which three places, offline and the operator's, hold each master's shares, since the masters are made at step 0",
		from: 'b8f35',
	},
	{
		id: 'B13',
		group: 'B',
		what: "facts to read from the vendor, into lessons.md: D1's write latency from a machine outside Cloudflare, how many databases an account holds, a Worker's limits on memory, CPU time and request size",
		from: 'found',
		done: 'lessons.md',
	},
	{
		id: 'B14',
		group: 'B',
		what: "the constants v0 picks: how long a capability and a working key live, a sweep's grace, at what size a tablet's log is archived, how long a writer's lease lasts, the longest a write waits after a writer is lost, and an object's longest extension, 13ixj",
		from: 'b8f35, vuanj, 49qyg, model/footing.ts',
	},
	{
		id: 'B15',
		group: 'B',
		what: "how process.md's phases -- theory, simulation, comparison with what exists -- meet this checklist as the test for building, and what replaces the word stage there now the model's stages are s",
		from: 'found',
	},

	{
		id: 'B16',
		group: 'B',
		what: "how a host on a machine reaches a footing in D1: through a Worker of the footing's account, since D1's REST API carries the Cloudflare API's limit of 1,200 requests in five minutes, lessons.md; and how long such a write takes, measured",
		from: 'found',
		done: 'b8f35, lessons.md',
	},
	{
		id: 'B17',
		group: 'B',
		what: "how the extent is kept off the footing's growth: its pages in parcels, the footing keeping their root, and its index cached by generation",
		from: 'model/footing.ts',
		done: "b8f35: the extent stays in the footing, whose 10 GB bounds an organization's pieces, beside its 30 TB in all",
	},
	{
		id: 'B18',
		group: 'B',
		what: 'how many placements a scope writes journals for at once, so its footing stays bounded',
		from: '13ixj, b8f35',
		done: 'b8f35',
	},
	{
		id: 'B19',
		group: 'B',
		what: "what each level of availability means, for compute, databases and storage alike, and how many hosts each asks; and what custody means; durability's levels are A7",
		from: 'v7v3w',
		done: "vr5lw: the levels are 13ixj's, of a host as of a store, and a set composes to one by stated rules alone",
	},
	{
		id: 'B20',
		group: 'B',
		what: "where an ordinary organization's own records are kept -- each tablet's log, the extent's records, its backing, its bundle -- now only the console stands on a footing: a database made of its extensions, placed by configuration; where what manages extensions runs; a database's sizes",
		from: 'vr5lw, v7v3w, b8f35',
		done: 'v7v3w, vr5lw: each organization has a control of its own on a footing the platform gives it',
	},
	{
		id: 'B21',
		group: 'B',
		what: "how a database's adapter in front of D1 tells a statement that only reads, for a capability of read alone, since D1 offers no authorizer and no query_only",
		from: 'b8f35, lessons.md',
		done: "zn3u5: none is told; a database's rights are granted together",
	},
	// C -- blocks a later step.
	{
		id: 'C1',
		group: 'C',
		what: "a tablet's log replicated among hosts, from a footing holding the configuration and f+1 copies, Vertical Paxos's shape, simulated on paper with its failures",
		from: '94y0d',
		step: 9,
	},
	{
		id: 'C2',
		group: 'C',
		what: "what the model's stages past s0 take in, now the internal and external platforms changed what they must cover",
		from: 'scope.md',
		step: 9,
	},
	{
		id: 'C3',
		group: 'C',
		what: "bringing one's own cloud: how a host is bound, what credential its driver gives a binding, and how an admin enters it",
		from: 'b8f35, v7v3w',
		step: 6,
	},
	{
		id: 'C4',
		group: 'C',
		what: 'the grades: how many, and what each means for a tier',
		from: 'b8f35',
		step: 6,
		done: '13ixj, b8f35',
	},
	{
		id: 'C5',
		group: 'C',
		what: 'the private network between resources',
		from: 'v7v3w',
		step: 6,
		done: 'vr5lw: inline, direct or relayed',
	},
	{
		id: 'C6',
		group: 'C',
		what: 'when cells move onto a database organization, and what a cell holds before',
		from: '94y0d',
		step: 10,
	},
	{
		id: 'C7',
		group: 'C',
		what: 'how much an organization writes through its footing before the footing bounds it, measured',
		from: 'b8f35',
		step: 10,
	},
	{
		id: 'C8',
		group: 'C',
		what: 'whether one content named in a content and an opaque bucket is kept once',
		from: '13ixj',
		step: 2,
	},
	{
		id: 'C9',
		group: 'C',
		what: "the storage's metadata held per owner or per bucket",
		from: '13ixj',
		step: 2,
	},
	{
		id: 'C10',
		group: 'C',
		what: "a private link's reader proving they may read it, the authentication of people",
		from: '13ixj, vuanj',
		step: 2,
	},
	{
		id: 'C11',
		group: 'C',
		what: "functions past v0's: daemons and their credentials, a derive's denied imports, an export's version, storage starting a function, whether the call graph holds bindings, and the format of a process's image",
		from: '49qyg',
		step: 2,
	},
	{
		id: 'C12',
		group: 'C',
		what: "the database's analytical kind, a query's limits and the form of its results, deleting a database only while empty",
		from: 'zn3u5',
		step: 2,
	},
	{
		id: 'C13',
		group: 'C',
		what: 'how the data kept in each version on disk is counted, so a reader knows when it may drop an old one',
		from: 'wnqvu',
		step: 3,
	},
	{
		id: 'C14',
		group: 'C',
		what: 'the clock and the egress, built where v0 leaves them for later',
		from: 'scope.md',
		step: 4,
	},

	{
		id: 'C15',
		group: 'C',
		what: "a derive's fuel on Cloudflare: the Worker Loader limits CPU milliseconds, not instructions, so the same input running out at the same place needs its module metered when it is deployed",
		from: 'found',
		step: 2,
	},
	{
		id: 'C16',
		group: 'C',
		what: 'a call graph deeper than the four distinct dynamic Workers a request may have in flight on Cloudflare, lessons.md',
		from: 'found',
		step: 2,
	},
	{
		id: 'C17',
		group: 'C',
		what: "D1's 1 TB an account, which bounds every footing of the one-each cells in one account, and how footings spread over accounts",
		from: 'found',
		step: 10,
	},
	{
		id: 'C19',
		group: 'C',
		what: 'whether an organization keeps one scope id on both the internal and the external platform',
		from: 'b8f35',
		step: 1,
	},
	{
		id: 'C20',
		group: 'C',
		what: 'a store lost without warning, or reaching an end its owner did not choose: what the platform does, and the state each bucket on it is left in',
		from: '13ixj',
		step: 6,
	},
	{
		id: 'C21',
		group: 'C',
		what: 'whether copies are laid out whole or as shards with parity, and whether the owner sees which',
		from: '13ixj',
		step: 6,
	},
	{
		id: 'C18',
		group: 'C',
		what: "what metering counts for each vendor and machine -- requests, CPU, rows, storage, a machine's network in and out and its disk -- where the counts are kept, and the margin it cuts off at",
		from: '94y0d',
		step: 8,
	},
	{
		id: 'C22',
		group: 'C',
		what: "how an organization with no compute offering instance keeps the data its products hold in tablets -- the storage's paths, the function product's calls and messages -- since a footing may not grow with content; configuration is read from the bundle already. Only an organization bringing its own cloud meets it: the internal platform has hosts from step 0",
		from: 'vuanj, v7v3w; B1 before',
		step: 6,
		done: "vr5lw: an extension gives a database in the platform's own contract",
	},
	{
		id: 'C23',
		group: 'C',
		what: "a database's sizes, a small one and a large one, and what each is made of",
		from: 'vr5lw',
		step: 2,
	},
	{
		id: 'C24',
		group: 'C',
		what: 'the comment format a key the platform made carries on a machine, known by every control of every platform by its form alone, and versioned, since it is written onto machines the platform does not hold',
		from: 'vr5lw',
		step: 6,
	},
	{
		id: 'C25',
		group: 'C',
		what: "a network laid over the public one, keeping an organization's addresses off it: an overlay, or a vendor's network from a Worker to a machine; a guard beside the capability, which alone says who may call",
		from: 'vr5lw',
		step: 6,
		done: 'vr5lw: networks joined by jumps, a path compiled by the control; a tailnet is a host of no resource',
	},
	{
		id: 'C26',
		group: 'C',
		what: "to try that a user's Cloudflare account on the free plan gives a custom hostname, a name of the platform's zone pointing at it DNS only, its certificate; and which certificate_authority values the API takes",
		from: 'vr5lw, lessons.md',
		step: 6,
	},
	{
		id: 'C27',
		group: 'C',
		what: "which ways of signing in each step builds -- a passkey; GitHub, Google or Apple; an email's link; a password; a TOTP code -- and what sends an email's link",
		from: 'v7v3w',
		step: 8,
	},
	{
		id: 'C28',
		group: 'C',
		what: "what one way of signing in counts for among a sign-in's factors, a passkey among them, and how an account that lost every way it held is given back",
		from: 'v7v3w',
		step: 8,
	},
	{
		id: 'C29',
		group: 'C',
		what: 'a name for the bucket kind that is cut, compressed and sealed, since content names what lies beneath every bucket',
		from: '13ixj',
		step: 2,
	},
	{
		id: 'C30',
		group: 'C',
		what: "what an organization's gateway does past routing, each on its own: authenticating an app's users, a firewall kept in step in the account it runs in; and the scopes the platform reserves past the storage",
		from: 'vr5lw',
		step: 6,
	},
	// D -- commercial and operational.
	{
		id: 'D1',
		group: 'D',
		what: "the app that charges, an organization's on the internal platform: what it reads of use and how it acts on an organization; charging is no part of the platform and quotas are the binding's, vr5lw, v7v3w",
		from: 'v7v3w',
	},
	{
		id: 'D2',
		group: 'D',
		what: "what becomes of a revoked organization's sealed data in cells the platform pays for",
		from: '94y0d',
		done: '94y0d',
	},
	{
		id: 'D3',
		group: 'D',
		what: 'how often the intermediate key is rotated, whether a machine of the author may rotate it unattended, and how a leaked one is revoked',
		from: 'b8f35',
	},
	{
		id: 'D4',
		group: 'D',
		what: "every other bound past v0's constants: an id's life, a derive's budget, a lock's wait and hold, a dead-letter list",
		from: '49qyg, vuanj',
	},
	{
		id: 'D5',
		group: 'D',
		what: "a host's way to a footing kept short where the vendor's routing lands a connection far: one connection dialed again, reads from replicas, the paid plan's routing measured",
		from: 'lessons.md',
	},
	{
		id: 'D6',
		group: 'D',
		what: 'the background collection: what it repacks below the threshold, how often, and in what order it walks parcels',
		from: 'b8f35',
	},
	{
		id: 'D7',
		group: 'D',
		what: "the anchor's rows, one for every scope ever made: how many the platform's footing holds, and what comes after",
		from: 'model/footing.ts',
	},

	{
		id: 'D8',
		group: 'D',
		what: "how a machine's driver bounds what it holds by how full the machine is, beyond a count, and the default it starts from; and how long a call may run on a machine, a field its driver declares, its default and whether it counts CPU or the clock",
		from: 'vr5lw',
	},

	{
		id: 'D9',
		group: 'D',
		what: "the domains organizations' public names and their storage's names are of, apart from the platform's own and from each other, and asking the Public Suffix List to take them once the platform serves thousands",
		from: 'vr5lw, lessons.md',
		done: 'vr5lw: mofl.fyi, one name an organization at its gateway; the list asked before the platform opens',
	},
	{
		id: 'D10',
		group: 'D',
		what: "the platform signing people in to others' apps itself, by OAuth",
		from: 'v7v3w',
	},
	{
		id: 'D11',
		group: 'D',
		what: "the platform's own CI: what it runs on, and how long it keeps what it builds",
		from: 'vr5lw',
	},
	{
		id: 'D12',
		group: 'D',
		what: 'exporting a bucket, to another object store, a file system or an archive: plaintext, and a right of its own',
		from: '13ixj',
	},

	// E -- stale or inconsistent text.
	{
		id: 'E1',
		group: 'E',
		what: "the issuer's standing capability to read every scope's grants, gone now each organization signs its own: drop it from b8f35's question, v7v3w's Open and the intermediate's contract",
		from: 'b8f35, v7v3w, graph.ts',
		done: 'b8f35, v7v3w, graph.ts',
	},
	{
		id: 'E2',
		group: 'E',
		what: "where what control held stands: answered by the bundle and the footing, so drop vuanj's Open",
		from: 'vuanj',
		done: 'vuanj',
	},
	{
		id: 'E3',
		group: 'E',
		what: "which database is the platform's footing: D1 on the internal platform's own account, so close b8f35's Open",
		from: 'b8f35',
		done: 'b8f35',
	},
	{
		id: 'E4',
		group: 'E',
		what: 'vuanj says the operator revoking an owner deletes its scope at once, v7v3w that what is revoked is stopped and nothing deleted: one must give way',
		from: 'vuanj, v7v3w',
		done: 'vuanj, after v7v3w',
	},
	{
		id: 'E5',
		group: 'E',
		what: "vuanj's sentence that deleting a scope deletes its bytes since its key can always be derived again, which does not follow",
		from: 'vuanj',
		done: 'vuanj',
	},
	{
		id: 'E6',
		group: 'E',
		what: "v7v3w's heading that the platform runs on serverless vendors only, while the internal platform's hosts are machines from step 0: the heading means the platform's half",
		from: 'v7v3w',
		done: 'v7v3w',
	},
	{
		id: 'E7',
		group: 'E',
		what: "the backing's edge to the root for the platform's own stores, while an organization's stores now reach it in the bundle",
		from: 'graph.ts',
		done: 'graph.ts',
	},
	{
		id: 'E8',
		group: 'E',
		what: "b8f35's rule that nothing holds every scope's configuration at once, while the platform's half holds every configuration's truth",
		from: 'found',
		done: 'b8f35',
	},
];
