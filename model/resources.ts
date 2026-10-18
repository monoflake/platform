/**
 * What each host's driver gives, RFC vr5lw, and what a footing and the products ask of it. `check.ts`
 * asks of every step of the bootstrap path that each deployment's footing, of the platform and of an
 * organization alike, holds one kind of each class, its compute an `effect` function; that its
 * extensions give every kind the products need; and that every resource reaches the public network
 * by a path, networks joined by jumps.
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

/**
 * A network a resource may be in, RFC vr5lw: the public one; Cloudflare's, joined by a tunnel; and a
 * relay's, joined by a connection held out to a machine with an address. A tailnet and a local
 * network are private networks as well, bound by an organization and on no ground here.
 */
export type Network = 'public' | 'cloudflare' | 'relay';

export interface Resource {
	gives: Kind[];
	/** The networks it is in, where they stand: one in two is a jump between them. */
	in: Network[];
	/** The private networks it stands up, which it is a jump into from the public one. */
	stands?: Network[];
	/** The CPU a call may take on each of the vendor's plans, in milliseconds, lessons.md. A machine's
	 * driver declares how long a call may run as well, a value open [D8]; until it is, a machine is
	 * taken here to bound nothing. */
	cpu?: { free: number; paid: number };
	/** Whether it is used only once metering holds, being priced by use, RFC 94y0d. */
	metered?: boolean;
	from: string;
}

export const RESOURCES: Record<string, Resource> = {
	/** A machine with an address, a database its driver makes of a container and a volume. */
	machine: {
		gives: ['function', 'instance', 'container', 'object', 'volume', 'database'],
		in: ['public', 'cloudflare', 'relay'],
		stands: ['relay'],
		from: 'vr5lw',
	},
	'machine at home': {
		gives: ['function', 'instance', 'container', 'object', 'volume', 'database'],
		in: ['cloudflare', 'relay'],
		from: 'vr5lw',
	},
	worker: {
		gives: ['function'],
		cpu: { free: 10, paid: 300_000 },
		/** Cloudflare's edge, which a Worker stands for here. */
		in: ['public', 'cloudflare'],
		stands: ['cloudflare'],
		from: 'vr5lw, b8f35',
	},
	'durable object': {
		gives: ['instance', 'database'],
		metered: true,
		in: ['cloudflare'],
		from: 'vr5lw, 94y0d',
	},
	/** Reached at the adapter its driver deploys, which is its address, vr5lw. */
	d1: { gives: ['database'], in: ['public', 'cloudflare'], from: 'vr5lw' },
	r2: { gives: ['object'], in: ['public', 'cloudflare'], from: 'vr5lw' },
	/** The internal platform's three products, given the external one through the driver's interface. */
	'internal products': {
		gives: ['function', 'instance', 'container', 'object', 'database'],
		in: ['public'],
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

/** What cutting and sealing a container takes of CPU in a call, in milliseconds: assumed, an order
 * past a free Worker's 10, until it is measured. */
export const ASSUMED_SEAL_CPU = 100;

/**
 * What the products ask of an organization's extensions in v0, each met by any of its kinds: a
 * function for compute; a database for the database product, given in the platform's contract or
 * as a tablet whose one writer an instance holds, RFC 49qyg; and objects for the storage and a
 * tablet's archive, RFC vuanj. The rest of a kind is asked only by an app that declares it.
 */
export const NEEDS: { any: Kind[]; cpu?: number; why: string }[] = [
	{ any: ['function'], why: "compute runs an app's derive and effect" },
	{
		any: ['function'],
		cpu: ASSUMED_SEAL_CPU,
		why: 'the storage cuts and seals up to 16 MiB in a call, b8f35',
	},
	{
		any: ['database', 'instance'],
		why: 'the database product needs a database, or an instance to write a tablet',
	},
	{ any: ['object'], why: 'storage keeps datasets, and a tablet archives its log and snapshots' },
];

const resourcesOf = (d: Deployment) =>
	d.ground.flatMap((g) => GROUND[g]).map((n) => ({ name: n, ...RESOURCES[n] }));

/** What of a deployment's resources reaches the public network by no path, vr5lw: a private
 * network stands only where something of the deployment stands it up, and a resource in two that
 * stand joins them. */
export function unreached(d: Deployment): string[] {
	const all = resourcesOf(d);
	const standing = new Set<Network>(['public', ...all.flatMap((r) => r.stands ?? [])]);
	const reached = new Set<Network>(['public']);
	for (let grew = true; grew;) {
		grew = false;
		for (const r of all) {
			const nets = r.in.filter((n) => standing.has(n));
			if (nets.some((n) => reached.has(n)))
				for (const n of nets)
					if (!reached.has(n)) {
						reached.add(n);
						grew = true;
					}
		}
	}
	return all.filter((r) => !r.in.some((n) => reached.has(n) && standing.has(n))).map((r) => r.name);
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

/** What a deployment's extensions may give, compute, storage and databases, each kind with the
 * most CPU a call may take of it on the deployment's plan. */
export function extensionKinds(d: Deployment): Map<Kind, number> {
	const given = new Map<Kind, number>();
	for (const r of resourcesOf(d).filter((r) => usable(r, d))) {
		const cpu = r.cpu ? r.cpu[d.plan ?? 'free'] : Infinity;
		for (const k of r.gives) given.set(k, Math.max(given.get(k) ?? 0, cpu));
	}
	return given;
}
