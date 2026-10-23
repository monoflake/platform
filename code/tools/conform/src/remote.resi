/***
 * A test machine as ssh reaches it, as deploy reaches it, and a port of its loopback forwarded to
 * one of this machine's.
 */

/** A target as ssh reaches it, its address and the options every connection takes. */
type target = {host: string, options: array<string>}

/**
 * A target by the name ssh takes, `local` being monoflake/machine's local machine on port 2222 of
 * localhost, its host key unchecked as it is made in its container.
 */
let target: string => target

/** ssh's arguments holding a port of the machine's loopback open at one of localhost's. */
let forward: (target, ~local: int, ~remote: int) => array<string>
