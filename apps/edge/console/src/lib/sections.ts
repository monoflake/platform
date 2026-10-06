/** The console's five sections, in the sidebar's order: where each lives and what it is called. */
import Boxes from '@lucide/svelte/icons/boxes';
import LayoutDashboard from '@lucide/svelte/icons/layout-dashboard';
import Rocket from '@lucide/svelte/icons/rocket';
import ScrollText from '@lucide/svelte/icons/scroll-text';
import Server from '@lucide/svelte/icons/server';

export const SECTIONS = [
	{ href: '/', label: 'Overview', icon: LayoutDashboard },
	{ href: '/nodes', label: 'Nodes', icon: Server },
	{ href: '/deployments', label: 'Deployments', icon: Rocket },
	{ href: '/apps', label: 'Apps', icon: Boxes },
	{ href: '/events', label: 'Events', icon: ScrollText },
] as const;

export type Section = (typeof SECTIONS)[number];

/** The section `path` is in, the Overview only at `/` itself. */
export function sectionOf(path: string): Section | undefined {
	return SECTIONS.find(({ href }) =>
		href === '/' ? path === '/' : path === href || path.startsWith(`${href}/`),
	);
}
