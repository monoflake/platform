import { describe, expect, it } from 'vitest';
import { boundNodes, deployerNodes, drift, render } from './receivers.ts';

describe("the deployer's nodes, generated into the hook", () => {
	it('is not stale against the committed file, and every node is bound', () => {
		expect(drift()).toBeUndefined();
	});

	it('takes the nodes a declaration places it on, never Workers, as bindings', () => {
		const declaration =
			'version = 1\nname = "deployer"\nplacements = ["workers", "tyo", "my-node"]\n';
		expect(deployerNodes(declaration)).toEqual(['TYO', 'MY_NODE']);
		expect(deployerNodes('version = 1\nname = "deployer"\n')).toEqual([]);
	});

	it('reads the bindings out of a wrangler.jsonc', () => {
		const wrangler = '{ "vpc_services": [\n\t{ "binding": "RDU" },\n\t{ "binding": "TYO" },\n] }';
		expect(boundNodes(wrangler)).toEqual(['RDU', 'TYO']);
	});

	it('renders a module the hook imports', () => {
		expect(render(['TYO', 'BUF'])).toContain(
			"export const DEPLOYER_NODES: readonly string[] = ['TYO', 'BUF'];",
		);
	});
});
