/***
 * `Signed` held to `tests/capability/signed.json`, each record verified at its time to its signer
 * and content or its refusal.
 */
open Node
open Sample

let signed = "tests/capability/signed.json"

let kindOf = name =>
  switch name {
  | "capability" => Signed.Capability
  | "certificate" => Certificate
  | "account" => Account
  | "bundle" => Bundle
  | "authority" => Authority
  | "directory" => Directory
  | "call" => Call
  | _ => JsError.throwWithMessage(`${name}: no kind`)
  }

/** The signer a case names, `{"root": true}` or `{role, scope?, sub?}`. */
let signerOf = json =>
  switch member(json, "root") {
  | Some(_) => Signed.Root
  | None =>
    Signed({
      role: json->at(["role"])->string,
      scope: member(json, "scope")->Option.map(number),
      sub: member(json, "sub")->Option.map(string),
    })
  }

/** The refusal a case names, a name in lower case, `{"above": ...}` or `{"malformed": true}`. */
let rec refusedOf = (json): Signed.refused =>
  switch (json->JSON.Decode.string, member(json, "above"), member(json, "malformed")) {
  | (Some("algorithm"), None, None) => Algorithm
  | (Some("typ"), None, None) => Typ
  | (Some("unknown"), None, None) => Unknown
  | (Some("signature"), None, None) => Signature
  | (Some("role"), None, None) => Role
  | (Some("scope"), None, None) => Scope
  | (Some("expired"), None, None) => Expired
  | (Some("early"), None, None) => Early
  | (None, Some(above), None) => Above(refusedOf(above))
  | (None, None, Some(_)) => Malformed("")
  | _ => JsError.throwWithMessage(`${JSON.stringify(json)}: no one refusal`)
  }

/** A refusal with any Malformed's why left out, since a case names no why. */
let rec unexplained = (refused: Signed.refused): Signed.refused =>
  switch refused {
  | Malformed(_) => Malformed("")
  | Above(refused) => Above(unexplained(refused))
  | Algorithm | Typ | Unknown | Signature | Role | Scope | Expired | Early => refused
  }

let content = text =>
  switch Codec.Cbor.decodeDeterministic(hex(text)) {
  | Ok(value) => value
  | Error(_) => JsError.throwWithMessage(`${text}: no deterministic CBOR`)
  }

test("each kind's typ", () =>
  deepEqual(
    [Signed.Capability, Certificate, Account, Bundle, Authority, Directory, Call]->Array.map(
      Signed.typ,
    ),
    [
      "monoflake:capability:2",
      "monoflake:certificate:1",
      "monoflake:account:1",
      "monoflake:bundle:1",
      "monoflake:authority:1",
      "monoflake:directory:1",
      "monoflake:call:1",
    ],
  )
)

test("every record verified by its chain to the root, or refused for the first reason", () => {
  let sample = read(signed)
  let root = sample->hexAt(["root"])
  sample
  ->at(["cases"])
  ->array
  ->Array.forEach(item => {
    let message = item->at(["what"])->string
    let trust: Signed.trust = {
      root,
      certificates: item
      ->at(["certificates"])
      ->array
      ->Array.map(name => sample->hexAt(["certificates", name->string])),
      now: item->at(["now"])->number,
    }
    let got = Signed.verify(trust, item->at(["kind"])->string->kindOf, item->hexAt(["record"]))
    switch (member(item, "verified"), member(item, "refused")) {
    | (Some(verified), None) =>
      deepEqual(
        got,
        Ok({
          content: verified->at(["content"])->string->content,
          signer: verified->at(["signer"])->signerOf,
        }),
        ~message,
      )
    | (None, Some(refused)) =>
      deepEqual(got->Result.mapError(unexplained), Error(refusedOf(refused)), ~message)
    | _ => JsError.throwWithMessage(`${message}: neither verified nor refused`)
    }
  })
})
