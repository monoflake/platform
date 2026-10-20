/**
 * The code held to the model, RFC fhg6w: a component's code lies in its layer's directory under the
 * name the model gives it, in the language the model declares, and uses only libraries written in
 * that language. A driver declares none: it lies in its layer's `driver/` as a directory of its
 * implementations, one a kind its grounds give, each in its own, and of its management, in the
 * language its ground asks, `model/ground/drivers.res`. A library lies in `code/libs/`, a manifest
 * for each of its languages. A package is named as the model names what it holds, `@blueprint/` led
 * where it is ReScript's, and namespaced, and MIT OR Apache-2.0, the root's two texts. What
 * `monoflake/cloud` keeps lies nowhere here. Anything not yet written is noted, never refused.
 */
open Base

type lang = [#rust | #rescript]

/** What a directory is to hold: what of the model, in which languages, under which package name. */
type held = {name: string, languages: array<lang>, package: string, license: string}

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

/** A package's name is the model's, what is in parentheses written after a hyphen, as no package
 * name holds a parenthesis: `control-organization`, `driver-machine`. */
let packageName = name => name->String.replace("(", "-")->String.replace(")", "")

/** A driver is named `driver(...)`, its vendor in parentheses, and lies at `driver/` and that name,
 * as `control(organization)` names what it is first and which after: `driver(cloudflare)` lies at
 * `driver/cloudflare`. A driver named otherwise has none. */
let driverDir = name =>
  name->String.startsWith("driver(") && name->String.endsWith(")")
    ? Some(name->String.slice(~start=String.length("driver("), ~end=String.length(name) - 1))
    : None

/** A library's name in the model carries a mark, which its directory does not. */
let libraryDir = name => name->String.replace("*", "")

let manifests: array<(string, lang)> = [("Cargo.toml", #rust), ("rescript.json", #rescript)]

let text = (l: lang) => (l :> string)

let jsonName = path =>
  switch JSON.parseOrThrow(readFileSync(urlIn(path, root))) {
  | Object(d) => (d->Dict.get("name"), d->Dict.get("namespace"))
  | _ => (None, None)
  }

/**
 * A key's text in a Cargo.toml's `[package]`, read a line at a time, as nothing else of it is
 * asked.
 */
let crateKey = (path, key) => {
  let section = ref("")
  let found = ref(None)
  readFileSync(urlIn(path, root))
  ->String.split("\n")
  ->Array.forEach(line => {
    let line = line->String.trim
    if line->String.startsWith("[") {
      section := line
    } else if (
      section.contents == "[package]" &&
        line->String.split("=")->Array.get(0)->Option.map(String.trim) == Some(key)
    ) {
      found := line->String.split("\"")->Array.get(1)
    }
  })
  found.contents
}

let crateName = path => crateKey(path, "name")

let jsonLicense = path =>
  switch JSON.parseOrThrow(readFileSync(urlIn(path, root))) {
  | Object(d) => d->Dict.get("license")
  | _ => None
  }

let run = () => {
  let found = []
  let expected: Map.t<string, held> = Map.make()
  let none = []
  designed->Array.forEach(((name, c)) =>
    switch c.language {
    | _ if Components.elsewhere(name) => ()
    | None if Drivers.drivers->Dict.get(name) != None =>
      switch (group(c.layer), Drivers.drivers->Dict.get(name), driverDir(name)) {
      | (_, _, None) => found->Array.push(`${name}: a driver not named driver(...)`)
      | (Some(g), Some(d), Some(dir)) =>
        d.implements->Array.forEach(i =>
          expected->Map.set(
            `code/${g}/driver/${dir}/${(i.kind :> string)}`,
            {
              name: `${name} ${(i.kind :> string)}`,
              languages: [i.language],
              package: `${packageName(name)}-${(i.kind :> string)}`,
              license: Components.permissive,
            },
          )
        )
        expected->Map.set(
          `code/${g}/driver/${dir}/management`,
          {
            name: `${name} management`,
            languages: [d.management],
            package: `${packageName(name)}-management`,
            license: Components.permissive,
          },
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
      | Some(g) =>
        expected->Map.set(
          `code/${g}/${dirName(name)}`,
          {
            name,
            languages: [language],
            package: packageName(name),
            license: Components.permissive,
          },
        )
      }
      c.uses->Array.forEach(u =>
        switch Libraries.libraries->Dict.get(u) {
        | Some(l) if !(l.languages->Array.includes(language)) =>
          found->Array.push(
            `${name} uses ${u}, of ${l.languages->Array.map(text)->Array.join(" and ")}, not ${text(
                language,
              )}`,
          )
        | _ => ()
        }
      )
    }
  )
  Libraries.libraries->Dict.forEachWithKey((l, name) =>
    expected->Map.set(
      `code/libs/${libraryDir(name)}`,
      {name, languages: l.languages, package: libraryDir(name), license: Components.permissive},
    )
  )
  let written = []
  // A directory written holds each language's manifest it is declared in, and no other, each naming
  // it.
  let check = (path, h: held) => {
    let files = entries(urlIn(`${path}/`, root), {withFileTypes: true})->Array.map(entryName)
    if files->Array.length > 0 {
      written->Array.push(h.name)
      manifests->Array.forEach(((m, l)) =>
        switch (files->Array.includes(m), h.languages->Array.includes(l)) {
        | (true, false) =>
          found->Array.push(
            `${path}: a ${m}, yet ${h.name} is declared ${h.languages
              ->Array.map(text)
              ->Array.join(" and ")}`,
          )
        | (false, true) => found->Array.push(`${path}: no ${m}, yet ${h.name} is ${text(l)}`)
        | _ => ()
        }
      )
      if files->Array.includes("Cargo.toml") {
        switch crateName(`${path}/Cargo.toml`) {
        | Some(n) if n == h.package => ()
        | _ => found->Array.push(`${path}/Cargo.toml: no crate named ${h.package}`)
        }
        if crateKey(`${path}/Cargo.toml`, "license") != Some(h.license) {
          found->Array.push(`${path}/Cargo.toml: no license ${h.license}`)
        }
      }
      if (
        files->Array.includes("package.json") &&
          jsonLicense(`${path}/package.json`) != Some(JSON.String(h.license))
      ) {
        found->Array.push(`${path}/package.json: no license ${h.license}`)
      }
      if files->Array.includes("rescript.json") {
        let scoped = `@blueprint/${h.package}`
        switch jsonName(`${path}/rescript.json`) {
        | (Some(String(n)), Some(Boolean(true))) if n == scoped => ()
        | _ => found->Array.push(`${path}/rescript.json: no package named ${scoped} and namespaced`)
        }
        switch files->Array.includes("package.json")
          ? jsonName(`${path}/package.json`)
          : (None, None) {
        | (Some(String(n)), _) if n == scoped => ()
        | _ => found->Array.push(`${path}: no package.json named ${scoped}, which pnpm links by`)
        }
      }
    }
  }
  let inside = path => entries(urlIn(`${path}/`, root), {withFileTypes: true})
  ["apps", "products", "primitives", "substrate", "platform", "libs"]->Array.forEach(g => {
    let at = urlIn(`code/${g}/`, root)
    if existsSync(at) {
      inside(`code/${g}`)
      ->Array.filter(e => e->isDirectory)
      ->Array.forEach(e => {
        let path = `code/${g}/${e->entryName}`
        switch expected->Map.get(path) {
        | None if g == "substrate" && e->entryName == "driver" =>
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
                      | Some(h) => check(inner, h)
                      | None =>
                        found->Array.push(
                          `${inner}: neither its management nor a kind it implements`,
                        )
                      }
                    } else {
                      found->Array.push(
                        `${at}/${k->entryName}: a driver holds its implementations and its management alone`,
                      )
                    },
                )
              }
            },
          )
        | None => found->Array.push(`${path}: nothing of the model lies here`)
        | Some(h) => check(path, h)
        }
      })
    }
  })
  // The root holds the two texts as Rust's projects do, and nothing else of licensing, RFC fhg6w.
  ["LICENSE-MIT", "LICENSE-APACHE"]->Array.forEach(t =>
    if !existsSync(urlIn(t, root)) {
      found->Array.push(`no ${t} at the root`)
    }
  )
  ["LICENSE", "LICENSES/", "REUSE.toml"]->Array.forEach(t =>
    if existsSync(urlIn(t, root)) {
      found->Array.push(`${t}: the two texts at the root say all of it`)
    }
  )
  let unwritten =
    expected
    ->Map.values
    ->Array.fromIterator
    ->Array.filter(h => !(written->Array.includes(h.name)))
  dimension(
    "Code",
    "Does each component's code lie in its layer's directory, named as the model names it, in the language the model declares, using only libraries written in it, each package named and namespaced as the model names it?",
    found,
    ~notes=[
      `written: ${written->orNone(", ")}`,
      `not yet written: ${int(
          unwritten->Array.length,
        )}, components, implementations, managements and libraries`,
      `no code of the platform's: ${none->orNone(", ")}`,
      ...Drivers.drivers
      ->Dict.toArray
      ->Array.map(((n, d)) =>
        `${n}: management in ${text(d.management)}; ${d.implements
          ->Array.map(i => `${(i.kind :> string)} in ${text(i.language)}`)
          ->Array.join(", ")}`
      ),
    ],
    (),
  )
}
