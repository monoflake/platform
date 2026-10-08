/**
 * The platform's addresses, and the whole map as everything above infra reads it: the platform's
 * own declared here, the author's from `canmi` and infra's from `@monoflake/urls`, composed into
 * one shape so a caller asks one place and the Rust mirror has one source. See
 * the workspace's spec/architecture/layers.md, "Addresses are split by who owns the name".
 */
import {
	CONTACT,
	EXTERNAL,
	GITHUB_OWNER,
	SITE,
	SITE_PORT,
	SOURCE,
	isDevHost,
	LOOPBACK_HOST,
	loopbackUrl,
	normalizedLocation,
	normalizePath,
	type Normalized,
} from '@canmi/me/urls';
import { INFRA, PANEL_PORT } from '@monoflake/urls';

/**
 * The repositories whose deploy runs the hook passes on, as GitHub names them: the two whose apps
 * a node runs, web, whose Workers the deployer deploys, and cue, whose one app, `qq`, runs on sha.
 * Each receiver holds its own list too, and that one decides. See infra's
 * spec/architecture/host.md, "The machine pulls; nothing pushes into it", and
 * spec/architecture/deployer.md, "Admitting a repository".
 */
export const DEPLOY_SOURCES: readonly string[] = [
	'monoflake/infra',
	'monoflake/platform',
	'canmi21/web',
	'canmi21/cue',
];

/**
 * The repository the platform's own hosts are built from, which their robots.txt and security.txt
 * send an agent to. See the workspace's spec/robots.md.
 */
export const PLATFORM_SOURCE = 'https://github.com/monoflake/platform';

export {
	GITHUB_OWNER,
	isDevHost,
	LOOPBACK_HOST,
	loopbackUrl,
	normalizedLocation,
	normalizePath,
	type Normalized,
};

/**
 * The ports each app answers on in development.
 *
 * Pinned, and bound by exactly one checkout at a time. The gaps are the inspector ports, which
 * wrangler takes as port + 1, and they keep clear of LOCAL_PORT (mise.toml). A second copy of an
 * app collides here rather than drifting to a free port, which is the cheapest mutex there is.
 * See web's spec/toolchain.md.
 */
export const PINNED_PORTS = {
	site: SITE_PORT,
	api: 26512,
	alias: 26514,
	cdn: 26516,
	panel: PANEL_PORT,
} as const;

/** Workers reached by binding alone: a port that is the mutex, and no address. */
export const BOUND_PORTS = {
	quota: 26523,
} as const;

/** The ports this checkout's servers bind: the pinned ones and the bound ones together. */
export const DEVELOPMENT_PORTS: {
	readonly [App in keyof typeof PINNED_PORTS | keyof typeof BOUND_PORTS]: number;
} = { ...PINNED_PORTS, ...BOUND_PORTS };

export type AppName = keyof typeof PINNED_PORTS;

export type DevelopmentUrls = Readonly<Record<AppName | 'symlink', string>>;

/** The site's scope of the API host, which is the service's name, `site`. */
const SITE_SCOPE = 'site';

/**
 * Where the alias layer and the CDN are reached *from a page* in development: through the site.
 *
 * A page carries no host of its own for either prefix -- see web's spec/toolchain.md, "They bind
 * every interface, and the other two are reached through the site", for why that is what
 * makes the site work from a phone on the same network. The site's API needs no proxy: the
 * site's Worker answers it under `/api/` itself.
 */
export const DEVELOPMENT_PROXY_PATHS = {
	alias: '/alias',
	symlink: '/symlink',
	cdn: '/cdn',
} as const;

export function developmentUrl(app: AppName): string {
	return `http://localhost:${DEVELOPMENT_PORTS[app]}`;
}

/**
 * Every app's address in development. The service layer is reached through the development gateway,
 * as it is in production, so its CORS and its lifetimes hold here too; the gateway has no short
 * hosts here, so each is a service of the API host, at the version its short host pins. See
 * spec/architecture/gateway.md and spec/architecture/services.md, "Development goes through the
 * gateway too".
 */
export function developmentUrls(): DevelopmentUrls {
	const gateway = developmentUrl('api');
	return {
		site: developmentUrl('site'),
		api: `${gateway}/v1/${SITE_SCOPE}`,
		alias: `${gateway}/v1/aka`,
		symlink: `${gateway}/v1/aka/symlink`,
		cdn: `${gateway}/v3/cdn`,
		panel: developmentUrl('panel'),
	};
}

const development: DevelopmentUrls = developmentUrls();

/**
 * The API host's two sides: private, where every container asks its own node's Caddy over plain
 * HTTP, and public, past the gateway. See spec/architecture/gateway.md, "Inside a node, its own
 * services answer locally".
 */
const API = {
	private: 'http://api.internal.ixc.one',
	public: 'https://api.monoflake.com',
} as const;

/**
 * The domains owned here, which the production map below reads rather than spelling twice.
 * `alias` is the alias layer's. `app` is the suffix every
 * interface is on behind Access, see spec/architecture/services.md; `panel`, `keeper` and `host`
 * are infra's, see infra's spec/architecture/host.md; `ledger` is where every service records its
 * tasks, see ledger.md; `shot` is the public scope a capture's pictures are named under, see
 * shot.md.
 */
const INTERNAL = {
	app: 'https://canmi.app',
	alias: 'https://ill.li',
	...INFRA,
	ledger: `${API.private}/ledger`,
	shot: `${API.public}/v1/shot`,
	api: API,
	// The status page's two names: the one address, and Vercel's own name for it, reached while
	// Cloudflare's DNS is not. See web's spec/architecture/status.md, "The page: one app, served by
	// Vercel".
	status: { canonical: 'https://status.canmi.app', mirror: 'https://canmi.vercel.app' },
	// The console, every node at once, and the live socket it hands to the nearest node's relay.
	// See web's spec/architecture/console.md.
	console: 'https://console.canmi.app',
} as const;

export const URLS = {
	apps: {
		development,
		production: {
			site: SITE,
			// The site's public scope of the API host, which the alias layer reads; see
			// spec/architecture/services.md, "The site's API runs in the site's Worker".
			api: `${API.public}/v1/${SITE_SCOPE}`,
			// An apex of its own rather than a label under `infra`, because here the address is
			// the product: a resolved name is read aloud and typed, and `ill.li/k7m2x` is short
			// enough to be either. See spec/architecture/delivery.md.
			alias: INTERNAL.alias,
			// Where a scope's fixed names are followed: the alias layer's own host for them. See
			// spec/architecture/gateway.md, "Every request is one address".
			symlink: 'https://symlink.si',
			cdn: 'https://cdn.monoflake.com',
			// The panel, host's interface, an app of its own; see infra's spec/architecture/host.md.
			panel: INTERNAL.panel,
		},
	},
	source: SOURCE,
	// The apexes, declared once above so the one a worker answers on cannot be spelled twice.
	internal: INTERNAL,
	contact: CONTACT,
	external: {
		...EXTERNAL,
		// DNS over HTTPS, asked by address so that asking needs no DNS of its own; both answer for
		// every name `shot` captures, and the addresses both give must be public. The certificates
		// for both name the addresses. See spec/architecture/shot.md, "Only public addresses".
		doh: {
			cloudflare: 'https://1.1.1.1/dns-query',
			google: 'https://8.8.8.8/resolve',
		},
		// Cloudflare's API, pinned for the wrangler the deployer runs so a file it reads cannot point
		// it elsewhere. See spec/architecture/deployer.md, "Credentials".
		cloudflare: { api: 'https://api.cloudflare.com/client/v4' },
		// Whose GeoLite2 is, which `geo` credits in every answer. The files themselves are fetched by
		// geo's Dockerfile; see spec/architecture/geo.md, "GeoLite2 is fetched as the image is built".
		geolite: {
			maxmind: 'https://www.maxmind.com',
		},
	},
} as const;

/**
 * The service layer's hostnames, every one bound to the gateway, and the codes a deployment's own
 * hostname is spelled from: `{service}-{region}-{provider}` under `deployments`. A provider is its
 * code and the name a person is shown; it or a region is added here before anything is placed on
 * it. See spec/architecture/gateway.md, "Providers are short codes, registered here".
 */
export const GATEWAY = {
	// Each answers the same, the first the one published and the rest a way round a domain that
	// fails. See spec/architecture/gateway.md, "A second domain answers the same".
	domains: ['monoflake.com', 'monoflake.net'],
	api: 'api.monoflake.com',
	cdn: 'cdn.monoflake.com',
	deployments: 'ixc.one',
	alias: 'ill.li',
	symlink: 'symlink.si',
	// Proxied, never redirected, while the live corpus still names it. See spec/issues/gateway.md,
	// "cdn.ffoni.com is bound back until the corpus stops naming it".
	retired: { cdn: 'cdn.ffoni.com' },
	providers: {
		int: 'Self-hosted',
		cf: 'Cloudflare',
		vcl: 'Vercel',
		oci: 'Oracle',
		az: 'Azure',
		rkn: 'RackNerd',
	},
	regions: { rdu: 'the machine at home, by Raleigh-Durham', glo: 'everywhere, as a Worker runs' },
} as const;

/**
 * Where each consumer's pages are served, by its service code: what a declaration's `cors.origins`
 * names, so no `service.toml` spells an origin. The status page has two, both Vercel's. See
 * spec/architecture/gateway.md, "A route names who may call it by service code".
 */
export const PAGE_ORIGINS: Readonly<Record<string, readonly string[]>> = {
	site: [URLS.apps.production.site],
	status: [INTERNAL.status.canonical, INTERNAL.status.mirror],
};

export type UrlEnvironment = keyof typeof URLS.apps;
export type UrlMap = (typeof URLS.apps)[UrlEnvironment];

export function pickUrls(isDev: boolean): UrlMap {
	return isDev ? URLS.apps.development : URLS.apps.production;
}

/**
 * The same map as `pickUrls`, as a page served by the site should ask for it.
 *
 * Two functions because two consumers want opposite things from the development entry: a
 * worker wants origins it can put in a CORS list or a redirect, while a page wants paths, since
 * the host it should ask is whichever one it was opened from and need not be `localhost`.
 * Identical to `pickUrls` in production, where nothing is proxied.
 */
export function pageUrls(isDev: boolean): UrlMap {
	return isDev ? { ...URLS.apps.development, ...DEVELOPMENT_PROXY_PATHS } : URLS.apps.production;
}
