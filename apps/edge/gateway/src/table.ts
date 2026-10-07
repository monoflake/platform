import type { Row } from '@monoflake/sdk/limits';
import { parse } from 'smol-toml';
import { type Route, type Routing, routesOf } from './declaration.ts';

/**
 * How often one subject may call a route, as a bucket: a row of `[[api.limits]]`, the same rows
 * Caddy counts on the node. See spec/architecture/quota.md, "A limit is a bucket".
 */
export type Allowance = Row;

/** One scope the public API host answers, as the gateway routes it. */
export interface Scope {
	/** `workers`, or the first node whose Caddy answers it. See spec/architecture/services.md. */
	readonly placement: string;
	/** The binding the request goes out through: the Worker's, or the first node's VPC service. */
	readonly binding: string;
	/**
	 * On a node placement, every node's VPC service, the first's included, in the declared order;
	 * asked in a random one. See spec/architecture/gateway.md, "Where a request goes".
	 */
	readonly nodes?: readonly string[];
	/** How `nodes` are ordered for a request; `any` when absent. */
	readonly routing?: Routing;
	/** The Worker behind the binding, on a Workers placement; wrangler.jsonc binds it by name. */
	readonly worker?: string;
	/** Where the Worker answers its API, when not at its root; the path goes on after it. */
	readonly prefix?: string;
	/** Its routes' allowances, when it declares any. */
	readonly limits?: readonly Allowance[];
	/**
	 * What the gateway does for each path, most specific first and `/*` last, every field resolved.
	 * See spec/architecture/gateway.md, "The declaration".
	 */
	readonly routes: readonly Route[];
}

/** The placement that is Cloudflare's Workers; the same string as `WORKERS` in the deploy crate. */
export const WORKERS = 'workers';

/** A binding's name: the scope's or the node's, uppercased, hyphens as underscores. */
export function bindingOf(name: string): string {
	return name.toUpperCase().replaceAll('-', '_');
}

interface Declaration {
	name: string;
	placements: string[];
	api?: { public?: boolean; prefix?: string; routing?: Routing; limits?: Allowance[] } & Record<
		string,
		unknown
	>;
}

/**
 * The public scopes among `declarations`: a Worker's by its first placement, a node's on every node
 * it is placed on. A scope that is not public is left out: the public host does not know it exists.
 * See spec/architecture/gateway.md, "Where a request goes".
 */
export function scopeTable(declarations: readonly string[]): Record<string, Scope> {
	const table: Record<string, Scope> = {};
	const read = declarations.map((text) => parse(text) as unknown as Declaration);
	for (const declaration of read.toSorted((a, b) => a.name.localeCompare(b.name))) {
		const [placement] = declaration.placements;
		if (!declaration.api?.public || placement === undefined) continue;
		const limits = declaration.api.limits?.length ? { limits: declaration.api.limits } : {};
		const routes = routesOf(declaration.name, declaration.api);
		table[declaration.name] =
			placement === WORKERS
				? {
						placement,
						binding: bindingOf(declaration.name),
						worker: declaration.name,
						...(declaration.api.prefix ? { prefix: declaration.api.prefix } : {}),
						...limits,
						routes,
					}
				: {
						placement,
						binding: bindingOf(placement),
						nodes: declaration.placements
							.filter((each) => each !== WORKERS)
							.map((each) => bindingOf(each)),
						routing: declaration.api.routing ?? 'any',
						...limits,
						routes,
					};
	}
	return table;
}

/** The table as the committed module `src/scopes.ts`, which the Worker imports. */
export function renderScopes(table: Record<string, Scope>): string {
	return [
		'// @generated from every apps/*/service.toml by `mise run scopes`; do not edit.',
		"import type { Scope } from './table.ts';",
		'',
		`export const SCOPES: Readonly<Record<string, Scope>> = ${JSON.stringify(table, null, '\t')};`,
		'',
	].join('\n');
}
