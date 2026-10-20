/**
 * The code held to the model, RFC fhg6w: a component's code lies in its layer's directory under the
 * name the model gives it, in the language the model declares, and uses only libraries of that
 * language. A driver declares none: it lies in its layer's `driver/` as a directory of its
 * implementations, one a kind its grounds give, each in its own, `model/ground/drivers.res`. A
 * component not yet written is noted, never refused.
 */
open Base

/** The directory each layer's components lie in. */
let group = layer =>
  switch layer {
  | 1 => Some("apps")
  | 0 => Some("products")
  | -1 => Some("primitives")
  | -2 => Some("substrate")
  | -3 => Some("platform")
  | _ => None
  }

/** A half in a name is the layer's already, so it is no part of the directory's. */
let dirName = name => name->String.replace("(organization)", "")->String.replace("(platform)", "")

/** A driver's directory is its name without the word its parent already says: `cloudflare-driver`
 * lies at `driver/cloudflare`. A driver whose name ends otherwise has none. */
let driverDir = name =>
  name->String.endsWith("-driver")
    ? Some(name->String.slice(~start=0, ~end=String.length(name) - String.length("-driver")))
    : None

let manifests = [("Cargo.toml", #rust), ("rescript.json", #rescript)]

let run = () => {
  let found = []
  let expected = Map.make()
  let none = []
  designed->Array.forEach(((name, c)) =>
    switch c.language {
    | None if Drivers.drivers->Dict.get(name) != None =>
      switch (group(c.layer), Drivers.drivers->Dict.get(name), driverDir(name)) {
      | (_, _, None) => found->Array.push(`${name}: a driver whose name does not end in -driver`)
      | (Some(g), Some(d), Some(dir)) =>
        d.implements->Array.forEach(i =>
          expected->Map.set(
            `code/${g}/driver/${dir}/${(i.kind :> string)}`,
            (`${name} ${(i.kind :> string)}`, i.language),
          )
        )
        let given = Set.fromArray(
          d.grounds
          ->Array.flatMap(Resources.groundOf)
          ->Array.flatMap(n => Resources.get(Resources.resources, n).gives),
        )
        let made = Set.fromArray(d.implements->Array.map(i => i.kind))
        given->Set.forEach(k =>
          if !(made->Set.has(k)) {
            found->Array.push(`${name}: its grounds give ${(k :> string)}, which it implements not`)
          }
        )
        made->Set.forEach(k =>
          if !(given->Set.has(k)) {
            found->Array.push(`${name}: implements ${(k :> string)}, which its grounds give not`)
          }
        )
      | _ => found->Array.push(`${name}: a driver at layer ${int(c.layer)}, which has no directory`)
      }
    | None => none->Array.push(name)
    | Some(language) =>
      switch group(c.layer) {
      | None =>
        found->Array.push(
          `${name}: written in a language, yet layer ${int(c.layer)} has no directory`,
        )
      | Some(g) => expected->Map.set(`code/${g}/${dirName(name)}`, (name, language))
      }
      c.uses->Array.forEach(u =>
        switch Libraries.libraries->Dict.get(u) {
        | Some(l) if l.language != language =>
          found->Array.push(
            `${name} uses ${u}, of ${(l.language :> string)}, not ${(language :> string)}`,
          )
        | _ => ()
        }
      )
    }
  )
  let written = []
  ["apps", "products", "primitives", "substrate", "platform"]->Array.forEach(g => {
    let at = urlIn(`code/${g}/`, root)
    if existsSync(at) {
      entries(at, {withFileTypes: true})
      ->Array.filter(e => e->isDirectory)
      ->Array.forEach(e => {
        let path = `code/${g}/${e->entryName}`
        let check = (path, name, language: [#rust | #rescript]) => {
          let inside = urlIn(`${path}/`, root)
          let files = entries(inside, {withFileTypes: true})->Array.map(entryName)
          if files->Array.length > 0 {
            written->Array.push(name)
          }
          manifests->Array.forEach(
            ((m, l)) =>
              if files->Array.includes(m) && l != language {
                found->Array.push(
                  `${path}: a ${m}, yet ${name} is declared ${(language :> string)}`,
                )
              },
          )
        }
        let inside = path => entries(urlIn(`${path}/`, root), {withFileTypes: true})
        switch expected->Map.get(path) {
        | None if e->entryName == "driver" =>
          inside(path)->Array.forEach(
            v => {
              let at = `${path}/${v->entryName}`
              if !(v->isDirectory) {
                found->Array.push(`${at}: driver/ holds drivers alone`)
              } else if (
                !(
                  expected
                  ->Map.keys
                  ->Array.fromIterator
                  ->Array.some(k => k->String.startsWith(`${at}/`))
                )
              ) {
                found->Array.push(`${at}: no driver of the model lies here`)
              } else {
                inside(at)->Array.forEach(
                  k =>
                    if k->isDirectory {
                      let inner = `${at}/${k->entryName}`
                      switch expected->Map.get(inner) {
                      | Some((name, language)) => check(inner, name, language)
                      | None => found->Array.push(`${inner}: no kind its driver implements`)
                      }
                    } else {
                      found->Array.push(
                        `${at}/${k->entryName}: a driver holds its implementations alone`,
                      )
                    },
                )
              }
            },
          )
        | None => found->Array.push(`${path}: no component of the model lies here`)
        | Some((name, language)) => check(path, name, language)
        }
      })
    }
  })
  let unwritten =
    expected
    ->Map.values
    ->Array.fromIterator
    ->Array.map(((n, _)) => n)
    ->Array.filter(n => !(written->Array.includes(n)))
  dimension(
    "Code",
    "Does each component's code lie in its layer's directory, named as the model names it, in the language the model declares, using only libraries of that language?",
    found,
    ~notes=[
      `written: ${written->orNone(", ")}`,
      `not yet written: ${int(unwritten->Array.length)}, components and implementations`,
      `no code of the platform's: ${none->orNone(", ")}`,
      ...Drivers.drivers
      ->Dict.toArray
      ->Array.map(((n, d)) =>
        `${n}: ${d.implements
          ->Array.map(i => `${(i.kind :> string)} in ${(i.language :> string)}`)
          ->Array.join(", ")}`
      ),
    ],
    (),
  )
}
