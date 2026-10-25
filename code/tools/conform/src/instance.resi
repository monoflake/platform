/***
 * A second driver started on a test machine from the binary its own driver runs, on bindings, a
 * port, a bridge and a subnet of its own, and everything it made removed after, RFC n0o4l.
 */

/** The transient unit it runs as. */
let unit: string

/** The directory holding its tokens, its state and its secrets, on the machine's tmpfs. */
let directory: string

/** The file naming each binding a run opened, written before the first and kept by a reboot. */
let recorded: string

/** Where its driver roots each container's runtime, where the live driver roots its own. */
let roots: string

/** The port it listens on, on the machine's loopback alone. */
let port: int

/** The port it names as its entry's, one of its own beside the live entry's, as `port` is. */
let entry: int

/** The first of the bindings it holds, counted up from it, none of which is the live binding. */
let first: int

/** Its bridge, beside the live driver's. */
let bridge: string

/**
 * The shell printing what the machine holds, the live binding, its mount, routes and ports, and the
 * live driver's artifact directory, its artifact bound and the machine's architecture.
 */
let facts: string

/** What the machine said of itself. */
type facts = {
  /** The live driver's binding. */
  binding: float,
  /** The mount its btrfs lies on. */
  mount: string,
  /** Every IPv4 route's destination, `default` among them. */
  routes: array<string>,
  /** Every TCP port something listens on. */
  listening: array<int>,
  /** How many btrfs subvolumes the mount holds. */
  subvolumes: int,
  /** The directory a `file:` artifact may be fetched from, the live driver's `--local`. */
  local: option<string>,
  /** The most an artifact may be, the live driver's `--largest`. */
  largest: option<float>,
  /** The machine's architecture as OCI names it. */
  architecture: option<string>,
}

/**
 * What `facts` printed, or why the machine cannot hold a second driver, its live binding among the
 * `count` it would hold from `first` among the reasons.
 */
let readFacts: (string, ~count: int) => result<facts, string>

/** The directory under the live driver's `--local` the run's fixtures are copied into. */
let served: string => string

/** A file padded where the fixtures are served, its name, the file it is made of and its size. */
type padded = {file: string, from: string, size: float}

/** What the runner's fixtures build names, the files it wrote and those padded once copied. */
type fixtures = {files: array<string>, padded: array<padded>}

/** What the build's manifest names to copy and to pad, or why it names nothing. */
let readFixtures: string => result<fixtures, string>

/** The shell making the served directory afresh and empty. */
let emptied: string => string

/** The shell writing what stdin holds to a file of the served directory. */
let copied: (~directory: string, ~file: string) => string

/** The shell making each padded file in the served directory, another's bytes and then zeros. */
let made: (~directory: string, array<padded>) => string

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
 * The shell stopping the driver and removing all it made, the served directory among it, a line
 * `removed` each, and then a line `left` for each still there, the subvolumes counted against
 * `subvolumes`; only the bindings `recorded` names are the run's, in either form of their name.
 */
let cleaned: (~mount: string, ~subvolumes: int, ~served: option<string>) => string

/** What `cleaned` removed and what it left. */
type cleaned = {removed: array<string>, left: array<string>}

let readCleaned: string => cleaned
