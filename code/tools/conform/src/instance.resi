/***
 * A second driver started on a test machine from the binary its own driver runs, on bindings, a
 * port, a bridge and a subnet of its own, and everything it made removed after, RFC n0o4l.
 */

/** The transient unit it runs as. */
let unit: string

/** The directory holding its tokens, its state and its secrets, on the machine's tmpfs. */
let directory: string

/** The port it listens on, on the machine's loopback alone. */
let port: int

/** The port its entry listens on, on loopback alone. */
let entryPort: int

/** The first binding it holds, above every id a live binding takes. */
let first: int

/** Its bridge, beside the live driver's. */
let bridge: string

/** The shell printing what the machine holds, the live binding, its mount, routes and ports. */
let facts: string

/** What the machine said of itself. */
type facts = {
  /** The live driver's binding. */
  binding: int,
  /** The mount its btrfs lies on. */
  mount: string,
  /** Every IPv4 route's destination, `default` among them. */
  routes: array<string>,
  /** Every TCP port something listens on. */
  listening: array<int>,
  /** How many btrfs subvolumes the mount holds. */
  subvolumes: int,
}

/** What `facts` printed, or why the machine cannot hold a second driver. */
let readFacts: string => result<facts, string>

/** Whether two IPv4 networks in CIDR notation share an address, a bare address one of its own. */
let overlaps: (string, string) => bool

/** The first subnet of its own that no route of the machine overlaps. */
let subnet: array<string> => option<string>

/**
 * The shell making a token for each of `count` bindings from `first`, starting the driver on them
 * with the live driver's other flags, and printing the tokens in order once it answers.
 */
let started: (~count: int, ~subnet: string) => string

/** The tokens `started` printed, each of its binding in order, or why they are not. */
let readTokens: (string, ~count: int) => result<array<string>, string>

/**
 * The shell stopping the driver and removing all it made, a line `removed` each, and then a line
 * `left` for each still there, the subvolumes counted against `subvolumes`.
 */
let cleaned: (~mount: string, ~subvolumes: int) => string

/** What `cleaned` removed and what it left. */
type cleaned = {removed: array<string>, left: array<string>}

let readCleaned: string => cleaned
