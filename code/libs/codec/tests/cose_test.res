/***
 * `Sign1` and `Cwt` held to cose-wg's examples, read as they stand: their structure alone, since a
 * signature is made and checked by what the caller gives, `docs/code.md`. `cose.rs` beside it is
 * the same in Rust.
 */
open Node
open Sample

let sign1Tests = "vendor/cose-examples/sign1-tests"
let eddsa01 = "vendor/cose-examples/eddsa-examples/eddsa-sig-01.json"
let eddsa02 = "vendor/cose-examples/eddsa-examples/eddsa-sig-02.json"
let cwtA3 = "vendor/cose-examples/CWT/A_3.json"

/** Every Sign1 case, by its file's name: each of `sign1-tests/`, and the two EdDSA ones. */
let cases = () =>
  Array.concat(
    readdirSync(fromRoot(`${sign1Tests}/`))
    ->Array.toSorted((a, b) => a < b ? -1. : a > b ? 1. : 0.)
    ->Array.map(name => (name, read(`${sign1Tests}/${name}`))),
    [eddsa01, eddsa02]->Array.map(path => (
      path->String.split("/")->Array.at(-1)->Option.getOr(path),
      read(path),
    )),
  )

/** Whether a case's upstream changed its output after signing it by `failure`. */
let failedBy = (case, failure) =>
  case->at(["input"])->member("failures")->Option.flatMap(f => f->member(failure))->Option.isSome

/** The bytes a case's signature covers, as built from what was decoded of it. */
let toBeSigned = (case, sign1: Sign1.t) =>
  Sign1.toBeSigned(
    ~protected=sign1.protected,
    ~aad=case
    ->at(["input", "sign0"])
    ->member("external")
    ->Option.mapOr(bytes([]), external_ => external_->string->hex),
    ~payload=sign1.payload->Option.getOr(bytes([])),
  )

let decoded = (name, bytes) =>
  switch Sign1.decode(bytes) {
  | Ok(read) => read
  | Error(_) => JsError.throwWithMessage(`${name}: refused`)
  }

let written = (sign1, ~tagged) =>
  switch Sign1.encode(sign1, ~tagged) {
  | Ok(bytes) => bytes
  | Error(OutOfRange | RepeatedKey | TooDeep) => JsError.throwWithMessage("unwritable")
  }

test("every Sign1 case is read, written back, and its signed bytes built", () =>
  cases()->Array.forEach(((name, case)) => {
    let message = name
    let bytes = case->hexAt(["output", "cbor"])
    if failedBy(case, "ChangeCBORTag") {
      // sign-fail-01: a tag other than 18 is another message, not a Sign1.
      deepEqual(Sign1.decode(bytes), Error(Shape), ~message)
    } else {
      let (sign1, tagged) = decoded(name, bytes)
      deepEqual(tagged, !failedBy(case, "RemoveCBORTag"), ~message)
      deepEqual(written(sign1, ~tagged), bytes, ~message)
      let expected = case->hexAt(["intermediates", "ToBeSign_hex"])
      if case->member("fail")->Option.flatMap(JSON.Decode.bool) == Some(true) {
        // sign-fail-02 changes the payload, -03 and -04 the algorithm, -06 adds a protected
        // attribute and -07 removes one, each after signing: the structure stands, and what is
        // signed over differs from what was signed, which only a signature check catches.
        notDeepEqual(toBeSigned(case, sign1), expected, ~message)
      } else {
        deepEqual(toBeSigned(case, sign1), expected, ~message)
      }
    }
  })
)

test("an empty protected map is kept as written and signed over as no bytes", () => {
  // sign-pass-01 carries its protected header as h'a0', and gives what is signed as holding h''.
  let case = read(`${sign1Tests}/sign-pass-01.json`)
  let (sign1, _) = decoded("sign-pass-01.json", case->hexAt(["output", "cbor"]))
  deepEqual(sign1.protected, bytes([0xa0]))
  deepEqual(toBeSigned(case, sign1), case->hexAt(["intermediates", "ToBeSign_hex"]))
  let none = Sign1.toBeSigned(~protected=bytes([]), ~aad=bytes([]), ~payload=bytes([]))
  deepEqual(Sign1.toBeSigned(~protected=bytes([0xa0]), ~aad=bytes([]), ~payload=bytes([])), none)
  // Any other map is signed over as written.
  notDeepEqual(
    Sign1.toBeSigned(~protected=bytes([0xbf, 0xff]), ~aad=bytes([]), ~payload=bytes([])),
    none,
  )
})

test("a Sign1 holds a detached payload and empty protected bytes", () => {
  let sign1: Sign1.t = {
    protected: bytes([]),
    unprotected: [],
    payload: None,
    signature: bytes([1, 2]),
  }
  let untagged = written(sign1, ~tagged=false)
  deepEqual(untagged, bytes([0x84, 0x40, 0xa0, 0xf6, 0x42, 0x01, 0x02]))
  deepEqual(Sign1.decode(untagged), Ok((sign1, false)))
  let tagged = written(sign1, ~tagged=true)
  deepEqual(tagged->TypedArray.get(0), Some(0xd2))
  deepEqual(Sign1.decode(tagged), Ok((sign1, true)))
  deepEqual(
    Sign1.toBeSigned(~protected=bytes([]), ~aad=bytes([]), ~payload=bytes([])),
    // ["Signature1", h'', h'', h''].
    bytes([
      0x84,
      0x6a,
      0x53,
      0x69,
      0x67,
      0x6e,
      0x61,
      0x74,
      0x75,
      0x72,
      0x65,
      0x31,
      0x40,
      0x40,
      0x40,
    ]),
  )
})

test("what is no Sign1 is refused", () => {
  // Three fields; a text where the signature stands; a map's bytes where the map stands.
  deepEqual(Sign1.decode(bytes([0x83, 0x40, 0xa0, 0xf6])), Error(Shape))
  deepEqual(Sign1.decode(bytes([0x84, 0x40, 0xa0, 0xf6, 0x60])), Error(Shape))
  deepEqual(Sign1.decode(bytes([0x84, 0x40, 0x41, 0xa0, 0xf6, 0x40])), Error(Shape))
  deepEqual(Sign1.decode(bytes([0x84, 0x40])), Error(Cbor(Truncated)))
  // Protected bytes that are no map, a map and more, a map cut short, and a map not valid.
  [[0x00], [0xa0, 0x00], [0xa1, 0x01], [0xa2, 0x01, 0x00, 0x01, 0x00]]->Array.forEach(protected => {
    let sign1: Sign1.t = {
      protected: bytes(protected),
      unprotected: [],
      payload: None,
      signature: bytes([]),
    }
    deepEqual(Sign1.decode(written(sign1, ~tagged=true)), Error(Shape))
  })
  // A map written as 4.2.1 would not write it is still a map.
  let sign1: Sign1.t = {
    protected: bytes([0xbf, 0x01, 0x00, 0xff]),
    unprotected: [],
    payload: None,
    signature: bytes([]),
  }
  deepEqual(Sign1.decode(written(sign1, ~tagged=false)), Ok((sign1, false)))
})

test("a CWT is read with its claims under tags 61 and 18, or 18 alone", () => {
  let case = read(cwtA3)
  let message = cwtA3
  let output = case->hexAt(["output", "cbor"])
  let expected = switch Cbor.decode(case->hexAt(["input", "plaintext_hex"])) {
  | Ok(Map(claims)) => claims
  | Ok(
    Integer(_)
    | Bytes(_)
    | Text(_)
    | Array(_)
    | Tag(_)
    | Bool(_)
    | Null
    | Undefined
    | Simple(_)
    | Float(_),
  )
  | Error(_) =>
    JsError.throwWithMessage(`${cwtA3}: its plaintext is no map`)
  }
  switch Cwt.decode(output) {
  | Ok((sign1, claims)) =>
    deepEqual(claims, expected, ~message)
    deepEqual(Cwt.payload(claims)->Result.mapOr(None, p => Some(p)), sign1.payload, ~message)
    deepEqual(
      Sign1.toBeSigned(
        ~protected=sign1.protected,
        ~aad=bytes([]),
        ~payload=sign1.payload->Option.getOr(bytes([])),
      ),
      case->hexAt(["intermediates", "ToBeSign_hex"]),
      ~message,
    )
    deepEqual(Cwt.decode(bytes([0xd8, 0x3d, ...ints(output)])), Ok((sign1, claims)), ~message)
  | Error(_) => JsError.throwWithMessage(`${cwtA3}: refused`)
  }
  // Tag 61 over a Sign1 that is not under its own tag 18.
  let untagged = ints(output)->Array.slice(~start=1)
  deepEqual(Cwt.decode(bytes([0xd8, 0x3d, ...untagged])), Error(Sign1(Shape)))
})

test("what carries no claims is refused", () => {
  let sign = payload =>
    written({protected: bytes([]), unprotected: [], payload, signature: bytes([])}, ~tagged=true)
  deepEqual(Cwt.decode(sign(None)), Error(Detached))
  deepEqual(Cwt.decode(sign(Some(bytes([0x01])))), Error(Unclaimed))
  deepEqual(Cwt.decode(sign(Some(bytes([0x18])))), Error(Payload(Truncated)))
  deepEqual(
    Cwt.decode(sign(Some(bytes([0xa0])))),
    Ok((
      {protected: bytes([]), unprotected: [], payload: Some(bytes([0xa0])), signature: bytes([])},
      [],
    )),
  )
  deepEqual(Cwt.decode(bytes([0xd8, 0x3d, 0x00])), Error(Sign1(Shape)))
})
