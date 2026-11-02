module I = Envelope.Contracts.Interface.DeploymentGrants
module Cbor = Codec.Cbor

let rec jsonKeys = (given, written) =>
  switch (given->JSON.Decode.object, written->JSON.Decode.object) {
  | (Some(given), Some(written)) =>
    given
    ->Dict.toArray
    ->Array.every(((key, value)) =>
      written->Dict.get(key)->Option.mapOr(false, w => jsonKeys(value, w))
    )
  | _ => true
  }

let rec cborKeys = (given: Cbor.value, written: Cbor.value) =>
  switch (given, written) {
  | (Map(given), Map(written)) =>
    given->Array.every(((key, value)) =>
      written->Array.find(((k, _)) => k == key)->Option.mapOr(false, ((_, w)) => cborKeys(value, w))
    )
  | (
      Integer(_)
      | Bytes(_)
      | Text(_)
      | Array(_)
      | Map(_)
      | Tag(_)
      | Bool(_)
      | Null
      | Undefined
      | Simple(_)
      | Float(_),
      _,
    ) => true
  }

let malformed = (): Envelope.Malformed.t => {
  at: [Field("input")],
  expected: "only the fixed grant operation fields",
}

let fromJson = json =>
  I.fromJson(json)->Result.flatMap(envelope => {
    let input =
      json->JSON.Decode.object->Option.flatMap(o => o->Dict.get("input"))->Option.getOr(JSON.Null)
    let written =
      I.toJson(envelope)
      ->JSON.Decode.object
      ->Option.flatMap(o => o->Dict.get("input"))
      ->Option.getOr(JSON.Null)
    jsonKeys(input, written) ? Ok(envelope) : Error(malformed())
  })

let fromCbor = cbor =>
  I.fromCbor(cbor)->Result.flatMap(envelope =>
    cborKeys(cbor, I.toCbor(envelope)) ? Ok(envelope) : Error(malformed())
  )
