/***
 * A test machine as ssh reaches it, the driver's own flags read there, a call made with the
 * binding's token read on the machine and never sent off it, and the entry asked.
 */

/** A target as ssh reaches it, its address and the options every connection takes. */
type target = {host: string, options: array<string>}

/**
 * A target by the name ssh takes, `local` being monoflake/machine's local machine on port 2222 of
 * localhost, its host key unchecked as it is made in its container.
 */
let target: string => target

/** Whether the target is the local machine, its entry on port 8080 of localhost. */
let isLocal: string => bool

/** driver-machine's port on the machine, as driver's `dev` asks it. */
let port: int

/** The shell printing the driver's `--local` directory, the binding's id and any tunnel address. */
let facts: string

/** What the machine said of itself. */
type facts = {directory: string, binding: string, tunnel: option<string>}

/** What `facts` printed, or why it says too little. */
let readFacts: string => result<facts, string>

/**
 * The shell making the call an envelope writes, to the path its interface and operation name, the
 * envelope itself read from stdin.
 */
let call: JSON.t => string

/** The shell asking the entry for `/` by a host, printing its answer. */
let asked: string => string

/** Why a call answered no output, its reason and message, `unread` where its body was none. */
type refused = {reason: string, message: string}

/** A call's answer read as its output's type. */
let answer: (string, JSON.t => result<'output, Envelope.Malformed.t>) => result<'output, refused>
