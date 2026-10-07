import { rustConstants } from '@canmi/me/rust';
import { URLS } from './index.ts';

/**
 * The Rust mirror of the URL map.
 *
 * Rust cannot import this library, so every Rust program reads the generated `src/lib.rs`, the
 * `monoflake` crate, committed so a checkout compiles without Node having run. `mise run urls`
 * rewrites it and `rust.test.ts` fails when it no longer matches this render, so the two languages
 * cannot drift past `mise run verify`. See web's spec/architecture/workspace.md.
 */
export function rustUrlMap(): string {
	const constants = rustConstants(URLS);
	return [
		'//! @generated from libs/sdk/src/index.ts by `mise run urls`; do not edit.',
		"//! One URL map for both languages -- see web's spec/architecture/workspace.md.",
		'',
		constants,
		'',
	].join('\n');
}
