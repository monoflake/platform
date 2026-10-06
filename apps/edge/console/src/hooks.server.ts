import { fillTheme } from '@canmi/kit/theme';
import type { Handle } from '@sveltejs/kit/hooks';

/**
 * The script alone, never the class: every page is prerendered once for every reader. See lib's
 * spec/kit/theme.md, "One cookie, read the same way everywhere".
 */
export const handle: Handle = ({ event, resolve }) =>
	resolve(event, { transformPageChunk: ({ html }) => fillTheme(html) });
