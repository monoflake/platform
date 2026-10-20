/**
 * The samples in `tests/`, RFC vr5lw: data alone, which any language reads, held here to the
 * contracts they sample. A behavior file is an interface's cases, each a list of steps -- an
 * operation called with an input, and its output or its failure expected; a codec file is values in
 * JSON beside their CBOR, and inputs every reader must refuse. Every operation and every reason of
 * an interface with samples must be sampled.
 */
open Base

let declared = Dict.fromArray(Contracts.types->Array.map(t => (t.name, t)))

let base64urlText = /^[A-Za-z0-9_-]*$/
let int64Text = /^-?(0|[1-9][0-9]{0,18})$/
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

/** A decimal string of a signed 64-bit integer, no sign but a minus, no leading zero. */
let isInt64 = s =>
  int64Text->RegExp.test(s) && {
      let digits = s->String.startsWith("-") ? s->String.slice(~start=1) : s
      let most = s->String.startsWith("-") ? "9223372036854775808" : "9223372036854775807"
      String.length(digits) < 19 || digits <= most
    }

let isInteger = (x, lo, hi) => Math.floor(x) == x && x >= lo && x <= hi

let isHex = s => hexText->RegExp.test(s)

/** Where a value stands: in an input, in what is expected, or in a codec sample, read as a reader would. */
type mode = Input | Expected | Codec

type scope = {
  found: array<string>,
  captured: Set.t<string>,
  bounds: dict<int>,
  declared: array<string>,
}

let isContent = n => Contracts.contents->Array.some(c => c.content == n)

/** A sample's placeholder: an object of one key, `$`-led. */
let placeholder = (j: JSON.t) =>
  switch j {
  | Object(d) =>
    switch d->Dict.toArray {
    | [(k, v)] if k->String.startsWith("$") => Some((k, v))
    | _ => None
    }
  | _ => None
  }

/** Every way a value fails its shape, as `at` names where; none is a value that conforms. */
let rec conforms = (s: scope, shape: Subset.shape, j: JSON.t, mode, at) => {
  let fail = why => s.found->Array.push(`${at}: ${why}`)
  switch (placeholder(j), mode) {
  | (Some(("$any", _)), Expected) => ()
  | (Some(("$capture", String(n))), Expected) => s.captured->Set.add(n)
  | (Some(("$use", String(n))), Input) =>
    if !(s.captured->Set.has(n)) {
      fail(`uses ${n}, captured by no step before`)
    }
  // Bytes of a length, or a text its `start` led and spaces filled to a length, either a number or
  // a bound and how many past it: a bound of the interface's, or one each driver declares.
  | (Some((("$bytes" | "$text") as k, spec)), Input | Expected) =>
    if shape != (k == "$bytes" ? Prim(#bytes) : Prim(#string)) {
      fail(`${k} where its kind of value is not`)
    }
    switch spec {
    | Object(d) =>
      switch d->Dict.get("start") {
      | None | Some(String(_)) if k == "$text" => ()
      | None => ()
      | Some(_) => fail(`${k} takes no start but a text's`)
      }
      switch d->Dict.get("length") {
      | Some(Number(n)) if isInteger(n, 0., 9007199254740991.) => ()
      | Some(Object(b)) =>
        switch (b->Dict.get("bound"), b->Dict.get("plus")) {
        | (Some(String(name)), Some(Number(p))) if isInteger(p, -1e9, 1e9) =>
          if s.bounds->Dict.get(name) == None && !(s.declared->Array.includes(name)) {
            fail(`${k} past ${name}, no bound of its interface`)
          }
        | _ => fail(`${k}'s length is a bound and how many past it`)
        }
      | _ => fail(`${k} without a length`)
      }
    | _ => fail(`${k} takes a length`)
    }
  | (Some((k, _)), _) => fail(`placeholder ${k}, not taken here`)
  | (None, _) =>
    switch (shape, j) {
    | (Prim(#bool), Boolean(_)) => ()
    | (Prim(#string), String(_)) => ()
    | (Prim(#float64), Number(_)) => ()
    | (Prim(#int32), Number(n)) if isInteger(n, -2147483648., 2147483647.) => ()
    | (Prim(#uint32), Number(n)) | (Id(_), Number(n)) if isInteger(n, 0., 4294967295.) => ()
    | (Prim(#uint53), Number(n)) if isInteger(n, 0., 9007199254740991.) => ()
    | (Prim(#int64), String(t)) if isInt64(t) => ()
    | (Prim(#bytes), String(t)) if isBase64url(t) => ()
    | (Prim(#hash), String(t)) if hashText->RegExp.test(t) => ()
    | (Prim(p), _) => fail(`no ${(p :> string)}`)
    | (Id(kind), _) => fail(`no id of ${kind}`)
    | (List(inner), Array(items)) =>
      items->Array.forEachWithIndex((v, i) => conforms(s, inner, v, mode, `${at}[${int(i)}]`))
    | (List(_), _) => fail("no list")
    | (Map(inner), Object(d)) =>
      d->Dict.forEachWithKey((v, k) => conforms(s, inner, v, mode, `${at}.${k}`))
    | (Map(_), _) => fail("no map")
    | (Type(name), _) =>
      switch declared->Dict.get(name) {
      | None => fail(`no type ${name}`)
      | Some({def}) =>
        switch (def, j) {
        | (Record(fields), Object(d)) =>
          let fields = isContent(name) ? Array.concat([Subset.description], fields) : fields
          record(s, fields, d, [], mode, at)
        | (Enum({choices}), String(c)) =>
          if !(choices->Array.some(x => x.name == c)) {
            fail(`${c}, no choice of ${name}`)
          }
        | (Union({tag, cases}), Object(d)) =>
          switch d->Dict.get(tag) {
          | Some(String(c)) =>
            switch cases->Array.find(x => x.name == c) {
            | Some(case) => record(s, case.fields, d, [tag], mode, at)
            | None => fail(`${c}, no case of ${name}`)
            }
          | _ => fail(`no ${tag}, which names ${name}'s case`)
          }
        | (Record(_) | Union(_), _) => fail(`no object, as ${name} is`)
        | (Enum(_), _) => fail(`no name of ${name}`)
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

let member = (j: JSON.t, k) =>
  switch j {
  | Object(d) => d->Dict.get(k)
  | _ => None
  }

let items = j =>
  switch j {
  | Some(JSON.Array(a)) => a
  | _ => []
  }

let run = () => {
  let found = []
  let called = Set.make()
  let sampled = Set.make()
  let behavior = files("tests/kinds")
  behavior->Array.forEach(path => {
    let j = read(path)
    switch j->member("interface") {
    | Some(String(name)) =>
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
          }
          switch c->member("description") {
          | Some(String(_)) => ()
          | _ => found->Array.push(`${at}: no description`)
          }
          // What the runner holds for the case before its first step, as capacity of its kind.
          switch c->member("given") {
          | None => ()
          | Some(g) =>
            switch declared->Dict.get("management-capacity") {
            | Some({def: Union({cases})}) =>
              switch (cases->Array.find(x => x.name == name), g) {
              | (Some(k), Object(d)) => record(s, k.fields, d, [], Input, `${at}.given`)
              | _ => found->Array.push(`${at}: given, which ${name} holds no capacity of`)
              }
            | _ => ()
            }
          }
          let steps = items(c->member("steps"))
          if steps == [] {
            found->Array.push(`${at}: no steps`)
          }
          steps->Array.forEachWithIndex(
            (st, k) => {
              let at = `${at}.${int(k)}`
              // A step `within` some milliseconds is called again until it is answered as expected.
              switch st->member("within") {
              | None => ()
              | Some(Number(ms)) if isInteger(ms, 1., 3600000.) => ()
              | Some(_) => found->Array.push(`${at}: within, no milliseconds up to an hour`)
              }
              switch st->member("call") {
              | Some(String(call)) =>
                switch i.operations->Array.find(o => o.name == call) {
                | None => found->Array.push(`${at}: ${call}, no operation of ${name}`)
                | Some(o) =>
                  called->Set.add(`${name}.${call}`)
                  conforms(
                    s,
                    Type(o.input),
                    st->member("input")->Option.getOr(Null),
                    Input,
                    `${at}.input`,
                  )
                  switch st->member("expect") {
                  | Some(e) =>
                    switch (e->member("output"), e->member("failure"), e->member("reason")) {
                    | (Some(out), None, None) =>
                      conforms(s, Type(o.output), out, Expected, `${at}.output`)
                    | (None, Some(String(failure)), Some(String(reason))) =>
                      switch Array.concat(o.reasons, Calls.common)->Array.find(
                        r => r.name == reason,
                      ) {
                      | Some(r) =>
                        if (r.failure :> string) != failure {
                          found->Array.push(
                            `${at}: ${reason} is ${(r.failure :> string)}, not ${failure}`,
                          )
                        }
                        sampled->Set.add(`${name}.${call}.${reason}`)
                      | None => found->Array.push(`${at}: ${reason}, no reason of ${call}`)
                      }
                    | _ =>
                      found->Array.push(`${at}: expects an output, or a failure and its reason`)
                    }
                  | None => found->Array.push(`${at}: expects nothing`)
                  }
                }
              | _ => found->Array.push(`${at}: calls nothing`)
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
  // A codec sample is a value in JSON beside its CBOR; one refused fails as every reader must refuse it.
  let codec = files("tests/codec")
  let pairs = ref(0)
  let refused = ref(0)
  codec->Array.forEach(path => {
    let j = read(path)
    let typed = (x, n, what) =>
      switch x->member("type") {
      | Some(String(t)) if declared->Dict.get(t) != None => Some(t)
      | _ =>
        found->Array.push(`${path}: ${what} ${int(n)}, no type declared`)
        None
      }
    items(j->member("samples"))->Array.forEachWithIndex((x, n) =>
      switch typed(x, n, "sample") {
      | Some(t) =>
        pairs := pairs.contents + 1
        let s = {found, captured: Set.make(), bounds: dict{}, declared: []}
        conforms(s, Type(t), x->member("json")->Option.getOr(Null), Codec, `${path}#${int(n)}`)
        switch x->member("cbor") {
        | Some(String(h)) if isHex(h) && h != "" => ()
        | _ => found->Array.push(`${path}#${int(n)}: no CBOR in lowercase hex`)
        }
      | None => ()
      }
    )
    items(j->member("refused"))->Array.forEachWithIndex((x, n) =>
      switch typed(x, n, "refused") {
      | Some(t) =>
        refused := refused.contents + 1
        let s = {found: [], captured: Set.make(), bounds: dict{}, declared: []}
        conforms(s, Type(t), x->member("json")->Option.getOr(Null), Codec, "")
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
