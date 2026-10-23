/***
 * A target over HTTP, RFCs vr5lw and ge55b, and the chain a run signs by, RFC p8e8k.
 */
module Cbor = Codec.Cbor
module Sign1 = Codec.Sign1
module Signed = Capability.Signed
module Contracts = Envelope.Contracts

/** A key the chain holds, and its certificate as signed. */
type holder = {keys: Noble.keys, certificate: Uint8Array.t}

type chain = {
  rootKey: Uint8Array.t,
  /** The intermediate's, the authority's and the organization's, as signed. */
  certificates: array<Uint8Array.t>,
  components: dict<holder>,
}

/** The scope of the one organization a run is about. */
let scope = 1.

/** How long a certificate of the run lives, in seconds. */
let lifetime = 86400.

/** COSE's labels, as `capability*` reads them, b8f35. */
let alg = 1n
let kid = 4n
let typ = 16n
let kcwt = 13n
let ed25519 = -19n

let unwritable = (unwritable: Cbor.unwritable) =>
  switch unwritable {
  | OutOfRange => "an integer out of its range"
  | RepeatedKey => "a map's key repeated"
  | TooDeep => "nested too deep"
  }

/** What the run itself writes, which cannot be unwritable, so a refusal is the runner's fault. */
let written = value =>
  switch Cbor.encode(value) {
  | Ok(bytes) => bytes
  | Error(why) => JsError.throwWithMessage(`the runner wrote CBOR that is ${unwritable(why)}`)
  }

/** A key's `kid`, the first 16 bytes of the BLAKE3 of its public key. */
let kidOf = key => Noble.blake3(key, {dkLen: 32})->TypedArray.slice(~start=0, ~end=16)

/** A Sign1 under tag 18 by `by`, its protected header `alg`, `kid` and `typ` alone. */
let sign = (~by: Noble.keys, ~kind, ~unprotected, payload) => {
  let protected = written(
    Cbor.Map([
      (Cbor.Integer(alg), Cbor.Integer(ed25519)),
      (Cbor.Integer(kid), Cbor.Bytes(kidOf(by.publicKey))),
      (Cbor.Integer(typ), Cbor.Text(Signed.typ(kind))),
    ]),
  )
  let message = Sign1.toBeSigned(~protected, ~aad=Uint8Array.fromLength(0), ~payload)
  let signature = Noble.sign(message, by.secretKey)
  switch Sign1.encode({protected, unprotected, payload: Some(payload), signature}, ~tagged=true) {
  | Ok(bytes) => bytes
  | Error(why) => JsError.throwWithMessage(`the runner wrote a Sign1 that is ${unwritable(why)}`)
  }
}

/** A certificate of `keys` in a role, signed by `by`. */
let certify = (~by, ~keys: Noble.keys, ~role, ~scope=?, ~sub=?, ~now) => {
  let iat = Math.floor(now /. 1000.)
  let content: Contracts.Certificate.t = {
    iat,
    exp: iat +. lifetime,
    ?sub,
    cnf: {key: {kty: Okp, crv: Ed25519, x: keys.publicKey}},
    ?scope,
    role,
  }
  sign(~by, ~kind=Certificate, ~unprotected=[], written(Contracts.Certificate.toCbor(content)))
}

let chain = (~components, ~now) => {
  let root = Noble.keygen()
  let intermediate = Noble.keygen()
  let authority = Noble.keygen()
  let organization = Noble.keygen()
  {
    rootKey: root.publicKey,
    certificates: [
      certify(~by=root, ~keys=intermediate, ~role=Intermediate, ~now),
      certify(~by=intermediate, ~keys=authority, ~role=Authority, ~now),
      certify(~by=authority, ~keys=organization, ~role=Organization, ~scope, ~now),
    ],
    components: components
    ->Array.map(name => {
      let keys = Noble.keygen()
      (
        name,
        {
          keys,
          certificate: certify(~by=organization, ~keys, ~role=Component, ~scope, ~sub=name, ~now),
        },
      )
    })
    ->Dict.fromArray,
  }
}

let root = chain => chain.rootKey

let certificates = chain => chain.certificates

let media = (form: Run.form) =>
  switch form {
  | Cbor => "application/cbor"
  | Json => "application/json"
  }

let where = (malformed: Envelope.Malformed.t) =>
  `${malformed.at
    ->Array.map(step =>
      switch step {
      | Field(name) => name
      | Index(i) => Int.toString(i)
      | Key(key) => key
      }
    )
    ->Array.join("/")}: ${malformed.expected}`

/** A call's CBOR, as its interface's `envelope` writes it. */
let callCbor = (interface, call) =>
  switch Contracts.callJsonToCbor(interface, call) {
  | Some(Ok(value)) => Ok(written(value))
  | Some(Error(malformed)) =>
    Error(`the call is not as ${interface} writes it, at ${where(malformed)}`)
  | None => Error(`no interface ${interface}`)
  }

/**
 * What is answered where the body is no answer, `unknown`, as nothing the platform said was read.
 */
let noAnswer = (status, why): Run.answered => Failed({
  failure: "unknown",
  reason: "malformed",
  message: `HTTP ${Int.toString(status)}, its body no answer: ${why}`,
})

let failed = (error: Contracts.Error.t): Run.answered => Failed({
  failure: (error.failure :> string),
  reason: error.reason,
  message: error.message,
})

/** An output held to its type, which the answer then gives as JSON. */
let output = (status, read, name): Run.answered =>
  switch read {
  | Some(Ok(json)) => Answered(json)
  | Some(Error(malformed)) =>
    noAnswer(status, `the output not as ${name} writes it, at ${where(malformed)}`)
  | None => noAnswer(status, `no type ${name}`)
  }

let parsed = bytes =>
  try Ok(JSON.parseOrThrow(Web.text(bytes))) catch {
  | JsExn(e) => Error(e->JsExn.message->Option.getOr("no JSON"))
  }

/** An answer read by its `status` alone, the HTTP status only where the body is none, ge55b. */
let answerOf = (~name, ~form, status, contentType, bytes) => {
  let cbor = switch contentType {
  | Some(given) => given->String.startsWith("application/cbor")
  | None => form == Run.Cbor
  }
  if cbor {
    switch Cbor.decode(bytes) {
    | Error(_) => noAnswer(status, "no CBOR")
    | Ok(value) =>
      switch Contracts.Answer.fromCbor(value, data => Ok(data)) {
      | Ok(Success(data)) => output(status, Contracts.cborToJson(name, data), name)
      | Ok(Error(error)) => failed(error)
      | Error(malformed) => noAnswer(status, where(malformed))
      }
    }
  } else {
    switch parsed(bytes) {
    | Error(why) => noAnswer(status, why)
    | Ok(json) =>
      switch Contracts.Answer.fromJson(json, data => Ok(data)) {
      | Ok(Success(data)) =>
        output(
          status,
          Contracts.jsonToCbor(name, data)->Option.map(r => r->Result.map(_ => data)),
          name,
        )
      | Ok(Error(error)) => failed(error)
      | Error(malformed) => noAnswer(status, where(malformed))
      }
    }
  }
}

/** A request made, its status, its `Content-Type` and its body, or why nothing answered. */
let post = async (url, ~headers, ~body) =>
  switch await Web.fetch(url, {method: "POST", headers, ?body}) {
  | response =>
    let bytes = Uint8Array.fromBuffer(await response->Web.arrayBuffer)
    Ok((
      response->Web.status,
      response->Web.headers->Web.header("content-type")->Nullable.toOption,
      bytes,
    ))
  | exception JsExn(e) => Error(`${url}: ${e->JsExn.message->Option.getOr("not reached")}`)
  }

/** A signed record's kind and the type its content is read as, by the record's name. */
let records = name =>
  switch name {
  | "capability" => Some((Signed.Capability, "capability"))
  | "certificate" => Some((Signed.Certificate, "certificate"))
  | "account" => Some((Signed.Account, "account-credential"))
  | "bundle" => Some((Signed.Bundle, "bundle"))
  | "authority" => Some((Signed.Authority, "authority-record"))
  | "directory" => Some((Signed.Directory, "directory-row"))
  | _ => None
  }

let rec refusal = (refused: Signed.refused) =>
  switch refused {
  | Malformed(why) => `malformed: ${why}`
  | Algorithm => "an alg but Ed25519's"
  | Typ => "a typ not its kind's"
  | Unknown => "a kid of no certificate the run made, nor its root's"
  | Signature => "a signature its signer's key does not verify"
  | Role => "a signer whose role may not sign it"
  | Scope => "a signer holding another scope"
  | Expired => "expired"
  | Early => "issued ahead of now"
  | Above(refused) => `a certificate above it ${refusal(refused)}`
  }

let verified = (chain, bytes, record) =>
  switch (chain, records(record)) {
  | (None, _) => Error("no chain the run made to verify by")
  | (_, None) => Error(`no signed record ${record}`)
  | (Some(chain), Some((kind, content))) =>
    let trust: Signed.trust = {
      root: chain.rootKey,
      certificates: chain.certificates,
      now: Date.now() /. 1000.,
    }
    switch Signed.verify(trust, kind, bytes) {
    | Error(refused) => Error(refusal(refused))
    | Ok({content: claims}) =>
      switch Contracts.cborToJson(content, claims) {
      | Some(Ok(json)) => Ok(json)
      | Some(Error(malformed)) =>
        Error(`its content not as ${content} writes it, at ${where(malformed)}`)
      | None => Error(`no type ${content}`)
      }
    }
  }

let target = (~base, ~chain, ~bounds, ~token=?) => {
  let base = base->String.endsWith("/") ? base->String.slice(~start=0, ~end=-1) : base
  let call = async (~interface, ~operation, ~input, ~form, ~as_) => {
    let call = JSON.Object(
      dict{
        "interface": JSON.String(interface),
        "operation": JSON.String(operation),
        "input": input,
      },
    )
    // A call a certificate makes is a Sign1 of its CBOR in either form, fhg6w, and the answer is in
    // the form asked.
    let body = switch (as_, chain) {
    | (None, _) =>
      switch form {
      | Run.Json => Ok((media(form), Web.utf8(JSON.stringify(call))))
      | Run.Cbor => callCbor(interface, call)->Result.map(bytes => (media(form), bytes))
      }
    | (Some(name), Some(chain)) =>
      switch chain.components->Dict.get(name) {
      | None => Error(`no certificate of ${name} in the run's chain`)
      | Some(holder) =>
        callCbor(interface, call)->Result.map(payload => (
          media(Cbor),
          sign(
            ~by=holder.keys,
            ~kind=Call,
            ~unprotected=[(Cbor.Integer(kcwt), Cbor.Bytes(holder.certificate))],
            payload,
          ),
        ))
      }
    | (Some(name), None) => Error(`no chain the run made to sign as ${name}`)
    }
    switch body {
    | Error(why) => Error(why)
    | Ok((contentType, body)) =>
      let name = Generated.outputs->Dict.get(`${interface}/${operation}`)
      switch name {
      | None => Error(`no operation ${operation} of ${interface}`)
      | Some(name) =>
        (
          await post(
            `${base}/${interface}/${operation}`,
            ~headers=Dict.fromArray(
              [
                ("content-type", contentType),
                ("accept", media(form)),
                ...token->Option.mapOr([], token => [("authorization", `Bearer ${token}`)]),
              ],
            ),
            ~body=Some(body),
          )
        )->Result.map(((status, contentType, bytes)) =>
          answerOf(~name, ~form, status, contentType, bytes)
        )
      }
    }
  }
  let send = async (~to, ~export, ~key, ~body) => {
    let url = switch key {
    | Some(key) => `${to}/${key}/${export}`
    | None => `${to}/${export}`
    }

    (
      await post(
        url,
        ~headers=dict{"content-type": "application/json", "accept": "application/json"},
        ~body=body->Option.map(body => Web.utf8(JSON.stringify(body))),
      )
    )->Result.map(((status, _, bytes)) =>
      // An export answers in its app's own WIT, and the platform's refusal as an answer's error.
      switch parsed(bytes) {
      | Error(why) => noAnswer(status, why)
      | Ok(json) =>
        switch Contracts.Answer.fromJson(json, data => Ok(data)) {
        | Ok(Error(error)) => failed(error)
        | Ok(Success(_)) | Error(_) =>
          status >= 200 && status < 300
            ? Run.Answered(json)
            : noAnswer(status, JSON.stringify(json))
        }
      }
    )
  }
  let target: Run.target = {
    call,
    send,
    given: async (~interface as _, _) => Error(
      Filling.Unoffered("a case's given, set up through the contracts above the implementation"),
    ),
    lose: async _ => Error(
      Filling.Unoffered("losing copies, a fault the implementation lets the runner cause"),
    ),
    bound: name => bounds->Dict.get(name),
    fixture: _ => None,
    signed: (bytes, record) => verified(chain, bytes, record),
    now: Date.now,
    wait: Web.sleep,
  }
  target
}
