# What envelope-generator writes

envelope-generator writes `model/contracts.json` into `envelope*` for each of its languages,
`model/graph/tools.res`. Each type is written in one JSON and one CBOR, as RFC fhg6w's subset has
them, and read back from them alone: a field a reader does not know is passed over, and anything
else not as its type writes it is `Malformed`. The two languages' lists below are one contract.

## Rust

The module `contracts`, included from cargo's `OUT_DIR` as `build.rs` runs the generator.

- **A type** `bucket-kind` is `BucketKind`, implementing `Encoded`: a record a struct, every field
  public and named as the contract names it, a Rust keyword as a raw identifier, `r#type`, and an
  optional one an `Option`; an enumeration an enum without data, each choice named in upper camel
  case, `best_effort` as `BestEffort`; a union an enum, each case so named and holding its fields;
  and a set of names a struct holding the `u32` of its bits, with a constant for each name in upper
  snake case, `Rights::READ`.
- **A shape** is as the subset's table says: `bool`, `String`, `f64`, `i32`, `u32` for an unsigned
  32-bit integer, `Uint53` and `Int53`, `Vec<u8>` for bytes and for a secret, `[u8; 32]` for a hash,
  `u32` for an id of either half, `Vec` for a list and `BTreeMap<String, _>` for a map.
- **The shell** of every record, `contracts.json`'s `shell`, is `Shell`.
- **An interface** `object` is the module `interface::object`, holding `VERSION`, a `u32`, and for
  each operation, `write`, a unit struct named in upper camel case, `Write`, implementing
  `Operation`; and `Call`, an enum with a case for each operation, named as its struct and holding
  its input, `Call::Write(ObjectWrite)`, implementing `Called`, so a call read is held to the type
  its operation names.
- **The reasons** every operation may fail for are `REASONS`, and those a call between apps adds are
  `CALLING`, each a `&[Reason]`, every `Reason` with its message; and `message(name)` gives any
  reason's default message by its name, none for a name no reason has.
- **By a type's name**, `json_to_cbor(name, json)` reads the JSON as that type and gives its CBOR,
  and `cbor_to_json(name, cbor)` the reverse, each none for a name no type has; and **by an
  interface's name**, `call_json_to_cbor(name, json)` reads the JSON as a call of it, an `Envelope`
  of its `Call`, and `call_cbor_to_json(name, cbor)` the reverse: the samples of `tests/codec/` are
  held by these.

## ReScript

`generated/contracts.res`, the module `Contracts`, written by `mise run generate` and never
committed.

- **A type** `bucket-kind` is the module `Contracts.BucketKind`, holding `t`, `toJson: t => JSON.t`,
  `fromJson: JSON.t => result<t, Malformed.t>`, `toCbor: t => Codec.Cbor.value` and `fromCbor:
  Codec.Cbor.value => result<t, Malformed.t>`. A record is a record, each field named as the
  contract names it, a ReScript keyword followed by an underscore under `@as`, `type_`, and an
  optional one optional; an enumeration a variant without payloads, each choice in upper camel case
  under `@as` its name, `best_effort` as `BestEffort`; a union a variant under `@tag` its field,
  each case so named and holding its fields as an inline record; and a set of names an array of such
  a variant.
- **A shape** is as the subset's table says: `bool`, `string`, `float`, `int` for a signed 32-bit
  integer, `float` held exact for an unsigned one, for one under 2^53 and for one within 2^53,
  `Uint8Array.t` for bytes, a hash and a secret, `float` for an id of either half, `array` for a
  list and `dict` for a map.
- **The shell** of every record, `contracts.json`'s `shell`, is `Contracts.Shell`.
- **An interface** `object` is the module `Contracts.Interface.Object`, holding `version`, an `int`,
  and for each operation, `write`, a value named in lower camel case, `write`, of
  `Contracts.operation`: `{interface: string, version: int, name: string, input: string, output:
  string, reasons: array<Contracts.reason>}`, the input and the output by their types' names, a
  reason `{name: string, failure: Contracts.Failure.t}`; and `call`, a variant with a case for each
  operation in upper camel case holding its input, `Write(Contracts.ObjectWrite.t)`, and `envelope`,
  `{call: call, capabilities: array<Uint8Array.t>}`, with `toJson`, `fromJson`, `toCbor` and
  `fromCbor` as a type's.
- **A call**, every operation's body, `contracts.json`'s `call`, fhg6w, is an interface's
  `envelope`: its operation and input, and the capabilities it carries, each a COSE Sign1 as it was
  signed, none written absent. Read, its `interface` is held to the module's, its `operation`
  chooses how its `input` is read, and an operation the interface has not is `t` at `operation`. A
  call a certificate makes is signed whole by its caller, outside this package.
- **The reasons** every operation may fail for are `Contracts.reasons`, and those a call between
  apps adds are `Contracts.calling`, each an `array<Contracts.reason>`, a reason `{name: string,
  failure: Contracts.Failure.t, message: string}`, its message its default; and
  `Contracts.messages`, a `dict<string>`, gives any reason's default message by its name, RFC ge55b.
- **An answer**, every operation's, `contracts.json`'s `answer`, ge55b, is `Contracts.Answer`,
  holding `type t<'output> = Success('output) | Error(Contracts.Error.t)`, told apart by `status`
  alone, with `toJson: (t<'o>, 'o => JSON.t) => JSON.t`, `fromJson: (JSON.t, JSON.t => result<'o,
  Malformed.t>) => result<t<'o>, Malformed.t>`, and `toCbor` and `fromCbor` the same over
  `Codec.Cbor.value`; a `status` neither case names is `t` at `status`.
- **By a type's name**, `Contracts.jsonToCbor: (string, JSON.t) => option<result< Codec.Cbor.value,
  Malformed.t>>` reads the JSON as that type and gives its CBOR, and `Contracts.cborToJson` the
  reverse, each none for a name no type has; and **by an interface's name**,
  `Contracts.callJsonToCbor` and `Contracts.callCborToJson` read and write a call of it, its
  `envelope`: the samples of `tests/codec/` are held by these.
