/**
 * An artifact opened and held to the shape `.mise/tasks/worker` writes, before a byte of it reaches
 * the disk: `wrangler.json`, `service.toml`, `bundle/` and `assets/`, plain files and directories
 * alone. Read here rather than by `unzip`, so no link and no name GitHub served is ever trusted to
 * an extractor. See spec/architecture/deployer.md, "What it refuses".
 */
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { crc32, inflateRawSync } from 'node:zlib';
import { Refused } from './github.ts';

/** One file or directory the zip names, located but not yet read. */
export interface Entry {
	readonly name: string;
	readonly directory: boolean;
	readonly method: number;
	readonly crc: number;
	readonly packed: number;
	readonly size: number;
	readonly offset: number;
}

/** More than every Worker here together; the most an artifact may unpack to. */
const MOST_BYTES = 512 * 1024 * 1024;
const FILES = new Set(['wrangler.json', 'service.toml']);
const TREES = new Set(['bundle', 'assets']);
/** What wrangler reads into its own environment, refused even among the assets. */
const ENVIRONMENT = /^(?:\.env(?:\..*)?|\.dev\.vars(?:\..*)?)$/;

/**
 * Why the artifact may not hold `name`, or nothing: a name outside the four, a dotfile outside the
 * assets, an environment file anywhere, or a path that is not plainly relative.
 */
export function refusalOf(name: string, directory: boolean): string | undefined {
	const parts = name.replace(/\/$/, '').split('/');
	if (name.includes('\\') || name.includes('\0') || parts.some((part) => /^\.{0,2}$/.test(part))) {
		return `${JSON.stringify(name)} is not a plain relative path`;
	}
	const [top = ''] = parts;
	if (parts.length === 1 && FILES.has(top)) {
		return directory ? `${top} is a directory` : undefined;
	}
	if (!TREES.has(top)) return `${name} is not wrangler.json, service.toml, bundle/ or assets/`;
	if (parts.length === 1 && !directory) return `${top} is a file`;
	if (parts.some((part) => ENVIRONMENT.test(part))) return `${name} is an environment file`;
	if (top !== 'assets' && parts.some((part) => part.startsWith('.'))) {
		return `${name} is a dotfile outside assets/`;
	}
	return undefined;
}

function refuse(why: string): never {
	throw new Refused(`the artifact ${why}`);
}

/** Every entry of the zip in `bytes`, refused when it is not one this deployer reads. */
export function entriesOf(bytes: Buffer): Entry[] {
	// The end record, within the 64 KiB its comment may take.
	let end = -1;
	for (let at = bytes.length - 22; at >= Math.max(0, bytes.length - 22 - 0xffff); at -= 1) {
		if (bytes.readUInt32LE(at) === 0x06054b50) {
			end = at;
			break;
		}
	}
	if (end < 0) refuse('is not a zip');
	const count = bytes.readUInt16LE(end + 10);
	let at = bytes.readUInt32LE(end + 16);
	if (count === 0xffff || at === 0xffffffff) refuse('is a ZIP64, which no Worker needs');

	const entries: Entry[] = [];
	let total = 0;
	for (let index = 0; index < count; index += 1) {
		if (at + 46 > bytes.length || bytes.readUInt32LE(at) !== 0x02014b50) refuse('is malformed');
		const made = bytes.readUInt16LE(at + 4) >> 8;
		const flags = bytes.readUInt16LE(at + 8);
		const length = bytes.readUInt16LE(at + 28);
		const extra = bytes.readUInt16LE(at + 30);
		const comment = bytes.readUInt16LE(at + 32);
		const mode = bytes.readUInt32LE(at + 38) >>> 16;
		const name = bytes.toString('utf8', at + 46, at + 46 + length);
		const entry: Entry = {
			name,
			directory: name.endsWith('/'),
			method: bytes.readUInt16LE(at + 10),
			crc: bytes.readUInt32LE(at + 16),
			packed: bytes.readUInt32LE(at + 20),
			size: bytes.readUInt32LE(at + 24),
			offset: bytes.readUInt32LE(at + 42),
		};
		at += 46 + length + extra + comment;

		if (flags & 1) refuse(`holds ${name} encrypted`);
		// Made on Unix, the mode says what it is: a link or a device is refused outright.
		const kind = mode & 0o170000;
		if (made === 3 && kind !== 0 && kind !== 0o100000 && kind !== 0o040000) {
			refuse(`holds ${name}, which is not a plain file or directory`);
		}
		if (entry.method !== 0 && entry.method !== 8)
			refuse(`holds ${name} packed a way it cannot read`);
		const why = refusalOf(name, entry.directory);
		if (why) refuse(`holds what it may not: ${why}`);
		total += entry.size;
		if (total > MOST_BYTES) refuse('unpacks to more than any Worker needs');
		entries.push(entry);
	}
	return entries;
}

/** One entry's bytes, held to the size and checksum the zip recorded. */
export function contentOf(bytes: Buffer, entry: Entry): Buffer {
	const local = entry.offset;
	if (bytes.readUInt32LE(local) !== 0x04034b50) throw new Refused(`${entry.name} is malformed`);
	const start = local + 30 + bytes.readUInt16LE(local + 26) + bytes.readUInt16LE(local + 28);
	const packed = bytes.subarray(start, start + entry.packed);
	const content =
		entry.method === 0 ? packed : inflateRawSync(packed, { maxOutputLength: entry.size || 1 });
	if (content.length !== entry.size || crc32(content) !== entry.crc) {
		throw new Refused(`${entry.name} is not what the zip recorded`);
	}
	return content;
}

/**
 * The zip at `zip` out into `directory`, once every entry has been admitted. Each file is created
 * new, so two entries for one name fail rather than the second replacing the first.
 */
export async function unpack(zip: string, directory: string): Promise<void> {
	const bytes = await readFile(zip);
	const entries = entriesOf(bytes);
	await mkdir(directory, { recursive: true });
	for (const entry of entries) {
		const path = join(directory, entry.name);
		// oxlint-disable-next-line no-await-in-loop -- one file at a time keeps one in memory
		await mkdir(entry.directory ? path : dirname(path), { recursive: true });
		// oxlint-disable-next-line no-await-in-loop -- as above
		if (!entry.directory) await writeFile(path, contentOf(bytes, entry), { flag: 'wx' });
	}
}
