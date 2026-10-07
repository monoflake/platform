import { defineParams } from '@sveltejs/kit/params';

/** The console's marks, as web's `data/record/symlinks.json` registers them under `console`. */
export const MARKS = ['favicon.ico', 'favicon.svg'] as const;

const matchMark = (param: string): param is (typeof MARKS)[number] =>
	(MARKS as readonly string[]).includes(param);

export const params = defineParams({
	mark: (param) => (matchMark(param) ? param : undefined),
});
