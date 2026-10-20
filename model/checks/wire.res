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
  let checkFields = (where, fields: array<Subset.field>, ~content) => {
    unique(fields->Array.map(f => f.name), where)
    unique(fields->Array.map(f => int(f.key)), `${where}'s keys`)
    fields->Array.forEach(f => {
      if f.key < 1 {
        contractRules->Array.push(
          `${where}.${f.name}: key ${int(
              f.key,
            )}, below 1, which is the case's or the description's`,
        )
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
          if Records.records->Dict.get(k) == None {
            contractRules->Array.push(`${where}.${f.name}: an id of ${k}, no kind of record`)
          }
        }
      )
    })
  }
  let isContent = n => Contracts.contents->Array.some(c => c.content == n)
  Contracts.types->Array.forEach(t =>
    switch t.def {
    | Record(fields) => checkFields(t.name, fields, ~content=isContent(t.name))
    | Enum({choices, ordered}) =>
      unique(choices->Array.map(c => c.name), t.name)
      unique(choices->Array.map(c => int(c.code)), `${t.name}'s codes`)
      if ordered && choices->Array.some(c => c.code < 1) {
        contractRules->Array.push(`${t.name}: an ordered level coded below 1, 13ixj`)
      }
    | Union({cases}) =>
      unique(cases->Array.map(c => c.name), t.name)
      unique(cases->Array.map(c => int(c.code)), `${t.name}'s codes`)
      cases->Array.forEach(c => {
        if c.code < 1 {
          contractRules->Array.push(`${t.name}.${c.name}: coded below 1`)
        }
        checkFields(`${t.name}.${c.name}`, c.fields, ~content=false)
      })
    }
  )
  unique(Contracts.contents->Array.map(c => c.kind), "a record's content")
  Contracts.contents->Array.forEach(c => {
    if Records.records->Dict.get(c.kind) == None {
      contractRules->Array.push(`${c.kind}'s content: no such kind of record`)
    }
    switch declared->Dict.get(c.content) {
    | Some({def: Record(_)}) => ()
    | Some(_) => contractRules->Array.push(`${c.kind}'s content, ${c.content}, is no record`)
    | None => contractRules->Array.push(`${c.kind}'s content: no type ${c.content}`)
    }
  })
  let made = Contracts.product(
    ~half=k => Records.records->Dict.get(k)->Option.mapOr("", r => (r.half :> string)),
    ~writes=k => Records.records->Dict.get(k)->Option.mapOr([], r => r.writes),
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
  // record's fields that are new and optional.
  let breaks = (old: JSON.t, now: JSON.t) => {
    let found = []
    items(old->member("records"))->Array.forEach(r => {
      let kind = r->named("kind")
      switch items(now->member("records"))->Array.find(x => x->named("kind") == kind) {
      | Some(n)
        if text(n->member("version")->Option.getOr(Null)) ==
          text(r->member("version")->Option.getOr(Null)) =>
        let before = reach(old, r->named("content"))
        let after = reach(now, n->named("content"))
        before->Map.forEachWithKey((d, name) =>
          switch after->Map.get(name) {
          | None => found->Array.push(`${kind}: ${name} gone, its version kept`)
          | Some(a) =>
            switch (d->member("record"), a->member("record")) {
            | (Some(Array(was)), Some(Array(is))) =>
              was->Array.forEach(
                f =>
                  if !(is->Array.some(g => text(g) == text(f))) {
                    found->Array.push(
                      `${kind}: ${name}.${f->named("name")} removed or changed, its version kept`,
                    )
                  },
              )
              is->Array.forEach(
                g =>
                  if (
                    !(was->Array.some(f => f->named("name") == g->named("name"))) &&
                    g->member("optional") == None
                  ) {
                    found->Array.push(
                      `${kind}: ${name}.${g->named("name")} added and required, its version kept`,
                    )
                  },
              )
            | _ =>
              if text(d) != text(a) {
                found->Array.push(`${kind}: ${name} changed, its version kept`)
              }
            }
          }
        )
      | _ => ()
      }
    })
    found
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
      `declared: ${Contracts.contents
        ->Array.map(c => `${c.kind} v${int(c.version)}`)
        ->orNone(", ")}`,
      `to declare: ${Records.records
        ->Dict.keysToArray
        ->Array.filter(k => !(Contracts.contents->Array.some(c => c.kind == k)))
        ->orNone(", ")}`,
    ],
    (),
  )
}
