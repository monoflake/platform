/** The contracts, RFC fhg6w. */
open Base

let run = () => {
  // The contracts, RFC fhg6w: each declared once, in the subset, and written out as the product every
  // language reads. A product changed in place, a type of a record whose version stayed, is refused.
  let contractRules = []
  let declared = Dict.fromArray(Contracts.types->Array.map(t => (t.name, t)))
  let unique = (names, what) => {
    let seen = Set.make()
    names->Array.forEach(n => {
      if seen->Set.has(n) {
        contractRules->Array.push(`${what}: ${n} twice`)
      }
      seen->Set.add(n)
    })
  }
  unique(Contracts.types->Array.map(t => t.name), "a type")
  // What the signed records reach, where an id of any kind of a half may stand.
  let signedReach = Set.make()
  let rec reachSigned = name =>
    if !(signedReach->Set.has(name)) {
      signedReach->Set.add(name)
      declared
      ->Dict.get(name)
      ->Option.mapOr([], t => Subset.fieldsOf(t.def))
      ->Array.forEach(f =>
        Subset.refers(f.shape)->Array.forEach(r =>
          switch r {
          | #type_(n) => reachSigned(n)
          | _ => ()
          }
        )
      )
    }
  Signed.signed->Array.forEach(r => reachSigned(r.content))
  Signed.sections->Array.forEach(((_, t)) => reachSigned(t))
  // No secret is signed, nor travels in a bundle: it reaches a deployment alone, fhg6w.
  let rec secret = (shape: Subset.shape) =>
    switch shape {
    | Prim(#secret) => true
    | List(s) | Map(s) => secret(s)
    | _ => false
    }
  signedReach->Set.forEach(name =>
    declared
    ->Dict.get(name)
    ->Option.mapOr([], t => Subset.fieldsOf(t.def))
    ->Array.forEach(f =>
      if secret(f.shape) {
        contractRules->Array.push(
          `${name}.${f.name}: a secret, which a signed record or a bundle reaches`,
        )
      }
    )
  )
  // Each kind of record in one section at most, so no two readers hold one configuration apart.
  let sectionReach = Dict.make()
  Signed.sections->Array.forEach(((n, t)) => {
    let seen = Set.make()
    let rec walk = name =>
      if !(seen->Set.has(name)) {
        seen->Set.add(name)
        if Contracts.contents->Array.some(c => c.content == name) {
          switch sectionReach->Dict.get(name) {
          | Some(m) if m != n =>
            contractRules->Array.push(`${name}: in the bundle's ${m} section and its ${n} both`)
          | _ => sectionReach->Dict.set(name, n)
          }
        }
        declared
        ->Dict.get(name)
        ->Option.mapOr([], t => Subset.fieldsOf(t.def))
        ->Array.forEach(f =>
          Subset.refers(f.shape)->Array.forEach(
            r =>
              switch r {
              | #type_(x) => walk(x)
              | _ => ()
              },
          )
        )
      }
    walk(t)
  })
  unique(Signed.signed->Array.map(r => r.name), "a signed record")
  Signed.signed->Array.forEach(r =>
    switch declared->Dict.get(r.content) {
    | Some({def: Record(_), keys: #cwt}) if r.form == #claims => ()
    | Some({def: Record(_), keys: #subset}) | Some({def: Record(_), keys: ?None})
      if r.form == #record => ()
    | Some(_) =>
      contractRules->Array.push(
        `signed ${r.name}: ${r.content} is no record of the keys its form asks, CWT's for claims`,
      )
    | None => contractRules->Array.push(`signed ${r.name}: no type ${r.content}`)
    }
  )
  Signed.sections->Array.forEach(((n, t)) =>
    switch declared->Dict.get(t) {
    | Some({def: Record(_)}) => ()
    | _ => contractRules->Array.push(`a bundle's ${n} section: ${t}, no record`)
    }
  )
  // A key is the subset's from 1; a claim's is CWT's registered number for its name, or the
  // platform's own below -65536, b8f35; another standard's is as its RFC registers it.
  let checkFields = (where, fields: array<Subset.field>, ~content, ~keys: Subset.keys=#subset) => {
    unique(fields->Array.map(f => f.name), where)
    unique(fields->Array.map(f => int(f.key)), `${where}'s keys`)
    fields->Array.forEach(f => {
      switch keys {
      | #subset if f.key < 1 =>
        contractRules->Array.push(
          `${where}.${f.name}: key ${int(
              f.key,
            )}, below 1, which is the case's or the description's`,
        )
      | #cwt =>
        switch Signed.registered->Array.find(((n, _)) => n == f.name) {
        | Some((_, k)) if k != f.key =>
          contractRules->Array.push(`${where}.${f.name}: CWT registers it as ${int(k)}`)
        | Some(_) => ()
        | None if f.key >= -65536 =>
          contractRules->Array.push(
            `${where}.${f.name}: key ${int(f.key)}, a claim of the platform's own above -65537`,
          )
        | None => ()
        }
      | _ => ()
      }
      if content && f.name == "description" {
        contractRules->Array.push(
          `${where}: declares description, which every record's content holds already`,
        )
      }
      Subset.refers(f.shape)->Array.forEach(r =>
        switch r {
        | #type_(n) =>
          if declared->Dict.get(n) == None {
            contractRules->Array.push(`${where}.${f.name}: no type ${n}`)
          }
        | #id(k) =>
          if !(Records.records->Array.some(r => r.kind == k)) {
            contractRules->Array.push(`${where}.${f.name}: an id of ${k}, no kind of record`)
          }
        | #across(_, "*") =>
          if !(signedReach->Set.has(where->String.split(".")->Array.getUnsafe(0))) {
            contractRules->Array.push(
              `${where}.${f.name}: an id of any kind, which a signed record alone holds`,
            )
          }
        | #across(h, k) =>
          if Records.find(h, k) == None {
            contractRules->Array.push(
              `${where}.${f.name}: an id of the ${(h :> string)}'s ${k}, no kind of its`,
            )
          }
        }
      )
    })
  }
  let isContent = n => Contracts.contents->Array.some(c => c.content == n)
  Contracts.types->Array.forEach(t =>
    switch t.def {
    | Record(fields) =>
      checkFields(t.name, fields, ~content=isContent(t.name), ~keys=t.keys->Option.getOr(#subset))
    | Flags(choices) =>
      unique(choices->Array.map(c => c.name), t.name)
      unique(choices->Array.map(c => int(c.code)), `${t.name}'s bits`)
      choices->Array.forEach(c =>
        if c.code < 1 || Int.bitwiseAnd(c.code, c.code - 1) != 0 {
          contractRules->Array.push(`${t.name}.${c.name}: ${int(c.code)}, no single bit`)
        }
      )
    | Enum({choices, ordered}) =>
      unique(choices->Array.map(c => c.name), t.name)
      unique(choices->Array.map(c => int(c.code)), `${t.name}'s codes`)
      if ordered && choices->Array.some(c => c.code < 1) {
        contractRules->Array.push(`${t.name}: an ordered level coded below 1, 13ixj`)
      }
    | Union({tag, cases}) =>
      unique(cases->Array.map(c => c.name), t.name)
      unique(cases->Array.map(c => int(c.code)), `${t.name}'s codes`)
      cases->Array.forEach(c => {
        if c.code < 1 {
          contractRules->Array.push(`${t.name}.${c.name}: coded below 1`)
        }
        checkFields(`${t.name}.${c.name}`, c.fields, ~content=false)
        if c.fields->Array.some(f => f.name == tag) {
          contractRules->Array.push(`${t.name}.${c.name}: a field named ${tag}, its union's tag`)
        }
      })
    }
  )
  unique(
    Contracts.contents->Array.map(c => `the ${(c.half :> string)}'s ${c.kind}`),
    "a record's content",
  )
  // An id within a content names a kind of the content's own half, which its control checks: every
  // type a content reaches is read so, wherever else it is used.
  let rec reached = (name, seen: Set.t<string>) =>
    if !(seen->Set.has(name)) {
      seen->Set.add(name)
      declared
      ->Dict.get(name)
      ->Option.mapOr([], t => Subset.fieldsOf(t.def))
      ->Array.forEach(f =>
        Subset.refers(f.shape)->Array.forEach(r =>
          switch r {
          | #type_(n) => reached(n, seen)
          | _ => ()
          }
        )
      )
    }
  Contracts.contents->Array.forEach(c => {
    let seen = Set.make()
    reached(c.content, seen)
    seen->Set.forEach(n =>
      declared
      ->Dict.get(n)
      ->Option.mapOr([], t => Subset.fieldsOf(t.def))
      ->Array.forEach(
        f =>
          Subset.refers(f.shape)->Array.forEach(
            r =>
              switch r {
              | #id(k) if Records.find(c.half, k) == None =>
                contractRules->Array.push(
                  `the ${(c.half :> string)}'s ${c.kind}: ${n}.${f.name} names ${k}, no kind of its half; an id across halves is Across`,
                )
              | _ => ()
              },
          ),
      )
    )
  })
  // A key is fields of the content itself, each named once, and no two keys of one kind alike.
  Contracts.contents->Array.forEach(c =>
    c.unique
    ->Option.getOr([])
    ->Array.forEach(key => {
      let fields = switch declared->Dict.get(c.content) {
      | Some({def: Record(fs)}) => fs->Array.map(f => f.name)
      | _ => []
      }
      if key == [] {
        contractRules->Array.push(`the ${(c.half :> string)}'s ${c.kind}: a key of no field`)
      }
      unique(key, `the ${(c.half :> string)}'s ${c.kind}'s key`)
      key->Array.forEach(
        f =>
          if !(fields->Array.includes(f)) {
            contractRules->Array.push(
              `the ${(c.half :> string)}'s ${c.kind}: its key names ${f}, no field of ${c.content}`,
            )
          },
      )
    })
  )
  Contracts.contents->Array.forEach(c => {
    if Records.find(c.half, c.kind) == None {
      contractRules->Array.push(`${c.kind}'s content: no such kind of record`)
    }
    switch declared->Dict.get(c.content) {
    | Some({def: Record(_)}) => ()
    | Some(_) => contractRules->Array.push(`${c.kind}'s content, ${c.content}, is no record`)
    | None => contractRules->Array.push(`${c.kind}'s content: no type ${c.content}`)
    }
  })
  // An interface's operations, RFC vr5lw: named in whole words, snake_case, each input and output a
  // record declared, and each reason its own.
  let snake = n => /^[a-z]+(_[a-z]+)*$/->RegExp.test(n)
  unique(Contracts.interfaces->Array.map(i => i.name), "an interface")
  Contracts.interfaces->Array.forEach(i => {
    unique(i.operations->Array.map(o => o.name), `${i.name}'s operations`)
    i.operations->Array.forEach(o => {
      let at = `${i.name}.${o.name}`
      if !snake(o.name) {
        contractRules->Array.push(`${at}: no snake_case name`)
      }
      [o.input, o.output]->Array.forEach(
        n =>
          switch declared->Dict.get(n) {
          | Some({def: Record(_)}) => ()
          | Some(_) => contractRules->Array.push(`${at}: ${n} is no record`)
          | None => contractRules->Array.push(`${at}: no type ${n}`)
          },
      )
      unique(o.reasons->Array.map(r => r.name), `${at}'s reasons`)
      o.reasons->Array.forEach(
        r => {
          if !snake(r.name) {
            contractRules->Array.push(`${at}: reason ${r.name}, no snake_case name`)
          }
          if Calls.common->Array.some(c => c.name == r.name) {
            contractRules->Array.push(`${at}: reason ${r.name}, which every operation has already`)
          }
        },
      )
    })
  })
  // The drivers' runtimes, RFC vr5lw: each a runtime the deployments' contract names, taking one of its
  // forms and standing on its isolations, every runtime given by some driver and every form taken.
  let choices = n =>
    switch declared->Dict.get(n) {
    | Some({def: Enum({choices})}) => choices->Array.map(c => c.name)
    | _ => []
    }
  let given =
    Drivers.drivers->Dict.toArray->Array.flatMap(((d, v)) => v.runtimes->Array.map(r => (d, r)))
  given->Array.forEach(((d, r)) => {
    let at = `${d}'s ${r.name}`
    if !(choices("deployment-runtime")->Array.includes(r.name)) {
      contractRules->Array.push(`${at}: no runtime of deployment-runtime`)
    }
    if !(choices("deployment-form")->Array.includes(r.takes)) {
      contractRules->Array.push(`${at}: takes ${r.takes}, no deployment-form`)
    }
    r.stands->Array.forEach(i =>
      if !(choices("deployment-isolation")->Array.includes(i)) {
        contractRules->Array.push(`${at}: stands on ${i}, no deployment-isolation`)
      }
    )
  })
  choices("deployment-runtime")->Array.forEach(n =>
    if !(given->Array.some(((_, r)) => r.name == n)) {
      contractRules->Array.push(`deployment-runtime ${n}: given by no driver`)
    }
  )
  choices("deployment-form")->Array.forEach(f =>
    if !(given->Array.some(((_, r)) => r.takes == f)) {
      contractRules->Array.push(`deployment-form ${f}: taken by no runtime`)
    }
  )
  // A database's preset tiers, zn3u5: within the bounds every set is held to, each sparser and kept
  // longer than the one before.
  Database.retentionPreset->Array.forEachWithIndex(((every, keep), i) => {
    if every < Database.retentionFinest || keep > Database.retentionMost || every >= keep {
      contractRules->Array.push(
        `database's preset tier ${int(i)}: past the bounds every set is held to`,
      )
    }
    switch Database.retentionPreset[i - 1] {
    | Some((e, k)) if every <= e || keep <= k =>
      contractRules->Array.push(
        `database's preset tier ${int(i)}: no sparser and longer than the one before`,
      )
    | _ => ()
    }
  })
  let made = Contracts.product(~writes=(h, k) =>
    Records.find(h, k)->Option.mapOr([], r => r.writes)
  )
  let productUrl = urlIn("model/contracts.json", root)
  let kept = existsSync(productUrl) ? Some(JSON.parseOrThrow(readFileSync(productUrl))) : None
  let text = (j: JSON.t) => JSON.stringify(j)
  let member = (j: JSON.t, k) =>
    switch j {
    | Object(d) => d->Dict.get(k)
    | _ => None
    }
  let items = (j: option<JSON.t>) =>
    switch j {
    | Some(Array(a)) => a
    | _ => []
    }
  let named = (j: JSON.t, k) => j->member(k)->Option.flatMap(JSON.Decode.string)->Option.getOr("")
  // The types a record's content reaches, by name, each with its definition.
  let reach = (p: JSON.t, root) => {
    let defs = p->member("types")
    let found = Map.make()
    let rec walk = n =>
      if !(found->Map.has(n)) {
        switch defs->Option.flatMap(d => d->member(n)) {
        | Some(d) =>
          found->Map.set(n, d)
          let rec names = (s: JSON.t) =>
            switch (s->member("type"), s->member("list"), s->member("map")) {
            | (Some(String(t)), _, _) => [t]
            | (_, Some(inner), _) | (_, _, Some(inner)) => names(inner)
            | _ => []
            }
          let fields = Array.concat(
            items(d->member("record")),
            items(d->member("union")->Option.flatMap(u => u->member("cases")))->Array.flatMap(c =>
              items(c->member("fields"))
            ),
          )
          fields->Array.forEach(f =>
            f->member("shape")->Option.mapOr([], names)->Array.forEach(walk)
          )
        | None => ()
        }
      }
    walk(root)
    found
  }
  // What an old reader of a version can no longer read: a type it reached gone or changed, past a
  // record's fields that are new and optional, and an interface's operation gone.
  let breaks = (old: JSON.t, now: JSON.t) => {
    let found = []
    // An id is an integer on the wire whatever kind and half it names, so naming them otherwise
    // breaks no reader: what is compared is what is written.
    let rec wire = (j: JSON.t): JSON.t =>
      switch j {
      | Object(d) if d->Dict.get("id") != None => Object(dict{"id": String("*")})
      | Object(d) => Object(d->Dict.mapValues(wire))
      | Array(xs) => Array(xs->Array.map(wire))
      | x => x
      }
    let text = j => text(wire(j))
    let same = (label, was, is) => {
      let before = reach(old, was)
      let after = reach(now, is)
      before->Map.forEachWithKey((d, name) =>
        switch after->Map.get(name) {
        | None => found->Array.push(`${label}: ${name} gone, its version kept`)
        | Some(a) =>
          switch (d->member("record"), a->member("record")) {
          | (Some(Array(was)), Some(Array(is))) =>
            was->Array.forEach(f =>
              if !(is->Array.some(g => text(g) == text(f))) {
                found->Array.push(
                  `${label}: ${name}.${f->named("name")} removed or changed, its version kept`,
                )
              }
            )
            is->Array.forEach(g =>
              if (
                !(was->Array.some(f => f->named("name") == g->named("name"))) &&
                g->member("optional") == None
              ) {
                found->Array.push(
                  `${label}: ${name}.${g->named("name")} added and required, its version kept`,
                )
              }
            )
          | _ =>
            if text(d) != text(a) {
              found->Array.push(`${label}: ${name} changed, its version kept`)
            }
          }
        }
      )
    }
    let version = j => text(j->member("version")->Option.getOr(Null))
    items(old->member("records"))->Array.forEach(r => {
      let kind = r->named("kind")
      switch items(now->member("records"))->Array.find(x =>
        x->named("kind") == kind && x->named("half") == r->named("half")
      ) {
      | Some(n) if version(n) == version(r) => same(kind, r->named("content"), n->named("content"))
      | _ => ()
      }
    })
    let interface_ = (j: JSON.t, i) => j->member("interfaces")->Option.flatMap(x => x->member(i))
    switch old->member("interfaces") {
    | Some(Object(d)) =>
      d->Dict.forEachWithKey((o, i) =>
        switch interface_(now, i) {
        | Some(n) if version(n) == version(o) =>
          items(o->member("operations"))->Array.forEach(op => {
            let at = `${i}.${op->named("name")}`
            switch items(n->member("operations"))->Array.find(
              x => x->named("name") == op->named("name"),
            ) {
            | None => found->Array.push(`${at} gone, its version kept`)
            | Some(x) =>
              same(at, op->named("input"), x->named("input"))
              same(at, op->named("output"), x->named("output"))
            }
          })
        | _ => ()
        }
      )
    | _ => ()
    }
    Set.fromArray(found)->Set.values->Array.fromIterator
  }
  let write = args->Array.includes("--write")
  switch kept {
  | Some(k) if text(k) == text(made) => ()
  | Some(k) if write =>
    switch breaks(k, made) {
    | [] => writeFileSync(productUrl, JSON.stringify(made, ~space=2) ++ "\n")
    | b => b->Array.forEach(x => contractRules->Array.push(`refused to write contracts.json: ${x}`))
    }
  | None if write => writeFileSync(productUrl, JSON.stringify(made, ~space=2) ++ "\n")
  | _ => contractRules->Array.push("contracts.json is not what the model writes; run with --write")
  }
  dimension(
    "Contracts",
    "Is every contract declared once in the subset, every name it uses resolved, and contracts.json what the model writes, never changed in place?",
    contractRules,
    ~notes=[
      ...([#organization, #platform]: array<Subset.half>)->Array.map(h =>
        `declared, the ${(h :> string)}'s: ${Contracts.contents
          ->Array.filter(c => c.half == h)
          ->Array.map(c => `${c.kind} v${int(c.version)}`)
          ->orNone(", ")}`
      ),
      `interfaces: ${Contracts.interfaces
        ->Array.map(i => `${i.name} v${int(i.version)}`)
        ->orNone(
          ", ",
        )}; function, instance and container are deployed by deployments and called by an app's WIT; volume has none but its files`,
      `signed: ${Signed.signed
        ->Array.map(r => `${r.name} v${int(r.version)}, ${(r.form :> string)}`)
        ->orNone(", ")}; a bundle's sections: ${Signed.sections
        ->Array.map(((n, _)) => n)
        ->orNone(", ")}, no secret reaching any`,
      `to declare: ${Records.records
        ->Array.filter(r =>
          !(Contracts.contents->Array.some(c => c.kind == r.kind && c.half == r.half))
        )
        ->Array.map(r => `the ${(r.half :> string)}'s ${r.kind}`)
        ->orNone(", ")}`,
    ],
    (),
  )
}
