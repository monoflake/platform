/**
 * The code held to the model, RFC fhg6w: a component's code lies in its layer's directory under the
 * name the model gives it, in the language the model declares, and uses only libraries of that
 * language. A component not yet written is noted, never refused.
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

let manifests = [("Cargo.toml", #rust), ("rescript.json", #rescript)]

let run = () => {
  let found = []
  let expected = Map.make()
  let none = []
  designed->Array.forEach(((name, c)) =>
    switch c.language {
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
        switch expected->Map.get(path) {
        | None => found->Array.push(`${path}: no component of the model lies here`)
        | Some((name, language)) =>
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
      `not yet written: ${int(unwritten->Array.length)} components`,
      `no code of the platform's: ${none->orNone(", ")}`,
    ],
    (),
  )
}
