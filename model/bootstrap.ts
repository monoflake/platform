/**
 * The bootstrap path, RFC 94y0d: what each version of the Platform can do, what each step runs, and
 * how each deployment came to it from the step before. `check.ts` runs it in s0, on the correct
 * path alone; how a move fails, and the replicated log a database organization needs, are s1's.
 */

/** What a version of the Platform can do. A deployment turns on some of what its version has. */
export type Feature =
	/** The three products, standing on a footing. */
	| 'products'
	/** A machine a provider runs, bound as a host by the ordinary flow, its commands the operator's. */
	| 'hosts'
	/** An upgrade by D3: one part replaced while the rest run. */
	| 'rolling'
	/** The deployer, in place of day one's commands. */
	| 'deployer'
	/** A user binding a cloud of their own. */
	| 'byoc'
	/** An organization's extensions spread over vendors, so losing one is survived. */
	| 'vendors'
	/** What each resource is used for counted, and cut off short of a limit, RFC 94y0d. */
	| 'metering'
	/** A tablet's log replicated among hosts offering `instance`, not kept in a footing. */
	| 'replicated';

export const VERSIONS: Record<number, Feature[]> = {
	0: ['products', 'hosts'],
	1: ['products', 'hosts', 'rolling'],
	2: ['products', 'hosts', 'rolling', 'deployer'],
	3: ['products', 'hosts', 'rolling', 'deployer', 'byoc', 'vendors', 'metering'],
	4: ['products', 'hosts', 'rolling', 'deployer', 'byoc', 'vendors', 'metering', 'replicated'],
};

/** What a deployment stands on. Only `provider` offers `instance`, 49qyg. */
export type Ground =
	| 'cloudflare'
	/** A machine a provider runs. */
	| 'provider'
	/** A machine the author keeps at home. */
	| 'home'
	/** The internal platform's three products. */
	| 'internal';

/** How a deployment came to a step from the one before. */
export type Move = 'by hand' | 'new organization' | 'rolling' | 'planned stop' | 'none';

export interface Deployment {
	version: number;
	on: Feature[];
	ground: Ground[];
	move: Move;
	/** The vendor's plan the deployment's Cloudflare account is on: the internal platform's is paid
	 * from step 0, RFC 94y0d. */
	plan?: 'free' | 'paid';
}

export interface Step {
	what: string;
	internal: Deployment;
	external?: Deployment;
	/** How external organizations are placed on internal ones, RFC 94y0d. */
	cells?: 'one each' | 'database organization';
	/** Who uses the platform: the author and a friend or two unless others are invited, RFC 94y0d. */
	users?: 'author' | 'invited';
}

const internal = (version: number, on: Feature[], move: Move): Deployment => ({
	version,
	on,
	ground: ['cloudflare', 'provider'],
	move,
	plan: 'paid',
});
const OWN_CLOUDS: Ground[] = ['internal', 'cloudflare', 'provider', 'home'];

export const STEPS: Step[] = [
	{
		what: 'v0 installed as the internal platform, its own half by hand, its hosts bound as any host is',
		internal: internal(0, ['products', 'hosts'], 'by hand'),
	},
	{
		what: 'v0 deployed again as the external platform, an organization on the internal one',
		internal: internal(0, ['products', 'hosts'], 'none'),
		external: { version: 0, on: ['products'], ground: ['internal'], move: 'new organization' },
		cells: 'one each',
	},
	{
		what: 'an upgrade by D3 built, the external platform moved to it',
		internal: internal(0, ['products', 'hosts'], 'none'),
		external: {
			version: 1,
			on: ['products', 'rolling'],
			ground: ['internal'],
			move: 'planned stop',
		},
		cells: 'one each',
	},
	{
		what: 'the pin moved to v1',
		internal: internal(1, ['products', 'hosts', 'rolling'], 'planned stop'),
		external: { version: 1, on: ['products', 'rolling'], ground: ['internal'], move: 'none' },
		cells: 'one each',
	},
	{
		what: 'the deployer built',
		internal: internal(1, ['products', 'hosts', 'rolling'], 'none'),
		external: {
			version: 2,
			on: ['products', 'rolling', 'deployer'],
			ground: ['internal'],
			move: 'rolling',
		},
		cells: 'one each',
	},
	{
		what: 'the pin moved to v2',
		internal: internal(2, ['products', 'hosts', 'rolling', 'deployer'], 'rolling'),
		external: {
			version: 2,
			on: ['products', 'rolling', 'deployer'],
			ground: ['internal'],
			move: 'none',
		},
		cells: 'one each',
	},
	{
		what: "bringing one's own cloud, more vendors than one and metering built, proven on the author's own organizations",
		internal: internal(2, ['products', 'hosts', 'rolling', 'deployer'], 'none'),
		external: {
			version: 3,
			on: ['products', 'hosts', 'rolling', 'deployer', 'byoc', 'vendors', 'metering'],
			ground: OWN_CLOUDS,
			move: 'rolling',
		},
		cells: 'one each',
	},
	{
		what: 'the pin moved to v3: the internal platform survives losing a vendor, and meters its use',
		internal: internal(
			3,
			['products', 'hosts', 'rolling', 'deployer', 'vendors', 'metering'],
			'rolling',
		),
		external: {
			version: 3,
			on: ['products', 'hosts', 'rolling', 'deployer', 'byoc', 'vendors', 'metering'],
			ground: OWN_CLOUDS,
			move: 'none',
		},
		cells: 'one each',
	},
	{
		what: 'others than the author and a friend or two invited to test, a checkpoint, once metering holds',
		internal: internal(
			3,
			['products', 'hosts', 'rolling', 'deployer', 'vendors', 'metering'],
			'none',
		),
		external: {
			version: 3,
			on: ['products', 'hosts', 'rolling', 'deployer', 'byoc', 'vendors', 'metering'],
			ground: OWN_CLOUDS,
			move: 'none',
		},
		cells: 'one each',
		users: 'invited',
	},
	{
		what: "a tablet's log replicated among hosts built, proven on the external platform",
		internal: {
			...internal(3, ['products', 'hosts', 'rolling', 'deployer', 'vendors', 'metering'], 'none'),
		},
		external: {
			version: 4,
			on: ['products', 'hosts', 'rolling', 'deployer', 'byoc', 'vendors', 'metering', 'replicated'],
			ground: OWN_CLOUDS,
			move: 'rolling',
		},
		cells: 'one each',
		users: 'invited',
	},
	{
		what: 'the pin moved to v4: cells move onto a database organization',
		internal: {
			...internal(
				4,
				['products', 'hosts', 'rolling', 'deployer', 'vendors', 'metering', 'replicated'],
				'rolling',
			),
		},
		external: {
			version: 4,
			on: ['products', 'hosts', 'rolling', 'deployer', 'byoc', 'vendors', 'metering', 'replicated'],
			ground: OWN_CLOUDS,
			move: 'none',
		},
		cells: 'database organization',
		users: 'invited',
	},
];

/** How far the external platform's newest version may run ahead of the internal's pin. */
export const WINDOW = 1;

/** How many planned stops the bootstrap may take in all, RFC 94y0d. */
export const STOPS = 5;
