/***
 * What `Contracts` is written with, each shape's JSON and CBOR, RFC fhg6w. A reader throws
 * `Unread`, which `fromJson` and `fromCbor` catch as `Malformed.t`.
 */
module Cbor = Codec.Cbor

exception Unread(Malformed.t)

/** Not as its type writes it here, with what was expected. */
let fail = expected => throw(Unread({at: [], expected}))

/** A reading within a step from the value read, the step leading where it was refused. */
let within = (step: Malformed.step, read) =>
  try read() catch {
  | Unread({at, expected}) => throw(Unread({at: [step, ...at], expected}))
  }

/** A reading, its refusal caught. */
let reading = read =>
  try Ok(read()) catch {
  | Unread(malformed) => Error(malformed)
  }

/** A type's own reading, within another's. */
let unwrap = result =>
  switch result {
  | Ok(value) => value
  | Error(malformed) => throw(Unread(malformed))
  }

let jsonToCbor = (json, fromJson, toCbor) => fromJson(json)->Result.map(toCbor)
let cborToJson = (cbor, fromCbor, toJson) => fromCbor(cbor)->Result.map(toJson)

/** An integer's bounds, held exact in a float, and what is expected outside them. */
type bounds = {low: float, high: float, text: string}

let int32Bounds = {low: -2147483648., high: 2147483647., text: "an integer of -2^31 to 2^31 - 1"}
let uint32Bounds = {low: 0., high: 4294967295., text: "an integer of 0 to 2^32 - 1"}
let uint53Bounds = {low: 0., high: 9007199254740991., text: "an integer of 0 to 2^53 - 1"}
let int53Bounds = {
  low: -9007199254740991.,
  high: 9007199254740991.,
  text: "an integer of -(2^53 - 1) to 2^53 - 1",
}

let isWithin = (n, bounds) =>
  Float.isFinite(n) && Math.floor(n) == n && n >= bounds.low && n <= bounds.high

let oneOf = names => `one of ${names->Array.join(", ")}`

/** A list written absent when empty, as a call's capabilities are. */
let nonEmpty = items => items->Array.length > 0 ? Some(items) : None
let orEmpty = items => items->Option.getOr([])

/** A name no case or operation has, at the field naming it. */
let unknownName = (tag, names) => within(Malformed.Field(tag), () => fail(oneOf(names)))

module ToJson = {
  let bool = value => JSON.Boolean(value)
  let string = value => JSON.String(value)
  let float = value => JSON.Number(value)
  let int = value => JSON.Number(Int.toFloat(value))
  let uint32 = value => JSON.Number(value)
  let uint53 = uint32
  let int53 = uint32
  let bytes = value => JSON.String(Base64url.encode(value))
  let hash = value => JSON.String(Hex.encode(value))
  /** A value already written, as a call's input is by its operation's type. */
  let json = (value: JSON.t) => value
  let list = write => items => JSON.Array(items->Array.map(write))
  let map = write => entries => JSON.Object(entries->Dict.mapValues(write))

  /** A field, by its name. */
  let field = (name, value, write) => Some((name, write(value)))
  /** A field that may be absent, and is left out then. */
  let optional = (name, value, write) => value->Option.map(value => (name, write(value)))
  let record = fields => JSON.Object(fields->Array.filterMap(field => field)->Dict.fromArray)
  /** A union's case, named in its tag. */
  let case = (tag, name, fields) => record([Some((tag, JSON.String(name))), ...fields])

  /** A set of names, by its table of each name and its choice, in the table's order. */
  let flags = (set, table) => JSON.Array(
    table->Array.filterMap(((name, flag)) =>
      set->Array.includes(flag) ? Some(JSON.String(name)) : None
    ),
  )
}

module FromJson = {
  let bool = json =>
    switch json->JSON.Decode.bool {
    | Some(value) => value
    | None => fail("a boolean")
    }

  let string = json =>
    switch json->JSON.Decode.string {
    | Some(value) => value
    | None => fail("a string")
    }

  let float = json =>
    switch json->JSON.Decode.float {
    | Some(value) => value
    | None => fail("a number")
    }

  let bounded = (json, bounds) =>
    switch json->JSON.Decode.float {
    | Some(n) if isWithin(n, bounds) => n
    | Some(_) | None => fail(bounds.text)
    }

  let int = json => bounded(json, int32Bounds)->Float.toInt
  let uint32 = json => bounded(json, uint32Bounds)
  let uint53 = json => bounded(json, uint53Bounds)
  let int53 = json => bounded(json, int53Bounds)

  let bytes = json =>
    switch json->JSON.Decode.string->Option.flatMap(Base64url.decode) {
    | Some(bytes) => bytes
    | None => fail("base64url, unpadded")
    }

  let hash = json =>
    switch json->JSON.Decode.string->Option.flatMap(Hex.decode) {
    | Some(bytes) if TypedArray.length(bytes) == 32 => bytes
    | Some(_) | None => fail("64 lowercase hex digits")
    }

  let list = read =>
    json =>
      switch json->JSON.Decode.array {
      | Some(items) =>
        items->Array.mapWithIndex((item, i) => within(Malformed.Index(i), () => read(item)))
      | None => fail("an array")
      }

  let map = read =>
    json =>
      switch json->JSON.Decode.object {
      | Some(entries) =>
        entries
        ->Dict.toArray
        ->Array.map(((key, value)) => (key, within(Malformed.Key(key), () => read(value))))
        ->Dict.fromArray
      | None => fail("an object")
      }

  /** Another type's reading. */
  let named = fromJson => json => unwrap(fromJson(json))

  /** Exactly this string, as a call's interface is held to its module's. */
  let exactly = text =>
    json =>
      switch string(json) {
      | given if given == text => given
      | _ => fail(oneOf([text]))
      }

  /** A record's fields, its own alone, by name. */
  type fields = Map.t<string, JSON.t>

  let record = (json, build) =>
    reading(() =>
      switch json->JSON.Decode.object {
      | Some(entries) => build(Map.fromArray(entries->Dict.toArray))
      | None => fail("an object")
      }
    )

  let field = (fields: fields, name, read) =>
    within(Malformed.Field(name), () =>
      switch fields->Map.get(name) {
      | Some(value) => read(value)
      | None => fail("present")
      }
    )

  let optional = (fields: fields, name, read) =>
    fields->Map.get(name)->Option.map(value => within(Malformed.Field(name), () => read(value)))

  /** A union, its case's name in its tag given to `build` with its fields. */
  let union = (json, tag, build) =>
    record(json, fields => build(field(fields, tag, string), fields))

  /** A case no union of these names has. */
  let unknown = unknownName

  /** An enumeration, by its table of each name and its choice. */
  let choice = (json, table) =>
    reading(() =>
      switch json
      ->JSON.Decode.string
      ->Option.flatMap(name => table->Array.find(((n, _)) => n == name)) {
      | Some((_, choice)) => choice
      | None => fail(oneOf(table->Array.map(((name, _)) => name)))
      }
    )

  /** A set of names, each once, by its table of each name and its choice, in the table's order. */
  let flags = (json, table) =>
    reading(() => {
      let names = table->Array.map(((name, _)) => name)
      switch json->JSON.Decode.array {
      | Some(items) =>
        let given = items->Array.mapWithIndex((item, i) =>
          within(
            Malformed.Index(i),
            () =>
              // A name repeated is refused as one unknown is, as the Rust side writes it.
              switch item->JSON.Decode.string {
              | Some(name)
                if names->Array.includes(name) &&
                  !(items->Array.slice(~start=0, ~end=i)->Array.includes(item)) => name
              | Some(_) | None => fail(oneOf(names))
              },
          )
        )
        table->Array.filterMap(((name, flag)) => given->Array.includes(name) ? Some(flag) : None)
      | None => fail("an array")
      }
    })
}

let asInteger = (value: Cbor.value) =>
  switch value {
  | Integer(n) => Some(n)
  | Bytes(_)
  | Text(_)
  | Array(_)
  | Map(_)
  | Tag(_, _)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

let asBytes = (value: Cbor.value) =>
  switch value {
  | Bytes(bytes) => Some(bytes)
  | Integer(_)
  | Text(_)
  | Array(_)
  | Map(_)
  | Tag(_, _)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

let asText = (value: Cbor.value) =>
  switch value {
  | Text(text) => Some(text)
  | Integer(_)
  | Bytes(_)
  | Array(_)
  | Map(_)
  | Tag(_, _)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

let asArray = (value: Cbor.value) =>
  switch value {
  | Array(items) => Some(items)
  | Integer(_)
  | Bytes(_)
  | Text(_)
  | Map(_)
  | Tag(_, _)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

let asMap = (value: Cbor.value) =>
  switch value {
  | Map(pairs) => Some(pairs)
  | Integer(_)
  | Bytes(_)
  | Text(_)
  | Array(_)
  | Tag(_, _)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

let asBool = (value: Cbor.value) =>
  switch value {
  | Bool(value) => Some(value)
  | Integer(_)
  | Bytes(_)
  | Text(_)
  | Array(_)
  | Map(_)
  | Tag(_, _)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

let asFloat = (value: Cbor.value) =>
  switch value {
  | Float(value) => Some(value)
  | Integer(_)
  | Bytes(_)
  | Text(_)
  | Array(_)
  | Map(_)
  | Tag(_, _)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_) =>
    None
  }

module ToCbor = {
  let bool = value => Cbor.Bool(value)
  let string = value => Cbor.Text(value)
  let float = value => Cbor.Float(value)
  let int = value => Cbor.Integer(BigInt.fromInt(value))
  // A float that holds no integer is written as one, which no reader of an integer takes.
  let uint32 = value =>
    switch BigInt.fromFloat(value) {
    | Some(n) => Cbor.Integer(n)
    | None => Cbor.Float(value)
    }
  let uint53 = uint32
  let int53 = uint32
  let bytes = value => Cbor.Bytes(value)
  let hash = bytes
  /** A value already written, as a call's input is by its operation's type. */
  let cbor = (value: Cbor.value) => value
  let list = write => items => Cbor.Array(items->Array.map(write))
  let map = write =>
    entries => Cbor.Map(
      entries->Dict.toArray->Array.map(((key, value)) => (Cbor.Text(key), write(value))),
    )

  /** A field, by its key. */
  let field = (key, value, write) => Some((key, write(value)))
  /** A field that may be absent, and is left out then. */
  let optional = (key, value, write) => value->Option.map(value => (key, write(value)))
  let record = fields => Cbor.Map(
    fields->Array.filterMap(field => field)->Array.map(((key, value)) => (int(key), value)),
  )
  /** A union's case, its code at key 0. */
  let case = (code, fields) => record([Some((0, int(code))), ...fields])

  /** A set of names by its table of codes and choices, the integer of the bits set. */
  let flags = (set, table) => Cbor.Integer(
    table->Array.reduce(0n, (bits, (code, flag)) =>
      set->Array.includes(flag) ? BigInt.bitwiseOr(bits, BigInt.fromInt(code)) : bits
    ),
  )
}

module FromCbor = {
  let bool = cbor =>
    switch asBool(cbor) {
    | Some(value) => value
    | None => fail("a boolean")
    }

  let string = cbor =>
    switch asText(cbor) {
    | Some(value) => value
    | None => fail("a text string")
    }

  // A float JSON cannot write, an infinity or a NaN, is none of the subset's.
  let float = cbor =>
    switch asFloat(cbor) {
    | Some(value) if Float.isFinite(value) => value
    | Some(_) | None => fail("a finite float")
    }

  let bounded = (cbor, bounds) =>
    switch asInteger(cbor)->Option.map(BigInt.toFloat) {
    | Some(n) if isWithin(n, bounds) => n
    | Some(_) | None => fail(bounds.text)
    }

  let int = cbor => bounded(cbor, int32Bounds)->Float.toInt
  let uint32 = cbor => bounded(cbor, uint32Bounds)
  let uint53 = cbor => bounded(cbor, uint53Bounds)
  let int53 = cbor => bounded(cbor, int53Bounds)

  let bytes = cbor =>
    switch asBytes(cbor) {
    | Some(bytes) => bytes
    | None => fail("a byte string")
    }

  let hash = cbor =>
    switch asBytes(cbor) {
    | Some(bytes) if TypedArray.length(bytes) == 32 => bytes
    | Some(_) | None => fail("32 bytes")
    }

  let list = read =>
    cbor =>
      switch asArray(cbor) {
      | Some(items) =>
        items->Array.mapWithIndex((item, i) => within(Malformed.Index(i), () => read(item)))
      | None => fail("an array")
      }

  let map = read =>
    cbor =>
      switch asMap(cbor) {
      | Some(pairs) =>
        pairs
        ->Array.map(((key, value)) =>
          switch asText(key) {
          | Some(key) => (key, within(Malformed.Key(key), () => read(value)))
          | None => fail("a map keyed by text")
          }
        )
        ->Dict.fromArray
      | None => fail("a map")
      }

  /** Another type's reading. */
  let named = fromCbor => cbor => unwrap(fromCbor(cbor))

  /** Exactly this text string, as a call's interface is held to its module's. */
  let exactly = text =>
    cbor =>
      switch string(cbor) {
      | given if given == text => given
      | _ => fail(oneOf([text]))
      }

  /** A text no operation has, at the field naming it. */
  let unknownText = unknownName

  /** A record's fields by their keys, a key that is no integer passed over as any unknown. */
  type fields = Map.t<bigint, Cbor.value>

  let record = (cbor, build) =>
    reading(() =>
      switch asMap(cbor) {
      | Some(pairs) =>
        build(
          Map.fromArray(
            pairs->Array.filterMap(((key, value)) => asInteger(key)->Option.map(n => (n, value))),
          ),
        )
      | None => fail("a map")
      }
    )

  let field = (fields: fields, key, name, read) =>
    within(Malformed.Field(name), () =>
      switch fields->Map.get(BigInt.fromInt(key)) {
      | Some(value) => read(value)
      | None => fail("present")
      }
    )

  let optional = (fields: fields, key, name, read) =>
    fields
    ->Map.get(BigInt.fromInt(key))
    ->Option.map(value => within(Malformed.Field(name), () => read(value)))

  /** A union, its case's code at key 0 given to `build` with its fields. */
  let union = (cbor, tag, build) =>
    record(cbor, fields => build(field(fields, 0, tag, int), fields))

  /** A case no union of these codes has. */
  let unknown = (tag, codes) =>
    within(Malformed.Field(tag), () => fail(oneOf(codes->Array.map(code => Int.toString(code)))))

  /** An enumeration, by its table of each code and its choice. */
  let choice = (cbor, table) =>
    reading(() =>
      switch asInteger(cbor)->Option.flatMap(n =>
        table->Array.find(((code, _)) => BigInt.fromInt(code) == n)
      ) {
      | Some((_, choice)) => choice
      | None => fail(oneOf(table->Array.map(((code, _)) => Int.toString(code))))
      }
    )

  /** A set of names, by its table of each code and its choice, in the table's order. */
  let flags = (cbor, table) =>
    reading(() => {
      let all =
        table->Array.reduce(0n, (bits, (code, _)) => BigInt.bitwiseOr(bits, BigInt.fromInt(code)))
      switch asInteger(cbor) {
      | Some(bits) if bits >= 0n && BigInt.bitwiseAnd(bits, BigInt.bitwiseNot(all)) == 0n =>
        table->Array.filterMap(((code, flag)) =>
          BigInt.bitwiseAnd(bits, BigInt.fromInt(code)) != 0n ? Some(flag) : None
        )
      | Some(_) | None =>
        fail(
          `an integer of the bits ${table
            ->Array.map(((code, _)) => Int.toString(code))
            ->Array.join(", ")}`,
        )
      }
    })
}
