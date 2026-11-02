/**
 * The samples in `tests/`, data any language reads, held to the contracts they sample, RFC vr5lw.
 * Every operation and reason of a sampled interface must be sampled.
 */
open Base
include Conforms

/** Every `.json` beneath a directory of the repository, by its path. */
let rec files = path => {
  let at = urlIn(`${path}/`, root)
  existsSync(at)
    ? entries(at, {withFileTypes: true})->Array.flatMap(e => {
        let inner = `${path}/${e->entryName}`
        e->isDirectory ? files(inner) : inner->String.endsWith(".json") ? [inner] : []
      })
    : []
}

let read = path => JSON.parseOrThrow(readFileSync(urlIn(path, root)))

let items = j => list(j)->Option.getOr([])

/**
 * The capacity a case of an interface is `given`, its own kind's and a container for what is
 * deployed.
 */
let capacityOf = name => name == "deployments" ? "container" : name

/** The products' interfaces, whose cases are given configuration rather than capacity. */
let products = [Buckets.interface_.name, Generations.interface_.name]

/**
 * The platform half's roles' contracts, whose cases are given what the role holds of the one
 * organization a case is about, a team writing its own holding them to these, 7xpd3.
 */
let roles = [Authorities.interface_.name, Directories.interface_.name, Authorities.notices.name]

/**
 * What a role's case is given, the authority's generation, status, allowance and loans and whether
 * its scope was opened. Unset, the organization is open, active and unbounded.
 */
let roleGiven = [
  Subset.optional("generation", 1, Prim(#uint53)),
  Subset.optional("status", 2, Type("scope-status")),
  Subset.optional("allowance", 3, Map(Type("allowance-value"))),
  Subset.optional("loans", 4, List(Type("authority-loan"))),
  Subset.optional("opened", 5, Prim(#bool)),
]

/** The components' interfaces, beneath the products, whose cases are given what they read. */
let components = [
  Blobs.interface_.name,
  Capabilities.interface_.name,
  Runs.interface_.name,
  Frames.interface_.name,
]

/**
 * What a product's case is given before its first step, the records changed first, a store's room,
 * its builds and its allowance.
 */
let productGiven = [
  Subset.optional("records", 1, List(Type("change-item"))),
  Subset.optional("room", 2, Prim(#uint53)),
  Subset.optional("builds", 3, Map(Type("manifest"))),
  Subset.optional("allowance", 4, Map(Type("allowance-value"))),
]

/**
 * What a component's case is given before its first step, a store's room, its bundle's issuer
 * section, fixtures and sandboxes. A step may be called `as` a component, b8f35.
 */
let componentGiven = [
  Subset.optional("room", 1, Prim(#uint53)),
  Subset.optional("issuer", 2, Type("bundle-issuer")),
  Subset.optional("deployed", 3, List(Prim(#string))),
  Subset.optional("sandboxes", 4, List(Type("sandbox"))),
]

/** How a fixture is served, as built, under a hash not its own, or from where nothing answers. */
let served = ["as_built", "hash_mismatched", "unfetchable"]

/** What every case begins with captured, the one organization a run is about, 8j7b0. */
let capturedFirst = ["organization"]

/**
 * A case's marker, `network` where it needs the network or `tunnel` where it binds by a tunnel,
 * true or false, each case so marked skipped by the runner unless told otherwise, p8e8k and 8j7b0.
 */
let marked = (found, c, at, name) =>
  switch (c->member(name), truth(c->member(name))) {
  | (None, _) | (Some(_), Some(_)) => ()
  | (Some(_), None) => found->Array.push(`${at}: ${name}, true or false`)
  }

/**
 * A step's `as`, a component calling a component, or the operator calling an operation whose
 * callers the model declares include it, 6x8su and 8j7b0.
 */
let caller = (found, ~interface, ~operation: Subset.operation, st, at) =>
  switch (st->member("as"), text(st->member("as"))) {
  | (None, _) => ()
  | (Some(_), Some(who))
    if components->Array.includes(interface) && Components.components->Dict.get(who) != None => ()
  | (Some(_), Some("operator")) if operation.callers->Array.includes(#operator) =>
    if st->member("bearer") != None {
      found->Array.push(`${at}: as the operator and a bearer at once`)
    }
  | (Some(_), Some("operator")) =>
    found->Array.push(`${at}: as the operator, on ${operation.name}, which is not the operator's`)
  | (Some(_), _) =>
    found->Array.push(`${at}: as, a component to a component or the operator to its own operation`)
  }

/**
 * A case binding by a tunnel carries `"tunnel": true`, so the runner binds none unless told, since
 * a tunnel bind against a control not local makes a real tunnel, 8j7b0.
 */
let tunneling = (found, ~interface, c, at) => {
  let binds = items(c->member("steps"))->Array.some(st =>
    text(st->member("call")) == Some("bind") &&
      st
      ->member("input")
      ->Option.flatMap(i => i->member("reach"))
      ->Option.flatMap(r => text(r->member("name"))) == Some("tunnel")
  )
  if interface == Bindings.interface_.name && binds && truth(c->member("tunnel")) != Some(true) {
    found->Array.push(`${at}: binds by a tunnel, which only a case marked tunnel true may`)
  }
}

/** A step's bearer, `{"$use": name}` alone, the name captured by a step before, 8j7b0. */
let bearer = (s: scope, st, at) =>
  switch st->member("bearer")->Option.map(placeholder) {
  | None => ()
  | Some(Some(("$use", v))) =>
    switch v->JSON.Decode.string {
    | Some(n) if capturedFirst->Array.includes(n) =>
      s.found->Array.push(`${at}: bearer uses ${n}, which is no binding's token`)
    | Some(n) if s.captured->Set.has(n) => ()
    | Some(n) => s.found->Array.push(`${at}: bearer uses ${n}, captured by no step before`)
    | None => s.found->Array.push(`${at}: bearer, {"$use": name} alone`)
    }
  | Some(Some(_) | None) => s.found->Array.push(`${at}: bearer, {"$use": name} alone`)
  }

/** The checkers a property names, each written in the runner, never in a sample. */
let checkers = ["single_instance", "read_after_write"]

let run = () => {
  let found = []
  let called = Set.make()
  let sampled = Set.make()
  let sent = ref(false)
  let deployments = Contracts.interfaces->Array.find(i => i.name == "deployments")
  // A fixture, `tests/fixtures/{name}/fixture.json`, an app deployed by samples and built by the
  // runner.
  let fixtures = Dict.make()
  let fixtureFiles = files("tests/fixtures")
  fixtureFiles->Array.forEach(path => {
    let parts = path->String.split("/")
    switch parts {
    | ["tests", "fixtures", name, "fixture.json"] => fixtures->Dict.set(name, read(path))
    | _ => found->Array.push(`${path}: a fixture is tests/fixtures/{name}/fixture.json alone`)
    }
  })
  let forms = switch declared->Dict.get("deployment-form") {
  | Some({def: Enum({choices})}) => choices->Array.map(c => c.name)
  | Some({def: Record(_) | Union(_) | Flags(_)}) | None => []
  }
  fixtures->Dict.forEachWithKey((f, name) => {
    let at = `tests/fixtures/${name}`
    if text(f->member("description")) == None {
      found->Array.push(`${at}: no description`)
    }
    switch (f->member("of"), text(f->member("of"))) {
    | (None, _) =>
      switch text(f->member("form")) {
      | Some(form) if forms->Array.includes(form) => ()
      | _ => found->Array.push(`${at}: no form of deployment-form`)
      }
      switch list(f->member("exports")) {
      | Some(e) if e != [] && e->Array.every(x => x->JSON.Decode.string != None) => ()
      | _ => found->Array.push(`${at}: no exports`)
      }
    | (Some(_), Some(base)) =>
      if fixtures->Dict.get(base) == None {
        found->Array.push(`${at}: of ${base}, no fixture`)
      }
    | (Some(_), None) => found->Array.push(`${at}: of names a fixture`)
    }
    if f->member("instance") != None && truth(f->member("instance")) == None {
      found->Array.push(`${at}: instance is yes or no`)
    }
    switch (f->member("served"), text(f->member("served"))) {
    | (None, _) => ()
    | (Some(_), Some(x)) if served->Array.includes(x) => ()
    | (Some(_), _) => found->Array.push(`${at}: served, none of ${served->Array.join(", ")}`)
    }
    switch f->member("padded") {
    | None => ()
    | Some(p) =>
      switch (text(p->member("bound")), numeric(p->member("plus"))) {
      | (Some(b), Some(n)) if isInteger(n, 0., 1e9) =>
        if !(deployments->Option.flatMap(d => d.declared)->Option.getOr([])->Array.includes(b)) {
          found->Array.push(`${at}: padded past ${b}, no bound deployments declares`)
        }
      | _ => found->Array.push(`${at}: padded is a bound and how many past it`)
      }
    }
  })
  let formOf = name => {
    let rec go = (n, depth) =>
      switch fixtures->Dict.get(n) {
      | Some(f) if depth < 4 =>
        switch (text(f->member("form")), text(f->member("of"))) {
        | (Some(form), _) => Some(form)
        | (None, Some(b)) => go(b, depth + 1)
        | (None, None) => None
        }
      | _ => None
      }
    go(name, 0)
  }
  // A reason a case expects, its operation's own or every operation's, held to the failure it is.
  let expectFailure = (at, reasons: array<Subset.reason>, e, key) =>
    switch (text(e->member("failure")), text(e->member("reason"))) {
    | (Some(failure), Some(reason)) =>
      switch reasons->Array.find(r => r.name == reason) {
      | Some(r) =>
        if (r.failure :> string) != failure {
          found->Array.push(`${at}: ${reason} is ${(r.failure :> string)}, not ${failure}`)
        }
        sampled->Set.add(`${key}.${reason}`)
      | None => found->Array.push(`${at}: ${reason}, no reason here`)
      }
    | _ => found->Array.push(`${at}: expects an output, or a failure and its reason`)
    }
  let behavior = Array.concatMany(
    files("tests/kinds"),
    [files("tests/products"), files("tests/components")],
  )
  behavior->Array.forEach(path => {
    let j = read(path)
    switch text(j->member("interface")) {
    | Some(name) =>
      switch Contracts.interfaces->Array.find(i => i.name == name) {
      | None => found->Array.push(`${path}: no interface ${name}`)
      | Some(i) =>
        sampled->Set.add(name)
        items(j->member("cases"))->Array.forEachWithIndex((c, n) => {
          let at = `${path}#${int(n)}`
          let s = {
            found,
            captured: Set.fromArray(capturedFirst),
            bounds: i.bounds->Option.getOr(dict{}),
            declared: i.declared->Option.getOr([]),
            fixtures: fixtures->Dict.keysToArray,
          }
          if text(c->member("description")) == None {
            found->Array.push(`${at}: no description`)
          }
          ["network", "tunnel"]->Array.forEach(name => marked(found, c, at, name))
          tunneling(found, ~interface=name, c, at)
          // What the runner holds for the case before its first step, as capacity of its kind.
          switch c->member("given") {
          | None => ()
          | Some(g) if products->Array.includes(name) =>
            switch g->JSON.Decode.object {
            | Some(d) => record(s, productGiven, d, [], Input, `${at}.given`)
            | None => found->Array.push(`${at}: given, no object`)
            }
          | Some(g) if roles->Array.includes(name) =>
            switch g->JSON.Decode.object {
            | Some(d) => record(s, roleGiven, d, [], Input, `${at}.given`)
            | None => found->Array.push(`${at}: given, no object`)
            }
          | Some(g) if components->Array.includes(name) =>
            switch g->JSON.Decode.object {
            | Some(d) =>
              record(s, componentGiven, d, [], Input, `${at}.given`)
              list(d->Dict.get("deployed"))
              ->Option.getOr([])
              ->Array.filterMap(JSON.Decode.string)
              ->Array.forEach(
                f =>
                  if !(s.fixtures->Array.includes(f)) {
                    found->Array.push(`${at}.given: ${f}, no fixture in tests/fixtures/`)
                  },
              )
            | None => found->Array.push(`${at}: given, no object`)
            }
          | Some(g) =>
            switch declared->Dict.get("management-capacity") {
            | Some({def: Union({cases})}) =>
              switch (cases->Array.find(x => x.name == capacityOf(name)), g->JSON.Decode.object) {
              | (Some(k), Some(d)) => record(s, k.fields, d, [], Input, `${at}.given`)
              | _ => found->Array.push(`${at}: given, which ${name} holds no capacity of`)
              }
            | Some({def: Record(_) | Enum(_) | Flags(_)}) | None => ()
            }
          }
          // The copies a database's case is held on, which a step may then lose, vuanj.
          let copies = switch (c->member("copies"), numeric(c->member("copies"))) {
          | (None, _) => None
          | (Some(_), Some(n))
            if name == "database" && isInteger(n, 1., Int.toFloat(Database.copiesMost)) =>
            Some(n)
          | (Some(_), _) =>
            found->Array.push(
              `${at}: copies, from 1 to ${int(Database.copiesMost)} and a database's alone`,
            )
            None
          }
          let lost = ref(0.)
          let steps = items(c->member("steps"))
          if steps == [] {
            found->Array.push(`${at}: no steps`)
          }
          steps->Array.forEachWithIndex(
            (st, k) => {
              let at = `${at}.${int(k)}`
              // A step `within` some milliseconds is called again until it is answered as expected.
              switch (st->member("within"), numeric(st->member("within"))) {
              | (None, _) => ()
              | (Some(_), Some(ms)) if isInteger(ms, 1., 3600000.) => ()
              | (Some(_), _) => found->Array.push(`${at}: within, no milliseconds up to an hour`)
              }
              let expect = st->member("expect")
              let call = st->member("call")
              let send = st->member("send")
              switch (text(call), call, object(send), send) {
              | (Some(call), _, _, None) =>
                switch i.operations->Array.find(o => o.name == call) {
                | None => found->Array.push(`${at}: ${call}, no operation of ${name}`)
                | Some(o) =>
                  called->Set.add(`${name}.${call}`)
                  caller(found, ~interface=name, ~operation=o, st, at)
                  bearer(s, st, at)
                  // A fixture's version, form and artifact are the runner's to write, where a step
                  // writes none.
                  let fixture = st->member("fixture")
                  let input = switch (fixture, text(fixture), st->member("input")) {
                  | (None, _, Some(x)) => x
                  | (None, _, None) => JSON.Null
                  | (Some(_), Some(f), x) =>
                    let d = switch object(x) {
                    | Some(d) => d->Dict.copy
                    | None => Dict.make()
                    }
                    switch formOf(f) {
                    | None => found->Array.push(`${at}: fixture ${f}, none in tests/fixtures/`)
                    | Some(form) =>
                      switch text(d->Dict.get("form")) {
                      | Some(given) if given != form =>
                        found->Array.push(`${at}: form ${given}, yet ${f} is ${form}`)
                      | _ => ()
                      }
                      let zeros = String.repeat("0", 64)
                      [
                        ("version", JSON.String(zeros)),
                        ("form", String(form)),
                        ("artifact", Object(dict{"address": String(f), "hash": String(zeros)})),
                      ]->Array.forEach(
                        ((k, v)) =>
                          if d->Dict.get(k) == None {
                            d->Dict.set(k, v)
                          },
                      )
                    }
                    Object(d)
                  | (Some(_), None, _) =>
                    found->Array.push(`${at}: fixture names one`)
                    JSON.Null
                  }
                  conforms(s, Type(o.input), input, Input, `${at}.input`)
                  switch expect {
                  | Some(e) =>
                    switch e->member("output") {
                    | Some(out) if e->member("failure") == None =>
                      conforms(s, Type(o.output), out, Expected, `${at}.output`)
                    | _ =>
                      expectFailure(at, Array.concat(o.reasons, Calls.common), e, `${name}.${call}`)
                    }
                  | None => found->Array.push(`${at}: expects nothing`)
                  }
                }
              // A call to what is deployed, held to the shape of its app's own WIT and never a
              // contract's.
              | (None, None, Some(d), _) =>
                if name != "deployments" {
                  found->Array.push(`${at}: sends to what ${name} deploys not`)
                }
                sent := true
                switch d->Dict.get("to") {
                | Some(x) if x->JSON.Decode.string != None => ()
                | Some(x) =>
                  switch placeholder(x) {
                  | Some(("$use", v))
                    if v->JSON.Decode.string->Option.mapOr(false, n => s.captured->Set.has(n)) => ()
                  | _ => found->Array.push(`${at}: sends to no address captured`)
                  }
                | None => found->Array.push(`${at}: sends to nowhere`)
                }
                switch text(d->Dict.get("export")) {
                | Some(e) if e != "" => ()
                | _ => found->Array.push(`${at}: sends to no export`)
                }
                if d->Dict.get("key") != None && text(d->Dict.get("key")) == None {
                  found->Array.push(`${at}: a key is text`)
                }
                d
                ->Dict.keysToArray
                ->Array.forEach(
                  k =>
                    if !(["to", "export", "key", "body"]->Array.includes(k)) {
                      found->Array.push(`${at}: ${k}, nothing a send holds`)
                    },
                )
                switch expect {
                | Some(e) =>
                  switch e->member("answer") {
                  | Some(_) if e->member("failure") == None => ()
                  | _ => expectFailure(at, Array.concat(Calls.calling, Calls.common), e, "calling")
                  }
                | None => found->Array.push(`${at}: expects nothing`)
                }
              // A step that loses some of the copies its case is held on, so a sample may ask of
              // fewer.
              | (None, None, None, None) if st->member("lose") != None =>
                switch (numeric(st->member("lose")), copies) {
                | (Some(k), Some(n)) if isInteger(k, 1., n -. lost.contents) =>
                  lost := lost.contents +. k
                | _ => found->Array.push(`${at}: lose, more copies than the case holds alive`)
                }
              // A step that only waits, so a sample may ask of a time past.
              | (None, None, None, None) if st->member("wait") != None =>
                switch numeric(st->member("wait")) {
                | Some(ms) if isInteger(ms, 1., 3600000.) => ()
                | _ => found->Array.push(`${at}: wait, no milliseconds up to an hour`)
                }
              | _ => found->Array.push(`${at}: calls nothing, or sends and calls at once`)
              }
            },
          )
        })
      }
    | _ => found->Array.push(`${path}: names no interface`)
    }
  })
  // An interface sampled is sampled whole, each operation called and each of its own reasons met.
  Contracts.interfaces->Array.forEach(i =>
    if sampled->Set.has(i.name) {
      i.operations->Array.forEach(o => {
        if !(called->Set.has(`${i.name}.${o.name}`)) {
          found->Array.push(`${i.name}.${o.name}: called by no sample`)
        }
        o.reasons->Array.forEach(
          r =>
            if !(sampled->Set.has(`${i.name}.${o.name}.${r.name}`)) {
              found->Array.push(`${i.name}.${o.name}: ${r.name} met by no sample`)
            },
        )
      })
    }
  )
  if sent.contents {
    Calls.calling->Array.forEach(r =>
      if !(sampled->Set.has(`calling.${r.name}`)) {
        found->Array.push(`a call: ${r.name} met by no sample`)
      }
    )
  }
  // A property is a checker of the runner's, the interfaces it is run on, and how hard.
  let properties = files("tests/properties")
  properties->Array.forEach(path => {
    let p = read(path)
    switch text(p->member("checker")) {
    | Some(c) if checkers->Array.includes(c) => ()
    | _ => found->Array.push(`${path}: no checker of ${checkers->Array.join(", ")}`)
    }
    switch list(p->member("interfaces")) {
    | Some(xs) if xs != [] =>
      xs->Array.forEach(x =>
        switch x->JSON.Decode.string {
        | Some(n) if Contracts.interfaces->Array.some(i => i.name == n) => ()
        | _ => found->Array.push(`${path}: an interface not declared`)
        }
      )
    | _ => found->Array.push(`${path}: run on no interface`)
    }
    switch (p->member("fixture"), text(p->member("fixture"))) {
    | (None, _) => ()
    | (Some(_), Some(f)) if fixtures->Dict.get(f) != None => ()
    | (Some(_), _) => found->Array.push(`${path}: a fixture not in tests/fixtures/`)
    }
    switch object(p->member("load")) {
    | Some(d)
      if d
      ->Dict.valuesToArray
      ->Array.every(v =>
        v->JSON.Decode.float->Option.mapOr(false, n => isInteger(n, 1., 1e6))
      ) => ()
    | _ => found->Array.push(`${path}: load, counts of what the checker runs`)
    }
  })
  // A codec sample is a value in JSON beside its CBOR; one refused fails as every reader must
  // refuse it.
  let codec = files("tests/codec")
  let pairs = ref(0)
  let refused = ref(0)
  codec->Array.forEach(path => {
    let j = read(path)
    let typed = (x, n, what) =>
      switch text(x->member("type")) {
      | Some(t) if declared->Dict.get(t) != None => Some(#type_(t))
      | Some(_) =>
        found->Array.push(`${path}: ${what} ${int(n)}, no type declared`)
        None
      | None =>
        switch text(x->member("interface"))->Option.flatMap(name =>
          Contracts.interfaces->Array.find(i => i.name == name)
        ) {
        | Some(i) => Some(#call(i))
        | None =>
          found->Array.push(`${path}: ${what} ${int(n)}, neither a type declared nor an interface`)
          None
        }
      }
    // A call, `contracts.json`'s `call`, its interface, an operation, the input it reads and the
    // capabilities it carries, fhg6w.
    let called = (s, i: Subset.interface_, json, at) =>
      switch json->JSON.Decode.object {
      | Some(d) =>
        let fail = why => s.found->Array.push(`${at}: ${why}`)
        if text(d->Dict.get("interface")) != Some(i.name) {
          fail(`a call of ${i.name} names another interface`)
        }
        switch text(d->Dict.get("operation"))->Option.flatMap(o =>
          i.operations->Array.find(x => x.name == o)
        ) {
        | Some(o) =>
          conforms(s, Type(o.input), d->Dict.get("input")->Option.getOr(Null), Codec, `${at}.input`)
        | None => fail(`no operation of ${i.name}`)
        }
        switch d->Dict.get("capabilities") {
        | None => ()
        | Some(c) => conforms(s, List(Prim(#bytes)), c, Codec, `${at}.capabilities`)
        }
        d
        ->Dict.keysToArray
        ->Array.forEach(k =>
          if !(["interface", "operation", "input", "capabilities"]->Array.includes(k)) {
            fail(`${k}, nothing a call holds`)
          }
        )
      | None => s.found->Array.push(`${at}: a call is an object`)
      }
    let held = (s, t, json, at) =>
      switch t {
      | #type_(t) => conforms(s, Type(t), json, Codec, at)
      | #call(i) => called(s, i, json, at)
      }
    items(j->member("samples"))->Array.forEachWithIndex((x, n) =>
      switch typed(x, n, "sample") {
      | Some(t) =>
        pairs := pairs.contents + 1
        let s = {found, captured: Set.make(), bounds: dict{}, declared: [], fixtures: []}
        held(s, t, x->member("json")->Option.getOr(Null), `${path}#${int(n)}`)
        switch text(x->member("cbor")) {
        | Some(h) if isHex(h) && h != "" => ()
        | _ => found->Array.push(`${path}#${int(n)}: no CBOR in lowercase hex`)
        }
      | None => ()
      }
    )
    items(j->member("refused"))->Array.forEachWithIndex((x, n) =>
      switch typed(x, n, "refused") {
      | Some(t) =>
        refused := refused.contents + 1
        let s = {found: [], captured: Set.make(), bounds: dict{}, declared: [], fixtures: []}
        held(s, t, x->member("json")->Option.getOr(Null), "")
        if s.found == [] {
          found->Array.push(`${path}: refused ${int(n)} is read, yet every reader must refuse it`)
        }
        if x->member("reason") != Some(String("malformed")) {
          found->Array.push(`${path}: refused ${int(n)}, refused for no reason but malformed`)
        }
      | None => ()
      }
    )
  })
  dimension(
    "Samples",
    "Does every sample in tests/ call what its contract declares, with what it parses, expecting what it can answer, and is every interface sampled sampled whole?",
    found,
    ~notes=[
      `fixtures: ${int(fixtures->Dict.keysToArray->Array.length)}; properties: ${int(
          properties->Array.length,
        )}`,
      `behavior: ${int(behavior->Array.length)} files; codec: ${int(pairs.contents)} pairs, ${int(
          refused.contents,
        )} refused`,
      `sampled: ${Contracts.interfaces
        ->Array.filter(i => sampled->Set.has(i.name))
        ->Array.map(i => i.name)
        ->orNone(", ")}; not yet: ${Contracts.interfaces
        ->Array.filter(i => !(sampled->Set.has(i.name)))
        ->Array.map(i => i.name)
        ->orNone(", ")}`,
    ],
    (),
  )
}
