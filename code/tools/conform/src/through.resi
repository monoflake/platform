/***
 * The path hello is asked through from here, the machine's tunnel, or a gateway's mount where one
 * is named, RFC oomwh. The driver and the entry are asked over ssh either way.
 */

/** A path by the name a report gives it, and the address asked. */
type t = {name: string, address: string}

/** `--gateway <origin>` taken out of the arguments, the origin and what is left, or why not. */
let flagged: array<string> => result<(option<string>, array<string>), string>

/** The scope hello mounts itself under, its `metadata.json`'s in monoflake/cloud. */
let scope: string

/** Hello's address on a gateway, `<origin>/v1/hello/`. */
let gateway: (~origin: string) => string

/**
 * Hello's mount on the gateway at the origin `--gateway` gives, or else the tunnel the machine
 * printed, none where it printed none.
 */
let chosen: (~gateway: option<string>, ~tunnel: result<string, string>) => option<t>
