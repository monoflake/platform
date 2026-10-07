import { existsSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { entriesOf, refusalOf, unpack } from './artifact.ts';
import { PACKAGED, type Item, zipOf } from './fixtures.ts';
import { Refused } from './github.ts';

function refused(items: readonly Item[]): string {
	try {
		entriesOf(zipOf(items));
	} catch (error) {
		expect(error).toBeInstanceOf(Refused);
		return (error as Error).message;
	}
	return '';
}

describe('an artifact', () => {
	it('unpacks what the packaging writes, dotfiles in the assets included', async () => {
		const directory = join(mkdtempSync(join(tmpdir(), 'deployer-')), 'artifact');
		const zip = `${directory}.zip`;
		writeFileSync(zip, zipOf(PACKAGED));
		await unpack(zip, directory);
		expect(readFileSync(join(directory, 'bundle/_worker.js'), 'utf8')).toBe('export default {}');
		expect(existsSync(join(directory, 'assets/.well-known/security.txt'))).toBe(true);
		expect(readdirSync(directory).toSorted()).toEqual([
			'assets',
			'bundle',
			'service.toml',
			'wrangler.json',
		]);
	});

	it('refuses an extra file at the top', () => {
		expect(refused([...PACKAGED, { name: 'package.json', data: '{}' }])).toMatch(/package\.json/);
		expect(refused([...PACKAGED, { name: 'other/x.js' }])).toMatch(/other/);
	});

	it('refuses a dotfile or a dot directory outside the assets', () => {
		const top = refused([...PACKAGED, { name: '.wrangler/deploy/config.json' }]);
		expect(top).toMatch(/\.wrangler.* is not wrangler\.json/);
		expect(refused([...PACKAGED, { name: 'bundle/.config/x' }])).toMatch(/dotfile/);
		expect(refused([...PACKAGED, { name: '.npmrc' }])).toMatch(/\.npmrc/);
	});

	it('refuses an environment file anywhere, the assets too', () => {
		for (const name of ['.env', 'bundle/.dev.vars', 'assets/.env', 'assets/a/.env.production']) {
			expect(refused([...PACKAGED, { name }])).toMatch(/environment|dotfile|not wrangler/);
		}
		expect(refusalOf('assets/.dev.vars', false)).toMatch(/environment/);
	});

	it('refuses a link, and anything else that is not a file or a directory', () => {
		const link = { name: 'bundle/escape.js', data: '/etc/passwd', mode: 0o120777 };
		expect(refused([...PACKAGED, link])).toMatch(/not a plain file/);
		expect(refused([...PACKAGED, { name: 'assets/fifo', mode: 0o010644 }])).toMatch(/plain/);
	});

	it('refuses a name that climbs, is absolute, or is not plainly written', () => {
		for (const name of ['bundle/../../x', '/etc/x', 'bundle//x', 'bundle/./x', 'assets\\x']) {
			expect(refused([{ name }])).toMatch(/plain relative path|not wrangler/);
		}
	});

	it('refuses two entries for one name rather than letting the second win', async () => {
		const directory = join(mkdtempSync(join(tmpdir(), 'deployer-')), 'artifact');
		const zip = `${directory}.zip`;
		writeFileSync(zip, zipOf([...PACKAGED, { name: 'wrangler.json', data: '{"x":1}' }]));
		await expect(unpack(zip, directory)).rejects.toThrow();
	});

	it('refuses what is not a zip', () => {
		expect(() => entriesOf(Buffer.from('not a zip at all, but long enough to search'))).toThrow(
			Refused,
		);
	});
});
