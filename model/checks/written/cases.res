/**
 * The samples in `tests/`, RFC vr5lw: data alone, which any language reads, held here to the
 * contracts they sample. A behavior file is an interface's cases, each a list of steps -- an
 * operation called with an input, and its output or its failure expected; a codec file is values in
 * JSON beside their CBOR, and inputs every reader must refuse. A database's case may be held on
 * `copies`, and a step `lose` some of them. Every operation and every reason of an interface with
 * samples must be sampled.
 */
open Base

let declared = Dict.fromArray(Contracts.types->Array.map(t => (t.name, t)))

let base64urlText = /^[A-Za-z0-9_-]*$/
let hexText = /^([0-9a-f]{2})*$/
let hashText = /^[0-9a-f]{64}$/

let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

/** Base64url without padding, its unused last bits zero, fhg6w: one text a value. */
let isBase64url = s => {
  let n = String.length(s)
  let rest = mod(n, 4)
  base64urlText->RegExp.test(s) &&
  rest != 1 &&
  (rest == 0 || mod(alphabet->String.indexOf(s->String.charAt(n - 1)), rest == 2 ? 16 : 4) == 0)
}

/** The largest integer a JavaScript number holds exactly, either way. */
let safe = 9007199254740991.

let isInteger = (x, lo, hi) => Math.floor(x) == x && x >= lo && x <= hi

let isHex = s => hexText->RegExp.test(s)

/**
 * Where a value stands: in an input, in what is expected, or in a codec sample, read as a reader
 * would.
 */
type mode = Input | Expected | Codec

type scope = {
  found: array<string>,
  captured: Set.t<string>,
  bounds: dict<int>,
  declared: array<string>,
  /** The fixtures in `tests/fixtures/`, by name. */
  fixtures: array<string>,
}

let isContent = n => Contracts.contents->Array.some(c => c.content == n)

/** A sample's placeholder: an object of one key, `$`-led. */
let placeholder = (j: JSON.t) =>
  switch j->JSON.Decode.object->Option.map(Dict.toArray) {
  | Some([(k, v)]) if k->String.startsWith("$") => Some((k, v))
  | _ => None
  }

/** Every way a value fails its shape, as `at` names where; none is a value that conforms. */
let rec conforms = (s: scope, shape: Subset.shape, j: JSON.t, mode, at) => {
  let fail = why => s.found->Array.push(`${at}: ${why}`)
  switch placeholder(j) {
  | Some((k, v)) =>
    switch (k, mode, v->JSON.Decode.string) {
    | ("$any", Expected, _) => ()
    // A field that must be absent, since one a sample leaves out is passed over, p8e8k.
    | ("$absent", Expected, _) => ()
    | ("$capture", Expected, Some(n)) => s.captured->Set.add(n)
    // A moment so many milliseconds before the step is sent, where a time is asked.
    | ("$time", Input, _) =>
      if shape != Prim(#uint53) {
        fail("$time where no time is")
      }
      switch numeric(v->member("ago")) {
      | Some(n) if isInteger(n, 0., 9007199254740991.) => ()
      | _ => fail("$time takes how many milliseconds ago")
      }
    // A value captured before: given as it was, or, expected, the same as it was.
    | ("$use", Input | Expected, Some(n)) =>
      if !(s.captured->Set.has(n)) {
        fail(`uses ${n}, captured by no step before`)
      }
    // Bytes of a length, or a text its `start` led and spaces filled to a length, either a number or
    // a bound and how many past it: a bound of the interface's, or one each driver declares.
    | (("$bytes" | "$text") as k, Input | Expected, _) =>
      if shape != (k == "$bytes" ? Prim(#bytes) : Prim(#string)) {
        fail(`${k} where its kind of value is not`)
      }
      switch v->JSON.Decode.object {
      | Some(d) =>
        let start = d->Dict.get("start")
        if start != None && !(k == "$text" && text(start) != None) {
          fail(`${k} takes no start but a text's`)
        }
        let length = d->Dict.get("length")
        switch (numeric(length), object(length)) {
        | (Some(n), _) if isInteger(n, 0., 9007199254740991.) => ()
        | (_, Some(b)) =>
          switch (text(b->Dict.get("bound")), numeric(b->Dict.get("plus"))) {
          | (Some(name), Some(p)) if isInteger(p, -1e9, 1e9) =>
            if s.bounds->Dict.get(name) == None && !(s.declared->Array.includes(name)) {
              fail(`${k} past ${name}, no bound of its interface`)
            }
          | _ => fail(`${k}'s length is a bound and how many past it`)
          }
        | _ => fail(`${k} without a length`)
        }
      | None => fail(`${k} takes a length`)
      }
    // Bytes that are a signed record, its claims or its content as expected, vuanj.
    | ("$signed", Expected, _) =>
      if shape != Prim(#bytes) {
        fail("$signed where no bytes are")
      }
      switch Signed.signed->Array.find(r => Some(r.name) == text(v->member("record"))) {
      | Some(r) =>
        switch v->member("claims") {
        | Some(claims) => conforms(s, Type(r.content), claims, Expected, `${at}.claims`)
        | None => fail("$signed without its claims")
        }
      | None => fail("$signed names no signed record")
      }
    // The WAL frames a SQLite primary appends committing these statements in one transaction,
    // after every earlier `$frames` of its case, made by the runner, vuanj.
    | ("$frames", Input, _) =>
      if shape != Prim(#bytes) {
        fail("$frames where no bytes are")
      }
      switch list(v->member("writes")) {
      | Some(writes)
        if writes != [] && writes->Array.every(w => w->JSON.Decode.string != None) => ()
      | _ => fail("$frames takes the statements it writes")
      }
    // The hash of a fixture's code as it was built, its hosts holding it deployed.
    | ("$fixture", Input, Some(name)) =>
      if shape != Prim(#hash) {
        fail("$fixture where no hash is")
      }
      if !(s.fixtures->Array.includes(name)) {
        fail(`$fixture ${name}, none in tests/fixtures/`)
      }
    | (k, Input | Expected | Codec, _) => fail(`placeholder ${k}, not taken here`)
    }
  | None =>
    let n = j->JSON.Decode.float
    let t = j->JSON.Decode.string
    let within = (lo, hi) => n->Option.mapOr(false, n => isInteger(n, lo, hi))
    switch shape {
    | Prim(p) =>
      let fits = switch p {
      | #bool => j->JSON.Decode.bool != None
      | #string => t != None
      | #float64 => n != None
      | #int32 => within(-2147483648., 2147483647.)
      | #uint32 => within(0., 4294967295.)
      | #uint53 => within(0., 9007199254740991.)
      | #int53 => within(-.safe, safe)
      | #bytes | #secret => t->Option.mapOr(false, isBase64url)
      | #hash => t->Option.mapOr(false, t => hashText->RegExp.test(t))
      }
      if !fits {
        fail(`no ${(p :> string)}`)
      }
    // An id sent may be a handle, resolved as it is received, v7v3w; one given back never is.
    | Id(kind) =>
      if !(within(0., 4294967295.) || (mode == Input && t != None)) {
        fail(`no id of ${kind}`)
      }
    | Across(_, kind) =>
      if !within(0., 4294967295.) {
        fail(`no id of ${kind}`)
      }
    | List(inner) =>
      switch j->JSON.Decode.array {
      | Some(items) =>
        items->Array.forEachWithIndex((v, i) => conforms(s, inner, v, mode, `${at}[${int(i)}]`))
      | None => fail("no list")
      }
    | Map(inner) =>
      switch j->JSON.Decode.object {
      | Some(d) => d->Dict.forEachWithKey((v, k) => conforms(s, inner, v, mode, `${at}.${k}`))
      | None => fail("no map")
      }
    | Type(name) =>
      switch declared->Dict.get(name) {
      | None => fail(`no type ${name}`)
      | Some({def}) =>
        switch def {
        | Record(fields) =>
          switch j->JSON.Decode.object {
          | Some(d) =>
            let fields = isContent(name) ? Array.concat([Subset.description], fields) : fields
            record(s, fields, d, [], mode, at)
          | None => fail(`no object, as ${name} is`)
          }
        | Enum({choices}) =>
          switch t {
          | Some(c) =>
            if !(choices->Array.some(x => x.name == c)) {
              fail(`${c}, no choice of ${name}`)
            }
          | None => fail(`no name of ${name}`)
          }
        | Union({tag, cases}) =>
          switch j->JSON.Decode.object {
          | Some(d) =>
            switch text(d->Dict.get(tag)) {
            | Some(c) =>
              switch cases->Array.find(x => x.name == c) {
              | Some(case) => record(s, case.fields, d, [tag], mode, at)
              | None => fail(`${c}, no case of ${name}`)
              }
            | None => fail(`no ${tag}, which names ${name}'s case`)
            }
          | None => fail(`no object, as ${name} is`)
          }
        | Flags(choices) =>
          switch j->JSON.Decode.array {
          | Some(xs) =>
            let seen = Set.make()
            xs->Array.forEach(x =>
              switch x->JSON.Decode.string {
              | Some(c) if choices->Array.some(k => k.name == c) && !(seen->Set.has(c)) =>
                seen->Set.add(c)
              | Some(c) => fail(`${c}, no flag of ${name} or one twice`)
              | None => fail(`a flag of ${name} is its name`)
              }
            )
          | None => fail(`no array of ${name}'s names`)
          }
        }
      }
    }
  }
}
/** A record's fields: each required one present, each conforming; a field unknown is a mistake in
 * a sample written, and passed over by a reader, as an optional field added later must be. */
and record = (s, fields: array<Subset.field>, d, known, mode, at) => {
  fields->Array.forEach(f =>
    switch d->Dict.get(f.name) {
    | Some(v) => conforms(s, f.shape, v, mode, `${at}.${f.name}`)
    | None =>
      if !(f.optional->Option.getOr(false)) {
        s.found->Array.push(`${at}: no ${f.name}`)
      }
    }
  )
  if mode != Codec {
    d
    ->Dict.keysToArray
    ->Array.forEach(k =>
      if !(known->Array.includes(k)) && !(fields->Array.some(f => f.name == k)) {
        s.found->Array.push(`${at}: ${k}, no field of it`)
      }
    )
  }
}

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
 * The capacity a case of an interface is `given`: its own kind's, and a container for what is
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
 * What a role's case is given: the authority's generation for the organization, its status,
 * allowance and loans; and whether its scope was ever opened, a directory's row being never
 * removed, so a scope not opened is the one not found. Unset, the organization is open and active,
 * its allowance without bounds and nothing lent.
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
 * What a product's case is given before its first step: the records changed first, through its
 * organization's control, each with its handle; the room of the one store the runner binds, at a
 * bucket's default levels, `best_effort`, `persistent` and no custody; the builds its builder keeps,
 * each manifest by its version's hash; and the allowance its authority gives it.
 */
let productGiven = [
  Subset.optional("records", 1, List(Type("change-item"))),
  Subset.optional("room", 2, Prim(#uint53)),
  Subset.optional("builds", 3, Map(Type("manifest"))),
  Subset.optional("allowance", 4, Map(Type("allowance-value"))),
]

/**
 * What a component's case is given before its first step: the room of the one store its scope's
 * backing holds, at a bucket's default levels; its organization's bundle's issuer section; the
 * fixtures its hosts hold deployed, by name; and the sandboxes its hosts offer, both unless set. A step may be called `as` a component, by its name in
 * the model, the runner signing the call by a certificate saying so, b8f35.
 */
let componentGiven = [
  Subset.optional("room", 1, Prim(#uint53)),
  Subset.optional("issuer", 2, Type("bundle-issuer")),
  Subset.optional("deployed", 3, List(Prim(#string))),
  Subset.optional("sandboxes", 4, List(Type("sandbox"))),
]

/**
 * How a fixture is served: as it was built, under a hash not its own, or from where nothing
 * answers.
 */
let served = ["as_built", "hash_mismatched", "unfetchable"]

/** The checkers a property names, each written in the runner, never in a sample. */
let checkers = ["single_instance", "read_after_write"]

let run = () => {
  let found = []
  let called = Set.make()
  let sampled = Set.make()
  let sent = ref(false)
  let deployments = Contracts.interfaces->Array.find(i => i.name == "deployments")
  // A fixture, `tests/fixtures/{name}/fixture.json`: an app deployed by samples, its source the
  // runner's to build.
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
            captured: Set.make(),
            bounds: i.bounds->Option.getOr(dict{}),
            declared: i.declared->Option.getOr([]),
            fixtures: fixtures->Dict.keysToArray,
          }
          if text(c->member("description")) == None {
            found->Array.push(`${at}: no description`)
          }
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
                  // A call made `as` a component, signed by its certificate, to a component alone.
                  switch (st->member("as"), text(st->member("as"))) {
                  | (None, _) => ()
                  | (Some(_), Some(who))
                    if components->Array.includes(name) &&
                      Components.components->Dict.get(who) != None => ()
                  | (Some(_), _) =>
                    found->Array.push(`${at}: as, a component of the model and to a component`)
                  }
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
              // A call to what is deployed, in its app's own WIT: held to its shape alone, never a
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
  // An interface sampled is sampled whole: each operation called, each of its own reasons met.
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
    // A call, `contracts.json`'s `call`, fhg6w: its interface's own, an operation of it, the input
    // that operation reads, and the capabilities it carries, each bytes, none written absent.
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
