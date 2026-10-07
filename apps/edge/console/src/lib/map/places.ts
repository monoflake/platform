/**
 * What the map says of each node beyond where it is: its place, its role in the relay, and where
 * its mark sits. A `Record<Node, ...>`, so a node added to `server/nodes.ts` fails the type check
 * here until it is placed. A role is one of the relay's three core nodes, a relay, or the relay at
 * home, which may go offline -- spec/architecture/relay.md.
 */
import type { Node } from '../server/nodes.ts';

export type Role = 'core' | 'relay' | 'home';

export interface Place {
	place: string;
	role: Role;
	/**
	 * Where the mark sits from the node's own point, in the map's viewBox units, for nodes too close
	 * to tell apart: set by hand so that marks of the largest size neither overlap nor leave Japan.
	 */
	offset?: readonly [number, number];
}

export const PLACES: Record<Node, Place> = {
	tyo: { place: 'Tokyo', role: 'core', offset: [-14, 2] },
	nrt: { place: 'Tokyo, Narita', role: 'relay', offset: [12, -12] },
	hnd: { place: 'Tokyo, Haneda', role: 'relay', offset: [12, 14] },
	gvx: { place: 'Gävle', role: 'core' },
	bru: { place: 'Brussels', role: 'relay' },
	buf: { place: 'Buffalo', role: 'core' },
	rdu: { place: 'Raleigh', role: 'home' },
};

export const ROLES: Record<Role, string> = { core: 'Core', relay: 'Relay', home: 'Home' };
