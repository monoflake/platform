module Declared = Envelope.Contracts.AppIngress

let domains = ingress =>
  ingress
  ->Option.getOr([])
  ->Array.filterMap((i: Declared.t) =>
    switch i {
    | Domain({domain}) => Some(domain)
    | Mount(_) | Binding => None
    }
  )
  ->Array.toSorted(String.compare)
  ->Array.reduce([], (all, domain) => {
    if all->Array.at(-1) != Some(domain) {
      all->Array.push(domain)
    }
    all
  })

let validDomain = domain => {
  let name = domain->String.startsWith("*.") ? domain->String.slice(~start=2) : domain
  let labels = name->String.split(".")
  String.length(domain) <= 253 &&
  labels->Array.length >= 2 &&
  !(/^[0-9]+$/->RegExp.test(labels->Array.at(-1)->Option.getOr(""))) &&
  labels->Array.every(label => /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/->RegExp.test(label))
}

let invalid = ingress => domains(ingress)->Array.find(domain => !validDomain(domain))

let toJson = ingress => JSON.Array(ingress->Array.map(Declared.toJson))
let ofJson = json =>
  json
  ->JSON.Decode.array
  ->Option.getOrThrow
  ->Array.map(i => Declared.fromJson(i)->Result.getOrThrow)
let toText = ingress => JSON.stringify(toJson(ingress))
let ofText = text => ofJson(JSON.parseOrThrow(text))

let domainOfObjects = async (objects: Objects.t, domain) =>
  switch await objects.read(`state/domains/${domain}`) {
  | Ok(Some(bytes)) => JSON.parseOrThrow(Web.fromUtf8(bytes))->JSON.Decode.float
  | Ok(None) => None
  | Error(why) => JsError.throwWithMessage(why)
  }

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
