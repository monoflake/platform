/***
 * A Worker's bundle as the machine's function kind takes it, a tar archive of its modules beside
 * `metadata.json`, RFC dg903, made from what `wrangler deploy --dry-run --outdir` writes.
 */
module Contracts = Envelope.Contracts

/** What the bundle takes of the app's wrangler configuration. */
type config = {main: string, compatibilityDate: string, compatibilityFlags: array<string>}

/** JSONC as wrangler reads it, its comments and trailing commas dropped outside strings. */
let uncommented: string => string

/** The app's `wrangler.json` or `wrangler.jsonc` read, or why it is refused. */
let config: string => result<config, string>

/**
 * The kinds the app's own `metadata.json` declares in the order its code prefers, RFC emgxf, or why
 * the declaration is refused, the reason written to follow the file's path.
 */
let declared: string => result<array<Contracts.DeploymentKind.t>, string>

/** The module wrangler writes for `main`, its file's name ending `.js`. */
let mainModule: config => string

/** Whether a file wrangler writes is one of the bundle's modules, its note and maps passed over. */
let isModule: string => bool

/**
 * The metadata naming the main module, the compatibility date, any flags and any kinds declared,
 * as JSON.
 */
let metadata: (~kinds: array<Contracts.DeploymentKind.t>=?, config) => string

type file = {name: string, bytes: Uint8Array.t}

/**
 * A ustar archive of the files in the order given, each a regular file of mode 644 at time 0, so
 * the same files make the same bytes; a name past 100 bytes is refused.
 */
let tar: array<file> => result<Uint8Array.t, string>

/** The bundle of the modules wrangler wrote, its metadata first and the rest by name. */
let packed: (
  ~kinds: array<Contracts.DeploymentKind.t>=?,
  config,
  array<file>,
) => result<Uint8Array.t, string>
