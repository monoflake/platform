/**
 * `router` as deployed on Workers: one table per isolate, read from the relay and kept a few
 * seconds, and every request on `*.canmi.app` routed by it. See index.ts.
 */
import { type Env, type Table, readState, route, tableKeeper } from './index.ts';

let table: (() => Promise<Table | undefined>) | undefined;

export default {
	fetch(request: Request, env: Env): Promise<Response> {
		table ??= tableKeeper(() => readState(env));
		return route(request, env, { origin: (sent) => fetch(sent), table });
	},
} satisfies ExportedHandler<Env>;
