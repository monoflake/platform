/***
 * Why a value was not read as its type, envelope*'s one type of its own, and what envelope-generator
 * writes beside it, `model/graph/tools.res`. The model's interface, `docs/code.md`; `src/lib.rs` is
 * the same in Rust.
 *
 * `generated/contracts.res`, the module `Contracts`, holds each type of `model/contracts.json` in
 * ReScript, its JSON and its CBOR as RFC fhg6w's subset writes them, and each interface's
 * operations. A value is written in one JSON and one CBOR, and read back from them alone: a field a
 * reader does not know is passed over, and anything else not as its type writes it is `t`.
 *
 * - **A type** `bucket-kind` is the module `Contracts.BucketKind`, holding `t`, `toJson: t =>
 *   JSON.t`, `fromJson: JSON.t => result<t, Malformed.t>`, `toCbor: t => Codec.Cbor.value`
 *   and `fromCbor: Codec.Cbor.value => result<t, Malformed.t>`. A record is a record, each
 *   field named as the contract names it, a ReScript keyword followed by an underscore under
 *   `@as`, `type_`, and an optional one optional; an enumeration a variant without payloads, each
 *   choice in upper camel case under `@as` its name, `best_effort` as `BestEffort`; a union a
 *   variant under `@tag` its field, each case so named and holding its fields as an inline record;
 *   and a set of names an array of such a variant.
 * - **A shape** is as the subset's table says: `bool`, `string`, `float`, `int` for a signed
 *   32-bit integer, `float` held exact for an unsigned one, for one under 2^53 and for one within
 *   2^53, `Uint8Array.t` for bytes, a hash and a secret, `float` for an id of either half, `array`
 *   for a list and `dict` for a map.
 * - **The shell** of every record, `contracts.json`'s `shell`, is `Contracts.Shell`.
 * - **An interface** `object` is the module `Contracts.Interface.Object`, holding `version`, an
 *   `int`, and for each operation, `write`, a value named in lower camel case, `write`, of
 *   `Contracts.operation`: `{interface: string, version: int, name: string, input: string, output:
 *   string, reasons: array<Contracts.reason>}`, the input and the output by their types' names, a
 *   reason `{name: string, failure: Contracts.Failure.t}`.
 * - **The reasons** every operation may fail for are `Contracts.reasons`, and those a call between
 *   apps adds are `Contracts.calling`, each an `array<Contracts.reason>`.
 * - **By a type's name**, `Contracts.jsonToCbor: (string, JSON.t) => option<result<
 *   Codec.Cbor.value, Malformed.t>>` reads the JSON as that type and gives its CBOR, and
 *   `Contracts.cborToJson` the reverse, each none for a name no type has: the samples of
 *   `tests/codec/` are held by these.
 */

/**
 * A step from a value into what it holds: a record's or a union's field by its name, in JSON and
 * CBOR alike; a list's item by its index; a map's entry by its key.
 */
type step = Field(string) | Index(int) | Key(string)

/**
 * Why a value was not read as its type, which an operation answers as `malformed`, RFC fhg6w:
 * where, by the steps from the value read, and what was expected there -- for bytes, the text,
 * "base64url, unpadded".
 */
type t = {at: array<step>, expected: string}
