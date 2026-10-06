/**
 * What the map says of each node beyond where it is: its place, its role in the relay, and where
 * its marker and label sit. A `Record<Node, ...>`, so a node added to `server/nodes.ts` fails the
 * type check here until it is placed. A role is one of the relay's three core nodes, a relay, or
 * the relay at home, which may go offline -- spec/architecture/relay.md.
 */
import type { Node } from '../server/nodes.ts';

export type Role = 'core' | 'relay' | 'home';
export type Side = 'left' | 'right' | 'top' | 'bottom';

export interface Place {
	place: string;
	role: Role;
	/** Where the marker sits from the node's own point, in pixels, for nodes sharing a city. */
	offset?: readonly [number, number];
	/** Which side of its marker the code is written. */
	side: Side;
}

export const PLACES: Record<Node, Place> = {
	tyo: { place: 'Tokyo', role: 'core', offset: [-18, -4], side: 'left' },
	nrt: { place: 'Tokyo, Narita', role: 'relay', offset: [14, -12], side: 'right' },
	hnd: { place: 'Tokyo, Haneda', role: 'relay', offset: [8, 16], side: 'right' },
	gvx: { place: 'Gävle', role: 'core', side: 'right' },
	bru: { place: 'Brussels', role: 'relay', side: 'left' },
	buf: { place: 'Buffalo', role: 'core', side: 'left' },
	rdu: { place: 'Raleigh', role: 'home', side: 'right' },
};

export const ROLES: Record<Role, string> = { core: 'Core', relay: 'Relay', home: 'Home' };
