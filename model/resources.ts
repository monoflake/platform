/**
 * What each resource gives, RFC vr5lw, and what a footing and the products ask of them. `check.ts`
 * asks of every step of the bootstrap path that each deployment's footing, of the platform and of an
 * organization alike, holds one kind of each class, and that its extensions give every kind the
 * products need, a database never among them.
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
	/** What it gives an app's code only on the vendor's paid plan, as the Worker Loader, lessons.md. */
	paid?: Kind[];
	/** Whether it is used only once metering holds, being priced by use, RFC 94y0d. */
	metered?: boolean;
	from: string;
}

export const RESOURCES: Record<string, Resource> = {
	machine: {
		gives: ['function', 'instance', 'container', 'object', 'volume'],
		from: 'vr5lw',
	},
	worker: { gives: ['function'], paid: ['function'], from: 'vr5lw, b8f35' },
	'durable object': { gives: ['instance', 'database'], metered: true, from: 'vr5lw, 94y0d' },
	d1: { gives: ['database'], from: 'vr5lw' },
	r2: { gives: ['object'], from: 'vr5lw' },
	/** The internal platform's three products, as the external platform finds them, vr5lw. */
	'internal products': {
		gives: ['function', 'instance', 'container', 'object', 'database'],
		from: 'vr5lw, 94y0d',
	},
};

/** The resources each ground of `bootstrap.ts` holds. */
export const GROUND: Record<Ground, string[]> = {
	cloudflare: ['worker', 'durable object', 'd1', 'r2'],
	provider: ['machine'],
	home: ['machine'],
	internal: ['internal products'],
};

/**
 * What the products ask of an organization's extensions in v0: a function for compute, an
 * instance for a tablet's writer, RFC 49qyg, and objects for the storage and a tablet's archive,
 * RFC vuanj. The rest of a kind is asked only by an app that declares it.
 */
export const NEEDS: { kind: Kind; why: string }[] = [
	{ kind: 'function', why: "compute runs an app's derive and effect" },
	{ kind: 'instance', why: "a database's tablet has one writer, placed where instance is offered" },
	{ kind: 'object', why: 'storage keeps datasets, and a tablet archives its log and snapshots' },
];

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

/** What a deployment's extensions may give: compute and storage alone, never a database, and what
 * a vendor gives an app's code only on its paid plan once that plan is taken. */
export function extensionKinds(d: Deployment): Set<Kind> {
	return new Set(
		d.ground
			.flatMap((g) => GROUND[g])
			.map((n) => RESOURCES[n])
			.filter((r) => usable(r, d))
			.flatMap((r) =>
				r.gives.filter(
					(k) => CLASS[k] !== 'database' && (d.plan === 'paid' || !r.paid?.includes(k)),
				),
			),
	);
}
