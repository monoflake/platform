/**
 * Zips for the tests, written as GitHub serves an artifact, and what the packaging puts in one.
 * Read by tests alone; nothing the deployer runs imports it.
 */
import { crc32, deflateRawSync } from 'node:zlib';

export interface Item {
	readonly name: string;
	readonly data?: string;
	/** A Unix mode, file type included; a regular file's when absent. */
	readonly mode?: number;
}

/** A zip as GitHub serves one: deflated entries made on Unix, then the central directory. */
export function zipOf(items: readonly Item[]): Buffer {
	const locals: Buffer[] = [];
	const centrals: Buffer[] = [];
	let offset = 0;
	for (const item of items) {
		const name = Buffer.from(item.name);
		const data = Buffer.from(item.data ?? '');
		const packed = deflateRawSync(data);
		const local = Buffer.alloc(30);
		local.writeUInt32LE(0x04034b50, 0);
		local.writeUInt16LE(20, 4);
		local.writeUInt16LE(8, 8);
		local.writeUInt32LE(crc32(data), 14);
		local.writeUInt32LE(packed.length, 18);
		local.writeUInt32LE(data.length, 22);
		local.writeUInt16LE(name.length, 26);
		const central = Buffer.alloc(46);
		central.writeUInt32LE(0x02014b50, 0);
		central.writeUInt16LE((3 << 8) | 20, 4);
		central.writeUInt16LE(20, 6);
		central.writeUInt16LE(8, 10);
		central.writeUInt32LE(crc32(data), 16);
		central.writeUInt32LE(packed.length, 20);
		central.writeUInt32LE(data.length, 24);
		central.writeUInt16LE(name.length, 28);
		const mode = item.mode ?? (item.name.endsWith('/') ? 0o040755 : 0o100644);
		central.writeUInt32LE((mode << 16) >>> 0, 38);
		central.writeUInt32LE(offset, 42);
		locals.push(local, name, packed);
		centrals.push(central, name);
		offset += local.length + name.length + packed.length;
	}
	const directory = Buffer.concat(centrals);
	const end = Buffer.alloc(22);
	end.writeUInt32LE(0x06054b50, 0);
	end.writeUInt16LE(items.length, 8);
	end.writeUInt16LE(items.length, 10);
	end.writeUInt32LE(directory.length, 12);
	end.writeUInt32LE(offset, 16);
	return Buffer.concat([...locals, directory, end]);
}

/** What `.mise/tasks/worker` packages for the console. */
export const PACKAGED: readonly Item[] = [
	{ name: 'wrangler.json', data: '{}' },
	{ name: 'service.toml', data: 'name = "console"' },
	{ name: 'bundle/' },
	{ name: 'bundle/_worker.js', data: 'export default {}' },
	{ name: 'assets/.assetsignore', data: '_worker.js' },
	{ name: 'assets/.well-known/security.txt', data: 'Contact: x' },
	{ name: 'assets/_app/start.js', data: 'start' },
];
