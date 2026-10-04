import { noteProblems } from '@canmi/me/robots';
import { PLATFORM_SOURCE } from '@monoflake/sdk';
import { expect, it } from 'vitest';
import { everyNote, noteFor } from './notes.ts';

it('says one thing six ways, no two the same', () => {
	const notes = everyNote().map((lines) => lines.join(' '));
	expect(notes).toHaveLength(6);
	expect(new Set(notes).size).toBe(notes.length);
});

it('keeps every note to the layout', () => {
	for (const lines of everyNote()) expect(noteProblems(lines)).toEqual([]);
});

it("sends an agent to the platform's own repository", () => {
	expect(noteFor('robots', 'cdn').source).toBe(PLATFORM_SOURCE);
});
