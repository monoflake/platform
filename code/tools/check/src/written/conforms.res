/** A sample value held to the shape its contract declares, as `cases.res` asks, RFC vr5lw. */
open Base

let declared = Dict.fromArray(Contracts.types->Array.map(t => (t.name, t)))

let base64urlText = /^[A-Za-z0-9_-]*$/
let hexText = /^([0-9a-f]{2})*$/
let hashText = /^[0-9a-f]{64}$/

let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

/** Base64url without padding and with its unused last bits zero, one text a value, fhg6w. */
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

/** Where a value stands, in an input, in what is expected or in a codec sample. */
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

/** A sample's placeholder, an object of one `$`-led key. */
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
    // A value captured before, given as it was or expected the same.
    | ("$use", Input | Expected, Some(n)) =>
      if !(s.captured->Set.has(n)) {
        fail(`uses ${n}, captured by no step before`)
      }
    // Bytes of a length, or a text its `start` leads and spaces fill to a length, a number or a
    // bound and how many past it.
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
/**
 * A record's fields, each required one present and conforming. A field unknown is a mistake in a
 * sample and passed over by a reader.
 */
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
