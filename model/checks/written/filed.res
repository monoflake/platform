/** The checklist, and every open question filed in it. */
open Base

type mark = {where: string, mutable text: string}

let run = () => {
  // The checklist, `model/plan/checklist.res`, grows by itself: every open question a draft lists
  // and every open mark in the model names its row in brackets, `[B12]`, and one that names none is
  // unfiled until it is, so a new structure's new questions reach the checklist without being
  // copied there.
  let hasTag = text => /\[([A-E]\d+)\]/->RegExp.test(text)
  let tagsIn = text => {
    let re = /\[([A-E]\d+)\]/g
    let found = []
    let go = ref(true)
    while go.contents {
      switch re->RegExp.exec(text) {
      | Some(m) =>
        switch m->RegExp.Result.matches {
        | [Some(id)] => found->Array.push(id)
        | _ => ()
        }
      | None => go := false
      }
    }
    found
  }
  let marks: array<mark> = []
  let rfcs = urlIn("docs/rfcs/", root)
  readdirSync(rfcs)
  ->Array.filter(f => f->String.endsWith(".md"))
  ->Array.toSorted(byText)
  ->Array.forEach(file => {
    let text = readFileSync(urlIn(file, rfcs))
    let at = text->String.indexOf("Open, for the discussion that follows:")
    if at >= 0 {
      let id = switch /-([a-z0-9]{5})\.md$/->RegExp.exec(file) {
      | Some(m) =>
        switch m->RegExp.Result.matches {
        | [Some(id)] => id
        | _ => file
        }
      | None => file
      }
      let bullet = ref(None)
      let lines = text->String.slice(~start=at)->String.split("\n")->Array.slice(~start=1)
      let i = ref(0)
      while i.contents < lines->Array.length {
        let l = lines->Array.getUnsafe(i.contents)
        i := i.contents + 1
        if l->String.startsWith("- ") {
          let b = [l->String.slice(~start=2)]
          bullet := Some(b)
          marks->Array.push({where: id, text: b->Array.join(" ")})
        } else if l->String.startsWith("  ") && bullet.contents != None {
          switch bullet.contents {
          | Some(b) =>
            b->Array.push(l->String.trim)
            (marks->Array.getUnsafe(marks->Array.length - 1)).text = b->Array.join(" ")
          | None => ()
          }
        } else if l->String.trim == "" {
          bullet := None
        } else {
          i := lines->Array.length
        }
      }
    }
  })
  components
  ->Dict.toArray
  ->Array.forEach(((name, p)) =>
    p.edges->Array.forEach(edge =>
      switch edge.open_ {
      | Some(o) => marks->Array.push({where: `${name} -> ${edge.to_}`, text: o})
      | None => ()
      }
    )
  )
  Components.globalOpen->Array.forEach(g => marks->Array.push({where: "globalOpen", text: g}))
  Components.undeclared->Array.forEach(((n, t)) =>
    marks->Array.push({where: `contract ?${n}`, text: t})
  )
  Footing.kept
  ->Dict.toArray
  ->Array.forEach(((name, k)) => {
    switch k.open_ {
    | Some(o) => marks->Array.push({where: `footing ${name}`, text: o})
    | None => ()
    }
    switch k.bound {
    | Some(b) if hasTag(b) => marks->Array.push({where: `footing ${name}`, text: b})
    | _ => ()
    }
  })
  let openWords = /\b(is|are) open\b|\bOpen:/
  Boundaries.boundaries
  ->Dict.toArray
  ->Array.forEach(((name, b)) => {
    [b.contract, b.keptBy]->Array.forEach(t =>
      switch t {
      | Some(text) if openWords->RegExp.test(text) => marks->Array.push({where: name, text})
      | _ => ()
      }
    )
    if (
      b.triage == Some(#later) &&
        !([b.contract, b.keptBy]->Array.some(t => t->Option.mapOr(false, hasTag)))
    ) {
      marks->Array.push({where: name, text: `left for later: ${b.keptBy->Option.getOr("")}`})
    }
  })

  let checklist = Checklist.checklist
  let rowsWrong = []
  let ids = Set.make()
  checklist->Array.forEach(item => {
    if ids->Set.has(item.id) {
      rowsWrong->Array.push(`${item.id}: listed twice`)
    }
    ids->Set.add(item.id)
    if !(item.id->String.startsWith((item.group :> string))) {
      rowsWrong->Array.push(`${item.id}: filed under ${(item.group :> string)}`)
    }
    if item.group == #C && steps != [] && item.step->Option.mapOr(true, s => steps[s] == None) {
      rowsWrong->Array.push(`${item.id}: names no step of the bootstrap path`)
    }
    if item.group != #C && item.step != None {
      rowsWrong->Array.push(`${item.id}: only a row of group C waits for a later step`)
    }
  })
  let unfiled = []
  marks->Array.forEach(m => {
    let named = tagsIn(m.text)
    if named->Array.length == 0 {
      unfiled->Array.push(`unfiled, ${m.where}: ${m.text}`)
    }
    named->Array.forEach(id =>
      switch checklist->Array.find(x => x.id == id) {
      // Group D is the hosted platform's, given with its rows; alone, a mark may name one.
      | None if Checklist.given == [] && id->String.startsWith("D") => ()
      | None => rowsWrong->Array.push(`${m.where} names ${id}, no row of the checklist`)
      | Some({done: d}) =>
        rowsWrong->Array.push(`${m.where} still lists ${id} open, though it was decided in ${d}`)
      | Some(_) => ()
      }
    )
  })

  let readyArg = args->Array.find(a => a == "--ready" || a->String.startsWith("--ready="))
  let ready = readyArg != None
  let upTo = switch readyArg {
  | Some(a) if a->String.includes("=") => number(a->String.split("=")->Array.getUnsafe(1))
  | _ => 0.
  }
  if ready && (!isInteger(upTo) || (steps != [] && steps[upTo->Float.toInt] == None)) {
    rowsWrong->Array.push(`--ready=${num(upTo)} names no step of the bootstrap path`)
  }
  let open_ = checklist->Array.filter(x => x.done == None)
  let blocking =
    open_->Array.filter(x =>
      x.group == #A ||
      x.group == #B ||
      x.group == #E ||
      (x.group == #C && x.step->Option.mapOr(false, s => Int.toFloat(s) <= upTo))
    )
  dimension(
    "Checklist",
    ready
      ? `Is every row that blocks step ${num(
            upTo,
          )} crossed off, and every open question filed, so it may begin?`
      : "Is every row well formed, and every open question filed? Run with --ready to ask whether building may begin.",
    [
      rowsWrong,
      unfiled,
      ready ? blocking->Array.map(x => `open ${x.id}: ${x.what} (${x.from})`) : [],
    ]->Array.flat,
    ~notes=[
      [
        `open: ${([#A, #B, #C, #D, #E]: array<Checklist.group>)
          ->Array.map(g =>
            `${(g :> string)} ${int(open_->Array.filter(x => x.group == g)->Array.length)}`
          )
          ->Array.join(", ")}; crossed off: ${int(
            checklist->Array.length - open_->Array.length,
          )}; open questions filed: ${int(marks->Array.length - unfiled->Array.length)} of ${int(
            marks->Array.length,
          )}`,
        `blocking step ${num(upTo)}: ${blocking->Array.length > 0
            ? blocking->Array.map(x => x.id)->Array.join(" ")
            : "none, it may begin"}`,
      ],
      ready
        ? open_
          ->Array.filter(x => !(blocking->Array.includes(x)))
          ->Array.map(x =>
            `later ${x.id}${switch x.step {
              | Some(s) => ` (before step ${int(s)})`
              | None => ""
              }}: ${x.what}`
          )
        : [],
    ]->Array.flat,
    (),
  )
}
