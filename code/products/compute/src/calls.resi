/***
 * A call's id and its record in compute's own `records` database, RFC 49qyg. The id is 16
 * lowercase hex: its high 48 bits the milliseconds it was issued at, its low 16 a sequence within
 * that millisecond, issued by compute alone. The model's interface, `docs/code.md`.
 */

/** The `database` contract's execute over its JSON, `database-execute` in, its answer out. */
type execute = JSON.t => promise<JSON.t>

/** What issues ids in one Worker, the last one it issued held. */
type issuer

let issuer: unit => issuer

/**
 * The next id at `now` in milliseconds: a later millisecond than the last starts its sequence at
 * 0; the same or an earlier one keeps the last id's milliseconds and takes the next sequence, so
 * ids only rise; none where the sequence would pass 65535.
 */
let issued: (issuer, ~now: float) => option<string>

/** The milliseconds an id carries, none for text that is no id. */
let issuedAt: string => option<float>

/** A call as its record holds it, `call` in model/contracts/records/compute.res. */
type record = {id: string, app: float, function: string, expires: float, outcome: option<string>}

/** The `calls` table made where it is absent. */
let made: (~execute: execute) => promise<result<unit, string>>

/** A call recorded as its id is issued, its outcome none yet. */
let recorded: (~execute: execute, record) => promise<result<unit, string>>

/** The outcome told, written to the call's record. */
let told: (~execute: execute, ~id: string, ~outcome: string) => promise<result<unit, string>>

/** A call's record by its id, none where none is. */
let found: (~execute: execute, ~id: string) => promise<result<option<record>, string>>
