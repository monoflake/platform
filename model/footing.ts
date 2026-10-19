/**
 * What a footing keeps and what it is asked to write, RFC b8f35. A footing is a database priced by
 * the row, so `check.ts` asks two things of it: that what it keeps is bounded, growing with neither
 * the content its owner holds nor time, and how many rows a day each step of the bootstrap path asks
 * of the vendor's plan, `scope.md`. Reads follow the caches above, and are not counted here.
 */

/** How what a footing keeps grows. Only `bounded` may stand; the rest wait on a row. */
export type Growth =
	/** By a constant for each owner, however much it holds and however long. */
	| 'bounded'
	/** With the content its owner holds. */
	| 'content'
	/** With every owner there has ever been. */
	| 'owners';

export interface Kept {
	/** Whose footing keeps it, vr5lw. */
	of: 'platform' | 'organization';
	what: string;
	from: string;
	grows: Growth;
	/** What bounds it, for `bounded`. */
	bound?: string;
	/** While it is not bounded, the question naming its row. */
	open?: string;
}

export const KEPT: Record<string, Kept> = {
	backing: {
		of: 'organization',
		what: "a scope's stores",
		from: 'b8f35',
		grows: 'bounded',
		bound: 'the stores a scope binds',
	},
	journals: {
		of: 'organization',
		what: 'which journal each placement writes; the journals themselves are kept in the stores',
		from: 'b8f35',
		grows: 'bounded',
		bound: "a row for each placement a scope writes, which the levels' product bounds",
	},
	logs: {
		of: 'organization',
		what: "each tablet's log until the blob archives it",
		from: 'vuanj, b8f35',
		grows: 'bounded',
		bound: "archived in batches at 16 MiB, a parcel's size, vuanj",
	},
	writers: {
		of: 'organization',
		what: 'which writer holds each tablet, and at which generation',
		from: 'b8f35',
		grows: 'bounded',
		bound: "a row for each of a scope's tablets",
	},
	bundle: {
		of: 'organization',
		what: "the organization's bundle",
		from: 'v7v3w',
		grows: 'bounded',
		bound: 'one, holding what the organization opened, as many as its allowance lets it',
	},
	extent: {
		of: 'organization',
		what: "which pieces each content is made of, each piece's parcel, and every parcel",
		from: 'b8f35',
		grows: 'bounded',
		bound:
			"the footing's 10 GB, about 35 million pieces, an organization's 30 TB reached before it; past either it is split",
	},
	anchor: {
		of: 'platform',
		what: "a row for every scope there has been, the platform's footing alone",
		from: 'b8f35',
		grows: 'owners',
		open: "the anchor keeps a row for every scope ever made, never removed: how many the platform's footing holds, and what comes after [D7]",
	},
};

/**
 * Rows written for one of each operation, as RFCs b8f35 and vuanj lay a write out: a tablet's
 * batch is one entry of its log, however many of its rows it changes, and the extent's rows are the
 * footing's own. A row written and later removed counts twice, since a deletion is a write.
 */
export const ROWS = {
	/** A file of one new piece: its log entry and its extent's two rows, its bytes put to the stores
	 * as a journal's object; then the piece's parcel written as the journal is exported, and the
	 * log entry removed once archived. */
	smallWrite: 5,
	/** A file whose content is held already: its log entry, the count raised, the entry removed. */
	duplicate: 3,
	/** A MiB of a large file sealed at once: about one piece's two extent rows, a parcel's row and
	 * the log entry spread over the 16 pieces of a parcel. */
	largeMiB: 2.2,
	/** An app's database commit: its log entry, and its removal once archived. */
	commit: 2,
	/** A tablet a day while idle: none, since a writer's lease is dated by its last entry, b8f35. */
	idleTablet: 0,
	/** A tablet taken over by another writer: its generation raised. */
	takeover: 1,
};

/** Rows written a day that a plan allows a whole account, `lessons.md`: the paid plan's included
 * 50 million a month, spread over 30 days. */
export const ALLOWED: Record<'free' | 'paid', number> = { free: 100_000, paid: 50_000_000 / 30 };

/**
 * What the model assumes of the internal platform's account at each step, until it is measured
 * [C7]: how many organizations the external platform holds, each standing on a cell of its own
 * while cells are one each; how many tablets each organization keeps -- the storage's metadata, the
 * functions', and its apps' databases.
 */
export const ASSUMED = {
	/** The external organizations at each step, the author's own until users come at step 8. */
	external: (step: number) => (step < 1 ? 0 : step < 8 ? 5 : 20),
	/** The internal platform's own organizations: the console's dashboard's and the external platform's. */
	internal: 2,
	tablets: 4,
};
