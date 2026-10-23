/***
 * The path hello is asked through from here, the machine's tunnel, or a control's gateway where
 * one is named, RFC rxmd9. The driver and the entry are asked over ssh either way.
 */

/** A path by the name a report gives it, and the address asked. */
type t = {name: string, address: string}

/** `--control <origin>` taken out of the arguments, the origin and what is left, or why not. */
let control: array<string> => result<(option<string>, array<string>), string>

/** The gateway's address of an app, `<origin>/v1/app-<id>/`. */
let gateway: (~origin: string, ~app: int) => string

/**
 * The gateway where a control is named, or else the tunnel the machine printed, none where it
 * printed none.
 */
let chosen: (~control: option<string>, ~tunnel: result<string, string>, ~app: int) => option<t>
