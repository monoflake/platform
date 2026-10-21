/***
 * What `model/contracts.json` holds that the ReScript is written from, and `Unread`, as `model.rs`
 * is in Rust.
 */
type unread = {at: string, expected: string}

exception Unread(unread)

type prim = Bool | String | Float64 | Int32 | Uint32 | Int53 | Uint53 | Bytes | Hash | Secret

type rec shape =
  | Prim(prim)
  /** An id of either half, its kind's name read and no more, since on the wire it is an integer. */
  | Id
  | Type(string)
  | List(shape)
  | Map(shape)

type field = {name: string, key: int, shape: shape, optional: bool}
type choice = {name: string, code: int}
type case = {name: string, code: int, fields: array<field>}

type def =
  | Record(array<field>)
  | Enum(array<choice>)
  | Union({tag: string, cases: array<case>})
  | Flags(array<choice>)

type reason = {name: string, failure: string}
type operation = {name: string, input: string, output: string, reasons: array<reason>}
type interface_ = {name: string, version: int, operations: array<operation>}

/**
 * An answer by `tag`, `success` holding the output as `data` and `error` the fields of the type
 * `error` names.
 */
type answer = {tag: string, success: (int, string, int), error: (int, string)}

/** A call's field, a shape of the subset's or the input of the operation another field names. */
type callShape = Shape(shape) | Input(string)
type callField = {name: string, key: int, shape: callShape, optional: bool}

type contracts = {
  shell: array<field>,
  call: array<callField>,
  types: array<(string, def)>,
  reasons: array<reason>,
  calling: array<reason>,
  interfaces: array<interface_>,
  answer: answer,
  messages: array<(string, string)>,
}

let fail = (at, expected) => throw(Unread({at: at->Array.join("/"), expected}))

let caught = make =>
  try Ok(make()) catch {
  | Unread(unread) => Error(unread)
  }
