/**
 * Every node as this browser holds it: seeded from the cluster a page loaded on the server, then
 * kept by the socket, or by polling while it is down. One per layout, which hands it to every page
 * through context. See src/lib/feed.ts and src/lib/view.ts.
 */
import { createContext } from 'svelte';
import { listen, type Mode } from './feed.ts';
import { EMPTY, merge, mergeCluster } from './view.ts';
import type { Cluster } from './wire.ts';

export class Live {
	/** Replaced whole on every message that holds anything newer; see src/lib/view.ts. */
	view = $state.raw(EMPTY);
	mode: Mode = $state('connecting');
	failure: string | undefined = $state();

	/** Takes in what a server load read; a node held newer already stays as held. */
	seed(cluster: Cluster) {
		this.view = mergeCluster(this.view, cluster);
	}

	/** Starts listening; the returned function stops. */
	start(): () => void {
		return listen({
			live: (message) => (this.view = merge(this.view, message)),
			polled: (cluster) => (this.view = mergeCluster(this.view, cluster)),
			mode: (next) => (this.mode = next),
			failure: (why) => (this.failure = why),
		});
	}
}

export const [live, provideLive] = createContext<Live>();
