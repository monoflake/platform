/***
 * A scope read from its bundle's issuer section, its allowance compared by vocabulary*, RFC vuanj.
 */
module Contracts = Envelope.Contracts
module Needs = Vocabulary.Needs

type t = {status: Contracts.ScopeStatus.t, allowance: dict<Needs.value>}

type unheld =
  | Other(float)
  | Absent
  | Malformed(Envelope.Malformed.t)

/** Where the issuer section stands within a bundle. */
let section: array<Envelope.Malformed.step> = [Field("body"), Key("issuer")]

/** A value as `allowance-value` holds it, as the vocabulary compares it. */
let value = (v: Contracts.AllowanceValue.t): Needs.value =>
  switch v {
  | Flag({value}) => Flag(value)
  | Amount({value}) => Amount(value)
  | One({value}) => One(value)
  | Some({values}) => Subset(values)
  }

let values = held => held->Dict.mapValues(value)

let read = (bundle: Contracts.Bundle.t, ~scope) =>
  if bundle.scope != scope {
    Error(Other(bundle.scope))
  } else {
    switch bundle.body->Dict.get("issuer") {
    | None => Error(Absent)
    | Some(bytes) =>
      switch Codec.Cbor.decodeDeterministic(bytes) {
      | Error(_) =>
        Error(
          Malformed({at: section, expected: "one CBOR data item as RFC 8949's 4.2.1 writes it"}),
        )
      | Ok(cbor) =>
        switch Contracts.BundleIssuer.fromCbor(cbor) {
        | Error({at, expected}) => Error(Malformed({at: Array.concat(section, at), expected}))
        | Ok(issuer) =>
          Ok({
            status: issuer.status->Option.getOr(Active),
            allowance: values(issuer.allowance),
          })
        }
      }
    }
  }

let status = scope => scope.status

let allowance = scope => Needs.filled(Needs.model, Held, scope.allowance)

type refused =
  | Suspended
  | Deleted
  | Unfit(array<Needs.failure>)

let fits = (scope, ~need) =>
  switch scope.status {
  | Suspended => Error(Suspended)
  | Deleted => Error(Deleted)
  | Active =>
    Needs.fits(
      Needs.model,
      ~need=values(need),
      ~allowance=scope.allowance,
    )->Result.mapError(failed => Unfit(failed))
  }
