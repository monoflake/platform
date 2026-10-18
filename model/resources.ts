/**
 * What each host's driver gives, RFC vr5lw, and what a footing and the products ask of it. `check.ts`
 * asks of every step of the bootstrap path that each deployment's footing, of the platform and of an
 * organization alike, holds one kind of each class, its compute an `effect` function; that its
 * extensions give every kind the products need; and that whatever has no address of its own has a
 * relay to be reached through.
 */
import type { Deployment, Ground } from './bootstrap.ts';

export type Class = 'compute' | 'storage' | 'database';

/** A kind of what a resource gives; a database's sizes are open [C23]. */
export type Kind = 'function' | 'instance' | 'container' | 'object' | 'volume' | 'database';

export const CLASS: Record<Kind, Class> = {
	function: 'compute',
	instance: 'compute',
	container: 'compute',
	object: 'storage',
	volume: 'storage',
	database: 'database',
};

export interface Resource {
	gives: Kind[];
	/** Whether it has an address of its own on the public network; one without is reached by a relay. */
	addressed: boolean;
	/** Whether its driver may relay for a host without an address. */
	relays: boolean;
	/** What it gives an app's code only on the vendor's paid plan, as the Worker Loader, lessons.md. */
	paid?: Kind[];
	/** Whether it is used only once metering holds, being priced by use, RFC 94y0d. */
	metered?: boolean;
	from: string;
}

export const RESOURCES: Record<string, Resource> = {
	/** A machine with an address, a database its driver makes of a container and a volume. */
	machine: {
		gives: ['function', 'instance', 'container', 'object', 'volume', 'database'],
		addressed: true,
		relays: true,
		from: 'vr5lw',
	},
	'machine at home': {
		gives: ['function', 'instance', 'container', 'object', 'volume', 'database'],
		addressed: false,
		relays: false,
		from: 'vr5lw',
	},
	worker: {
		gives: ['function'],
		paid: ['function'],
		addressed: true,
		relays: true,
		from: 'vr5lw, b8f35',
	},
	'durable object': {
		gives: ['instance', 'database'],
		metered: true,
		addressed: true,
		relays: false,
		from: 'vr5lw, 94y0d',
	},
	/** Reached at the adapter its driver deploys, which is its address, vr5lw. */
	d1: { gives: ['database'], addressed: true, relays: false, from: 'vr5lw' },
	r2: { gives: ['object'], addressed: true, relays: false, from: 'vr5lw' },
	/** The internal platform's three products, given the external one through the driver's interface. */
	'internal products': {
		gives: ['function', 'instance', 'container', 'object', 'database'],
		addressed: true,
		relays: false,
		from: 'vr5lw, 94y0d',
	},
};

/** The resources each ground of `bootstrap.ts` holds. */
export const GROUND: Record<Ground, string[]> = {
	cloudflare: ['worker', 'durable object', 'd1', 'r2'],
	provider: ['machine'],
	home: ['machine at home'],
	internal: ['internal products'],
};

/**
 * What the products ask of an organization's extensions in v0, each met by any of its kinds: a
 * function for compute; a database for the database product, given in the platform's contract or
 * as a tablet whose one writer an instance holds, RFC 49qyg; and objects for the storage and a
 * tablet's archive, RFC vuanj. The rest of a kind is asked only by an app that declares it.
 */
export const NEEDS: { any: Kind[]; why: string }[] = [
	{ any: ['function'], why: "compute runs an app's derive and effect" },
	{
		any: ['database', 'instance'],
		why: 'the database product needs a database, or an instance to write a tablet',
	},
	{ any: ['object'], why: 'storage keeps datasets, and a tablet archives its log and snapshots' },
];

const resourcesOf = (d: Deployment) =>
	d.ground.flatMap((g) => GROUND[g]).map((n) => ({ name: n, ...RESOURCES[n] }));

/** What of a deployment's hosts has no address and finds no relay among them, vr5lw. */
export function unrelayed(d: Deployment): string[] {
	const all = resourcesOf(d);
	return all.some((r) => r.relays) ? [] : all.filter((r) => !r.addressed).map((r) => r.name);
}

const usable = (r: Resource, d: Deployment) => !r.metered || d.on.includes('metering');

/** What a deployment's footing may hold: anything its ground gives, the paid plan aside, since a
 * footing's compute runs the control's own code and never an app's. */
export function footingKinds(d: Deployment): Set<Kind> {
	return new Set(
		d.ground
			.flatMap((g) => GROUND[g])
			.map((n) => RESOURCES[n])
			.filter((r) => usable(r, d))
			.flatMap((r) => r.gives),
	);
}

/** What a deployment's extensions may give: compute, storage and databases, and what a vendor
 * gives an app's code only on its paid plan once that plan is taken. */
export function extensionKinds(d: Deployment): Set<Kind> {
	return new Set(
		d.ground
			.flatMap((g) => GROUND[g])
			.map((n) => RESOURCES[n])
			.filter((r) => usable(r, d))
			.flatMap((r) => r.gives.filter((k) => d.plan === 'paid' || !r.paid?.includes(k))),
	);
}
