/***
 * Every signed record verified, RFC b8f35, each by its chain to the root.
 */
module Cbor = Codec.Cbor
module Sign1 = Codec.Sign1

type kind =
  | Capability
  | Certificate
  | Account
  | Bundle
  | Authority
  | Directory
  | Call

let typ = kind =>
  switch kind {
  | Capability => "monoflake:capability:2"
  | Certificate => "monoflake:certificate:1"
  | Account => "monoflake:account:1"
  | Bundle => "monoflake:bundle:1"
  | Authority => "monoflake:authority:1"
  | Directory => "monoflake:directory:1"
  | Call => "monoflake:call:1"
  }

type trust = {root: Uint8Array.t, certificates: array<Uint8Array.t>, now: float}

type signer =
  | Root
  | Signed({role: string, scope: option<float>, sub: option<string>})

type rec refused =
  | Malformed(string)
  | Algorithm
  | Typ
  | Unknown
  | Signature
  | Role
  | Scope
  | Expired
  | Early
  | Above(refused)

type verified = {content: Cbor.value, signer: signer}

/** A certificate's role, by its code, `model/contracts/signed/signed.res`. */
module Role = {
  type t =
    | Intermediate
    | Issuer
    | Bundle
    | Account
    | Component
    | Authority
    | Organization

  let ofCode = code =>
    switch code {
    | 1n => Some(Intermediate)
    | 2n => Some(Issuer)
    | 3n => Some(Bundle)
    | 4n => Some(Account)
    | 5n => Some(Component)
    | 6n => Some(Authority)
    | 7n => Some(Organization)
    | _ => None
    }

  let name = role =>
    switch role {
    | Intermediate => "intermediate"
    | Issuer => "issuer"
    | Bundle => "bundle"
    | Account => "account"
    | Component => "component"
    | Authority => "authority"
    | Organization => "organization"
    }
}

/** COSE's labels, RFC 9052's 3.1 and RFC 9596, and the claims', RFCs 8392 and 8747, b8f35. */
let alg = 1
let kid = 4
let typLabel = 16
let kcwt = 13
let ed25519 = -19n
let sub = 2
let exp = 4
let iat = 6
let cnf = 8
let scope = -65537
let rights = -65539
let role = -65540
let bundleScope = 2

/** How far ahead of the caller's clock an `iat` may stand, in seconds. */
let skew = 60.

/** The largest integer a float holds exactly, a `uint53`'s bound. */
let uint53 = 9007199254740991n

let integerOf = (value: Cbor.value) =>
  switch value {
  | Integer(n) => Some(n)
  | Bytes(_)
  | Text(_)
  | Array(_)
  | Map(_)
  | Tag(_)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

let bytesOf = (value: Cbor.value) =>
  switch value {
  | Bytes(bytes) => Some(bytes)
  | Integer(_)
  | Text(_)
  | Array(_)
  | Map(_)
  | Tag(_)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

let textOf = (value: Cbor.value) =>
  switch value {
  | Text(text) => Some(text)
  | Integer(_)
  | Bytes(_)
  | Array(_)
  | Map(_)
  | Tag(_)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

let mapOf = (value: Cbor.value) =>
  switch value {
  | Map(pairs) => Some(pairs)
  | Integer(_)
  | Bytes(_)
  | Text(_)
  | Array(_)
  | Tag(_)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) =>
    None
  }

/** The value a map holds under an integer label. */
let find = (pairs: array<(Cbor.value, Cbor.value)>, label) => {
  let label = BigInt.fromInt(label)
  pairs
  ->Array.find(((key, _)) => integerOf(key) == Some(label))
  ->Option.map(((_, value)) => value)
}

/** Whether two byte strings are one. */
let same = (a, b) =>
  TypedArray.length(a) == TypedArray.length(b) &&
    a->TypedArray.everyWithIndex((byte, i) => b->TypedArray.get(i) == Some(byte))

/** A key's `kid`, the first 16 bytes of the BLAKE3 of its public key. */
let kidOf = key => Keys.Hash.plain(key)->TypedArray.slice(~start=0, ~end=16)

/** An unsigned integer a float holds exactly, under `label`, none where it is absent. */
let optionalUint = (pairs, label, name) =>
  switch pairs->find(label) {
  | None => Ok(None)
  | Some(value) =>
    switch integerOf(value) {
    | Some(n) if n >= 0n && n <= uint53 => Ok(Some(BigInt.toFloat(n)))
    | Some(_) | None => Error(`${name} is no unsigned integer`)
    }
  }

let uint = (pairs, label, name) =>
  switch optionalUint(pairs, label, name) {
  | Ok(Some(n)) => Ok(n)
  | Ok(None) => Error(`no ${name}`)
  | Error(why) => Error(why)
  }

let optionalText = (pairs, label, name) =>
  switch pairs->find(label) {
  | None => Ok(None)
  | Some(value) =>
    switch textOf(value) {
    | Some(text) => Ok(Some(text))
    | None => Error(`${name} is no text`)
    }
  }

let text = (pairs, label, name) =>
  switch optionalText(pairs, label, name) {
  | Ok(Some(text)) => Ok(text)
  | Ok(None) => Error(`no ${name}`)
  | Error(why) => Error(why)
  }

/** What carries `iat` and `exp`. */
type timed = {iat: float, exp: float}

/** What a certificate certifies, its key, its role, its scope where it holds one and its `sub`. */
type certified = {key: Uint8Array.t, role: Role.t, scope: option<float>, sub: option<string>}

/** What verifying reads of a record's content, beyond the content itself. */
type claims = {timed: option<timed>, scope: option<float>, certified: option<certified>}

let timedOf = pairs =>
  switch (uint(pairs, iat, "iat"), uint(pairs, exp, "exp")) {
  | (Ok(iat), Ok(exp)) => Ok({iat, exp})
  | (Error(why), _) | (_, Error(why)) => Error(why)
  }

/**
 * The Ed25519 key a `cnf` confirms as a COSE_Key, `kty` OKP, `crv` Ed25519 and `x` its 32 bytes.
 */
let keyOf = pairs =>
  switch pairs
  ->find(cnf)
  ->Option.flatMap(mapOf)
  ->Option.flatMap(c => c->find(1))
  ->Option.flatMap(mapOf) {
  | None => Error("no cnf holding a COSE_Key")
  | Some(key) =>
    switch (
      key->find(1)->Option.flatMap(integerOf),
      key->find(-1)->Option.flatMap(integerOf),
      key->find(-2)->Option.flatMap(bytesOf),
    ) {
    | (Some(1n), Some(6n), Some(x)) if TypedArray.length(x) == 32 => Ok(x)
    | (Some(_) | None, Some(_) | None, Some(_) | None) => Error("cnf's key is no Ed25519 key")
    }
  }

let certifiedOf = pairs =>
  switch (
    keyOf(pairs),
    pairs
    ->find(role)
    ->Option.flatMap(integerOf)
    ->Option.flatMap(Role.ofCode)
    ->Option.mapOr(Error("no role of a known code"), role => Ok(role)),
    optionalUint(pairs, scope, "scope"),
    optionalText(pairs, sub, "sub"),
  ) {
  | (Ok(key), Ok(role), Ok(scope), Ok(sub)) =>
    // A component's certificate names it, the table's "with its `sub`".
    switch (role, sub) {
    | (Component, None) => Error("a component's certificate without its sub")
    | (Component, Some(_))
    | (Intermediate | Issuer | Bundle | Account | Authority | Organization, _) =>
      Ok({key, role, scope, sub})
    }
  | (Error(why), _, _, _) | (_, Error(why), _, _) | (_, _, Error(why), _) | (_, _, _, Error(why)) =>
    Error(why)
  }

/** What a kind's content holds that verifying reads, the rest of it its reader's. */
let claimsOf = (kind, pairs) =>
  switch kind {
  | Capability =>
    switch (timedOf(pairs), uint(pairs, scope, "scope"), uint(pairs, rights, "rights")) {
    | (Ok(_), Ok(_), Ok(0.)) => Error("a capability granting no right")
    | (Ok(timed), Ok(scope), Ok(_)) => Ok({timed: Some(timed), scope: Some(scope), certified: None})
    | (Error(why), _, _) | (_, Error(why), _) | (_, _, Error(why)) => Error(why)
    }
  | Certificate =>
    switch (timedOf(pairs), certifiedOf(pairs)) {
    | (Ok(timed), Ok(certified)) =>
      Ok({timed: Some(timed), scope: certified.scope, certified: Some(certified)})
    | (Error(why), _) | (_, Error(why)) => Error(why)
    }
  | Account =>
    switch (timedOf(pairs), text(pairs, sub, "sub")) {
    | (Ok(timed), Ok(_)) => Ok({timed: Some(timed), scope: None, certified: None})
    | (Error(why), _) | (_, Error(why)) => Error(why)
    }
  | Bundle =>
    uint(pairs, bundleScope, "scope")->Result.map(scope => {
      timed: None,
      scope: Some(scope),
      certified: None,
    })
  | Authority | Directory | Call => Ok({timed: None, scope: None, certified: None})
  }

/** A record as it is read, before anything of it is checked. */
type read = {
  sign1: Sign1.t,
  payload: Uint8Array.t,
  alg: Cbor.value,
  kid: Uint8Array.t,
  typ: Cbor.value,
  kcwt: option<Uint8Array.t>,
  content: Cbor.value,
  claims: claims,
}

/** The protected header, `alg`, `kid` of 16 bytes and `typ`, and nothing else. */
let headerOf = protected =>
  switch Cbor.decodeDeterministic(protected)->Result.mapOr(None, mapOf) {
  | None => Error("a protected header no deterministic map")
  | Some(pairs) =>
    switch (pairs->find(alg), pairs->find(kid)->Option.flatMap(bytesOf), pairs->find(typLabel)) {
    | (Some(alg), Some(kid), Some(typ))
      if Array.length(pairs) == 3 && TypedArray.length(kid) == 16 =>
      Ok((alg, kid, typ))
    | (Some(_) | None, Some(_) | None, Some(_) | None) =>
      Error("a protected header not alg, a kid of 16 bytes and typ alone")
    }
  }

/** The unprotected header, empty but for a call's certificate in `kcwt` as it was signed. */
let kcwtOf = (kind, unprotected: array<(Cbor.value, Cbor.value)>) =>
  switch (kind, unprotected) {
  | (_, []) => Ok(None)
  | (Call, [_]) =>
    switch unprotected->find(kcwt)->Option.flatMap(bytesOf) {
    | Some(certificate) => Ok(Some(certificate))
    | None => Error("a call's unprotected header not its kcwt alone")
    }
  | (Call, _) => Error("a call's unprotected header not its kcwt alone")
  | (Capability | Certificate | Account | Bundle | Authority | Directory, _) =>
    Error("an unprotected header where none is written")
  }

let read = (kind, bytes) =>
  // The whole record is read deterministically first, as the one form it is kept and compared by.
  switch (Cbor.decodeDeterministic(bytes), Sign1.decode(bytes)) {
  | (Error(_), _) => Error("no deterministic CBOR")
  | (Ok(_), Error(_)) => Error("no Sign1")
  | (Ok(_), Ok((_, false))) => Error("a Sign1 not under tag 18")
  | (Ok(_), Ok((sign1, true))) =>
    switch (headerOf(sign1.protected), kcwtOf(kind, sign1.unprotected), sign1.payload) {
    | (Error(why), _, _) | (_, Error(why), _) => Error(why)
    | (Ok(_), Ok(_), None) => Error("a payload detached")
    | (Ok((alg, kid, typ)), Ok(kcwt), Some(payload)) =>
      switch Cbor.decodeDeterministic(payload) {
      | Error(_) => Error("a payload no deterministic CBOR")
      | Ok(content) =>
        switch mapOf(content) {
        | None => Error("a payload no map")
        | Some(pairs) =>
          claimsOf(kind, pairs)->Result.map(claims => {
            sign1,
            payload,
            alg,
            kid,
            typ,
            kcwt,
            content,
            claims,
          })
        }
      }
    }
  }

/** Who a `kid` names, the root or a certificate as it was signed with what it certifies. */
type found =
  | ByRoot
  | ByCertificate(Uint8Array.t, certified)

/**
 * Who a record's `kid` may name, a call's `kcwt` first, then the certificates given and then the
 * root.
 */
let candidatesOf = (trust, record) => {
  let given = switch record.kcwt {
  | Some(certificate) => [certificate]->Array.concat(trust.certificates)
  | None => trust.certificates
  }
  let certificates = given->Array.filterMap(bytes =>
    switch read(Certificate, bytes) {
    | Ok({claims: {certified: Some(certified)}}) if same(kidOf(certified.key), record.kid) =>
      Some(ByCertificate(bytes, certified))
    | Ok(_) | Error(_) => None
    }
  )
  same(kidOf(trust.root), record.kid) ? certificates->Array.concat([ByRoot]) : certificates
}

/** The roles a signer, the root where none, may certify, `signed.resi`'s table. */
let certifies = (by: option<Role.t>): array<Role.t> =>
  switch by {
  | None => [Intermediate]
  | Some(Intermediate) => [Authority]
  | Some(Authority) => [Organization, Issuer, Bundle, Account]
  | Some(Organization) => [Component]
  | Some(Issuer | Bundle | Account | Component) => []
  }

/** The kinds but a certificate a signer, the root where none, may sign, the same table. */
let signs = (by: option<Role.t>): array<kind> =>
  switch by {
  | None | Some(Intermediate) => []
  | Some(Authority) => [Authority, Directory]
  | Some(Organization) => [Call]
  | Some(Issuer) => [Capability]
  | Some(Bundle) => [Bundle]
  | Some(Account) => [Account]
  | Some(Component) => [Call]
  }

let may = (by, kind, claims) =>
  switch (kind, claims.certified) {
  | (Certificate, Some(certified)) => certifies(by)->Array.includes(certified.role)
  | (Certificate, None) => false
  | (Capability | Account | Bundle | Authority | Directory | Call, _) =>
    signs(by)->Array.includes(kind)
  }

/** Whether a signer holding a scope signed what holds the same, where its kind holds one. */
let within = (scope, kind, claims) =>
  switch (scope, kind) {
  | (None, _) => true
  | (Some(_), Capability | Certificate | Bundle) => claims.scope == scope
  | (Some(_), Account | Authority | Directory | Call) => true
  }

/** The first that verifies of `candidates`, or where none does, the first one's refusal. */
let rec first = (candidates, by, refused) =>
  switch candidates {
  | list{} => Error(refused)
  | list{candidate, ...rest} =>
    switch by(candidate) {
    | Ok(verified) => Ok(verified)
    | Error(_) => first(rest, by, refused)
    }
  }

let rec verify = (trust, kind, bytes) =>
  switch read(kind, bytes) {
  | Error(why) => Error(Malformed(why))
  | Ok(record) =>
    if integerOf(record.alg) != Some(ed25519) {
      Error(Algorithm)
    } else if textOf(record.typ) != Some(typ(kind)) {
      Error(Typ)
    } else {
      switch candidatesOf(trust, record)->List.fromArray {
      | list{} => Error(Unknown)
      | list{candidate, ...rest} =>
        switch signedBy(trust, kind, record, candidate) {
        | Ok(verified) => Ok(verified)
        | Error(refused) => first(rest, found => signedBy(trust, kind, record, found), refused)
        }
      }
    }
  }

/** The record verified as `found` signed it, its signature, its role, its scope, its times, and
 * the certificate above it. */
and signedBy = (trust, kind, record, found) => {
  let (key, by) = switch found {
  | ByRoot => (trust.root, None)
  | ByCertificate(_, certified) => (certified.key, Some(certified))
  }
  let message = Sign1.toBeSigned(
    ~protected=record.sign1.protected,
    ~aad=Uint8Array.fromLength(0),
    ~payload=record.payload,
  )
  let timed = record.claims.timed
  if !Ed25519.verify(~signature=record.sign1.signature, ~message, ~key) {
    Error(Signature)
  } else if !may(by->Option.map(c => c.role), kind, record.claims) {
    Error(Role)
  } else if !within(by->Option.flatMap(c => c.scope), kind, record.claims) {
    Error(Scope)
  } else if timed->Option.mapOr(false, t => trust.now >= t.exp) {
    Error(Expired)
  } else if timed->Option.mapOr(false, t => t.iat > trust.now +. skew) {
    Error(Early)
  } else {
    switch found {
    | ByRoot => Ok({content: record.content, signer: Root})
    | ByCertificate(certificate, certified) =>
      switch verify(trust, Certificate, certificate) {
      | Error(refused) => Error(Above(refused))
      | Ok(_) =>
        Ok({
          content: record.content,
          signer: Signed({
            role: Role.name(certified.role),
            scope: certified.scope,
            sub: certified.sub,
          }),
        })
      }
    }
  }
}
