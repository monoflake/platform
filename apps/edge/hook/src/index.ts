/**
 * The `hook` scope of the public API host: GitHub's webhook for workflow runs arrives here, and a
 * run worth deploying is passed to every node over Workers VPC -- to host for the apps, and to
 * keeper, which alone deploys host. See spec/architecture/services.md, "Every node is the same
 * node".
 */
import { failure, success } from '@canmi/response';
import { URLS } from '@monoflake/sdk';
import { runToDeploy, signed } from './github';

/** Every VPC binding in it is a node's Caddy, through that node's tunnel, named for the node. The
 * nodes are the `vpc_services` of wrangler.jsonc and nowhere else. */
export type Env = Readonly<Record<string, unknown>> & {
	/** The secret GitHub signs each delivery with, set as a Worker secret. */
	readonly WEBHOOK_SECRET: string;
};

function isFetcher(value: unknown): value is Fetcher {
	return typeof (value as Fetcher | undefined)?.fetch === 'function';
}

/** The nodes, by binding name. */
function nodesOf(env: Env): [string, Fetcher][] {
	return Object.entries(env).filter((entry): entry is [string, Fetcher] => isFetcher(entry[1]));
}

/** The public suffix Caddy routes the two receivers under; VPC sends it as the `Host`. */
const SUFFIX = new URL(URLS.internal.app).hostname;

/** Where the notice goes on a node, by label: the panel, which passes it on to host, and keeper.
 * See infra's spec/architecture/host.md, "One name inside, and a domain label outside". */
export const RECEIVERS = ['infra', 'keeper'].map((label) => `http://${label}.${SUFFIX}/notice`);

export async function handle(request: Request, env: Env): Promise<Response> {
	const { pathname } = new URL(request.url);
	// The gateway has taken the scope off; see spec/architecture/services.md.
	if (request.method !== 'POST' || pathname !== '/v1/github') {
		return failure(404, 'no_such_route');
	}
	const body = await request.text();
	if (!(await signed(body, request.headers.get('x-hub-signature-256'), env.WEBHOOK_SECRET))) {
		return failure(401, 'invalid_signature');
	}
	// `ping` arrives when the webhook is set up; every other event is simply not one to act on.
	if (request.headers.get('x-github-event') !== 'workflow_run') {
		return new Response(null, { status: 204 });
	}
	const deploy = runToDeploy(JSON.parse(body));
	if (deploy === undefined) return new Response(null, { status: 204 });
	const { run, repository } = deploy;

	const notice = JSON.stringify({ run, repository });
	const targets = nodesOf(env).flatMap(([node, binding]) =>
		RECEIVERS.map((receiver) => ({ node, receiver, binding })),
	);
	const reached = await Promise.all(
		targets.map(async ({ node, receiver, binding }) => {
			try {
				const answer = await binding.fetch(receiver, {
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: notice,
				});
				return { node, receiver, status: answer.status, ok: answer.ok };
			} catch (error) {
				return { node, receiver, status: String(error), ok: false };
			}
		}),
	);
	const missed = reached.filter(({ ok }) => !ok);
	for (const { node, receiver, status } of missed) {
		console.error(`run ${run}: ${node} did not take it at ${receiver}: ${status}`);
	}
	// A receiver that did not take it fails the delivery, so GitHub shows it and it can be
	// redelivered.
	if (missed.length === 0 && reached.length > 0) {
		return success({ run, repository, reached }, { status: 202 });
	}
	const each = missed.map(({ node, receiver, status }) => `${node} ${receiver} ${status}`);
	return failure(502, 'upstream_unavailable', {
		message: `Run ${run} was not taken by every node: ${each.join(', ') || 'no node is bound'}`,
	});
}

export default { fetch: handle } satisfies ExportedHandler<Env>;
