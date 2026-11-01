module Declared = Envelope.Contracts.AppIngress

/** A declared mount already held by another app of its organization, RFC oomwh. */
exception ScopeHeld(string)

/** What `pick` reads of each declaration, sorted, each once. */
let declared = (ingress, pick) =>
  ingress
  ->Option.getOr([])
  ->Array.filterMap(pick)
  ->Array.toSorted(String.compare)
  ->Array.reduce([], (all, name) => {
    if all->Array.at(-1) != Some(name) {
      all->Array.push(name)
    }
    all
  })

let domains = ingress =>
  ingress->declared((i: Declared.t) =>
    switch i {
    | Domain({domain}) => Some(domain)
    | Mount(_) | Binding => None
    }
  )

let scopes = ingress =>
  ingress->declared((i: Declared.t) =>
    switch i {
    | Mount({scope}) => Some(scope)
    | Domain(_) | Binding => None
    }
  )

let validDomain = domain => {
  let name = domain->String.startsWith("*.") ? domain->String.slice(~start=2) : domain
  let labels = name->String.split(".")
  String.length(domain) <= 253 &&
  labels->Array.length >= 2 &&
  !(/^[0-9]+$/->RegExp.test(labels->Array.at(-1)->Option.getOr(""))) &&
  labels->Array.every(label => /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/->RegExp.test(label))
}

let invalid = ingress => domains(ingress)->Array.find(domain => !validDomain(domain))

// RFC vr5lw has a scope written as a label is, never one the platform reserves.
let reservedScopes = ["compute", "storage", "database"]

let validScope = scope =>
  /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/->RegExp.test(scope) &&
    !(reservedScopes->Array.includes(scope))

let invalidScope = ingress => scopes(ingress)->Array.find(scope => !validScope(scope))

let toJson = ingress => JSON.Array(ingress->Array.map(Declared.toJson))
let ofJson = json =>
  json
  ->JSON.Decode.array
  ->Option.getOrThrow
  ->Array.map(i => Declared.fromJson(i)->Result.getOrThrow)
let toText = ingress => JSON.stringify(toJson(ingress))
let ofText = text => ofJson(JSON.parseOrThrow(text))

let heldAt = async (objects: Objects.t, name) =>
  switch await objects.read(name) {
  | Ok(Some(bytes)) => JSON.parseOrThrow(Web.fromUtf8(bytes))->JSON.Decode.float
  | Ok(None) => None
  | Error(why) => JsError.throwWithMessage(why)
  }

let domainOfObjects = (objects, domain) => heldAt(objects, `state/domains/${domain}`)

let conflict = async (objects, ~app, ~ingress) => {
  let domains = domains(ingress)
  let holders = await Promise.all(domains->Array.map(domain => domainOfObjects(objects, domain)))
  domains->Array.findWithIndex((_, i) =>
    holders->Array.getUnsafe(i)->Option.mapOr(false, held => held != app)
  )
}

let replaceObjects = async (objects: Objects.t, ~app, ~before, ~after) => {
  let held = result =>
    switch result {
    | Ok() => ()
    | Error(why) => JsError.throwWithMessage(why)
    }
  let old = domains(before)
  for i in 0 to old->Array.length - 1 {
    let domain = old->Array.getUnsafe(i)
    held(await objects.delete(`state/domains/${domain}`))
  }
  let next = domains(after)
  for i in 0 to next->Array.length - 1 {
    let domain = next->Array.getUnsafe(i)
    held(await objects.write(`state/domains/${domain}`, Web.utf8(JSON.stringify(Number(app)))))
  }
}

let scopeAt = (~organization, scope) => `state/scopes/${Float.toString(organization)}/${scope}`

let scopeConflict = async (objects, ~organization, ~app, ~ingress) => {
  let scopes = scopes(ingress)
  let holders = await Promise.all(
    scopes->Array.map(scope => heldAt(objects, scopeAt(~organization, scope))),
  )
  scopes->Array.findWithIndex((_, i) =>
    holders->Array.getUnsafe(i)->Option.mapOr(false, held => held != app)
  )
}

let unmountObjects = async (objects: Objects.t, ~organization, ~ingress) => {
  let old = scopes(ingress)
  for i in 0 to old->Array.length - 1 {
    switch await objects.delete(scopeAt(~organization, old->Array.getUnsafe(i))) {
    | Ok() => ()
    | Error(why) => JsError.throwWithMessage(why)
    }
  }
}

let mountObjects = async (objects: Objects.t, ~organization, ~app, ~ingress) => {
  let next = scopes(ingress)
  for i in 0 to next->Array.length - 1 {
    switch await objects.write(
      scopeAt(~organization, next->Array.getUnsafe(i)),
      Web.utf8(JSON.stringify(Number(app))),
    ) {
    | Ok() => ()
    | Error(why) => JsError.throwWithMessage(why)
    }
  }
}
