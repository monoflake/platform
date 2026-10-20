/** The bootstrap path, RFC 94y0d. */
open Base

let run = () => {
  // The bootstrap path, RFC 94y0d: each step holds, and each deployment came to it by a move it may
  // take. A version, v, is the Platform's release; a stage, s, is the model's, `docs/scope.md`.
  let steps = Steps.steps
  let path = []
  let stops = []
  steps->Array.forEachWithIndex((step, i) => {
    let at = `step ${int(i)}`
    let before = steps[i - 1]
    let sides = [
      ("foundation", Some(step.foundation), before->Option.map(b => b.foundation)),
      ("production", step.production, before->Option.flatMap(b => b.production)),
    ]
    sides->Array.forEach(((name, d, was)) =>
      switch d {
      | None => ()
      | Some(d) =>
        d.on->Array.forEach(
          f =>
            if !(Versions.versions[d.version]->Option.mapOr(false, v => v->Array.includes(f))) {
              path->Array.push(
                `${at}: the ${name} platform turns on ${(f :> string)}, which v${int(
                    d.version,
                  )} lacks`,
              )
            },
        )
        switch was {
        | None =>
          let first: Steps.move = name == "foundation" ? #"by hand" : #"new organization"
          if d.move != first {
            path->Array.push(
              `${at}: the ${name} platform first comes up by ${(d.move :> string)}, not ${(first :> string)}`,
            )
          }
        | Some(was) =>
          if d.version == was.version {
            if d.move != #none {
              path->Array.push(
                `${at}: the ${name} platform moves by ${(d.move :> string)} with no new version`,
              )
            }
          } else if d.move == #rolling && !ons(was, #rolling) {
            path->Array.push(
              `${at}: the ${name} platform rolls from v${int(
                  was.version,
                )}, which cannot replace a component while the rest run`,
            )
          } else if d.move == #"planned stop" {
            stops->Array.push(
              `${at}, the ${name} platform, v${int(was.version)} -> v${int(d.version)}`,
            )
            if ons(was, #rolling) {
              path->Array.push(
                `${at}: the ${name} platform stops, though v${int(was.version)} can roll`,
              )
            }
          } else if d.move != #rolling {
            path->Array.push(`${at}: the ${name} platform changes version by ${(d.move :> string)}`)
          }
        }
        if d.ground->Array.includes(#provider) && !ons(d, #hosts) {
          path->Array.push(`${at}: the ${name} platform stands on machines without hosts turned on`)
        }
        // What its ground gives, RFC vr5lw: a footing of one kind of each class, for the platform's
        // control and each organization's alike, and extensions that give what the products need.
        let kinds = Resources.footingKinds(d)
        let held = Set.fromArray(
          kinds->Set.values->Array.fromIterator->Array.map(Resources.classOf),
        )
        [#compute, #storage, #database]->Array.forEach(
          c =>
            if !(held->Set.has(c)) {
              path->Array.push(`${at}: the ${name} platform's footing has no ${(c :> string)}`)
            },
        )
        if !(kinds->Set.has(#function)) {
          path->Array.push(
            `${at}: the ${name} platform's footing gives no effect function for its control`,
          )
        }
        if ons(d, #products) {
          let given = Resources.extensionKinds(d)
          Resources.needs->Array.forEach(
            n =>
              if (
                !(
                  n.any->Array.some(
                    k => given->Map.get(k)->Option.getOr(-1.) >= n.cpu->Option.getOr(0.),
                  )
                )
              ) {
                path->Array.push(
                  `${at}: the ${name} platform's extensions give none of ${n.any
                    ->Array.map(k => (k :> string))
                    ->Array.join(", ")}${switch n.cpu {
                    | Some(c) if c != 0. => ` with ${num(c)} ms of CPU a call`
                    | _ => ""
                    }}: ${n.why}`,
                )
              },
          )
        }
        Resources.unreached(d)->Array.forEach(
          r =>
            path->Array.push(
              `${at}: the ${name} platform's ${r} reaches the public network by no path`,
            ),
        )
      }
    )
    let a = step.foundation
    let b = step.production
    a.ground->Array.forEach(g =>
      if g == #home || g == #foundation {
        path->Array.push(`${at}: the foundation platform stands on ${(g :> string)}`)
      }
    )
    switch b {
    | Some(b) =>
      if a.version > b.version {
        path->Array.push(
          `${at}: the foundation platform runs v${int(
              a.version,
            )}, newer than the production platform's v${int(b.version)}`,
        )
      }
      if b.version - a.version > Steps.window {
        path->Array.push(
          `${at}: the production platform runs more than ${int(
              Steps.window,
            )} ahead of the foundation's pin`,
        )
      }
    | None => ()
    }
    let ran = steps->Array.slice(~start=0, ~end=i)
    switch before {
    | Some(before) =>
      if a.version != before.foundation.version {
        if !(ran->Array.some(s => s.production->Option.mapOr(false, e => e.version == a.version))) {
          path->Array.push(
            `${at}: the pin moves to v${int(a.version)}, which the production platform never ran`,
          )
        }
      }
      a.on->Array.forEach(f =>
        if (
          !ons(before.foundation, f) &&
          !(ran->Array.some(s => s.production->Option.mapOr(false, e => ons(e, f))))
        ) {
          path->Array.push(
            `${at}: the foundation platform turns on ${(f :> string)}, never proven on the production platform`,
          )
        }
      )
    | None => ()
    }
    if step.users == Some(#invited) && !ons(a, #metering) {
      path->Array.push(`${at}: others invited before the foundation platform meters its use`)
    }
    if before->Option.flatMap(b => b.users) == Some(#invited) && step.users != Some(#invited) {
      path->Array.push(`${at}: the invited sent away again`)
    }
    if before->Option.flatMap(b => b.foundation.plan) == Some(#paid) && a.plan != Some(#paid) {
      path->Array.push(`${at}: the paid plan given up again`)
    }
    if step.cells != None && b == None {
      path->Array.push(`${at}: cells, with no production platform`)
    }
  })
  if stops->Array.length > Steps.stops {
    path->Array.push(
      `the bootstrap stops ${int(stops->Array.length)} times, more than ${int(Steps.stops)}`,
    )
  }
  let kindsGiven = d =>
    Resources.extensionKinds(d)
    ->Map.keys
    ->Array.fromIterator
    ->Array.map(k => (k :> string))
    ->Array.toSorted(byText)
    ->Array.join(" ")
  dimension(
    "Bootstrap path",
    "From day one by hand, does every step hold, and does each deployment reach it by a move it may take?",
    path,
    ~notes=[
      steps->Array.mapWithIndex((s, i) =>
        `${int(i)}: foundation v${int(s.foundation.version)}${s.foundation.plan == Some(#paid)
            ? " paid"
            : ""}${switch s.production {
          | Some(e) => `, production v${int(e.version)}`
          | None => ""
          }}${switch s.cells {
          | Some(c) => `, cells ${(c :> string)}`
          | None => ""
          }} -- ${s.what}`
      ),
      steps->Array.mapWithIndex((s, i) =>
        `${int(i)}: extensions give, foundation ${kindsGiven(s.foundation)}${switch s.production {
          | Some(e) => `; production ${kindsGiven(e)}`
          | None => ""
          }}`
      ),
      [`planned stops: ${stops->orNone("; ")}`],
      steps == []
        ? ["no path given: it is the hosted platform's, monoflake/cloud's, RFC 8lkuv"]
        : [],
    ]->Array.flat,
    (),
  )
}
