import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { PORT, configOf, isDry, pairs, sources, tokenFor } from './config.ts';

describe('the configuration', () => {
	it('reads the sources as host does, owner and name pairs alone', () => {
		expect(sources(' canmi21/web\tmonoflake/platform \n')).toEqual([
			'canmi21/web',
			'monoflake/platform',
		]);
		expect(sources('platform a/b/c')).toEqual([]);
	});

	it('reads the owners and the zones as comma lists of pairs', () => {
		expect(pairs('console = canmi21/web, gateway=monoflake/platform,=x,y=,z')).toEqual([
			['console', 'canmi21/web'],
			['gateway', 'monoflake/platform'],
		]);
		const config = configOf({
			WORKER_OWNERS: 'console=canmi21/web',
			WORKER_ZONES: 'canmi21/web=canmi.app canmi.net, monoflake/platform=monoflake.com',
		});
		expect(config.owners.get('console')).toBe('canmi21/web');
		expect(config.zones.get('canmi21/web')).toEqual(['canmi.app', 'canmi.net']);
		expect(config.zones.get('monoflake/platform')).toEqual(['monoflake.com']);
	});

	it('reads the resources each repository is given, as kind and identifier', () => {
		const config = configOf({
			WORKER_RESOURCES: 'canmi21/web=d1:a1b2 r2:media  service:aka, other/x=kv:k1',
		});
		expect(config.resources.get('canmi21/web')).toEqual(['d1:a1b2', 'r2:media', 'service:aka']);
		expect(config.resources.get('other/x')).toEqual(['kv:k1']);
		expect(configOf({}).resources.size).toBe(0);
	});

	it('listens on the port its declaration states', () => {
		const declaration = readFileSync(join(import.meta.dirname, '../service.toml'), 'utf8');
		expect(declaration).toMatch(new RegExp(`^port = ${PORT}$`, 'm'));
	});

	it('starts with nothing configured, on its own port, with its data in /data', () => {
		const config = configOf({});
		expect(config.sources).toEqual([]);
		expect(config.owners.size).toBe(0);
		expect(config.readToken).toBeUndefined();
		expect(config.port).toBe(12020);
		expect(config.data).toBe('/data');
	});

	it('runs dry everywhere, or for the Workers named', () => {
		expect(isDry(configOf({ DEPLOYER_DRY: '1' }), 'console')).toBe(true);
		const some = configOf({ DRY_WORKERS: 'console, gateway' });
		expect(isDry(some, 'gateway')).toBe(true);
		expect(isDry(some, 'aka')).toBe(false);
		expect(isDry(configOf({ DEPLOYER_DRY: '0' }), 'console')).toBe(false);
	});
});

describe('the GitHub token, picked by the source', () => {
	const env = { GITHUB_ACTIONS_TOKEN: 'home', GITHUB_ACTIONS_TOKEN_CANMI21: 'canmi' };

	it("is the organization's own for monoflake's repositories", () => {
		expect(tokenFor('monoflake/platform', env)).toBe('home');
		expect(tokenFor('monoflake/infra', env)).toBe('home');
	});

	it("is the owner's for anyone else's", () => {
		expect(tokenFor('canmi21/web', env)).toBe('canmi');
	});

	it('is none for an owner with no token, never the organization one', () => {
		expect(tokenFor('stranger/repo', env)).toBeUndefined();
		expect(tokenFor('canmi21/web', { GITHUB_ACTIONS_TOKEN: 'home' })).toBeUndefined();
		expect(tokenFor('monoflake/platform', { GITHUB_ACTIONS_TOKEN: ' ' })).toBeUndefined();
	});
});
