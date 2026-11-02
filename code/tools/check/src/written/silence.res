/** Nothing only the other repository holds is named here, `model/names/withheld.res`, RFC 8lkuv. */
open Base

let rec files = path =>
  if existsSync(urlIn(`${path}/`, root)) && !(path->String.includes(".")) {
    entries(urlIn(`${path}/`, root), {withFileTypes: true})->Array.flatMap(e =>
      files(`${path}/${e->entryName}`)
    )
  } else if (
    path->String.endsWith(".md") ||
      (path->String.endsWith(".res") && !(path->String.endsWith(".res.mjs")))
  ) {
    [path]
  } else {
    []
  }

/**
 * A name as a word of its own, plural or not, a method called on a module so spelled being none.
 */
let whole = name =>
  RegExp.fromString(
    "(^|[^\\w])" ++ name->String.replaceRegExp(/[.*+?^${}()|[\]\\]/g, "\\$&") ++ "s?(?![\\w.])",
    ~flags="i",
  )

let run = () => {
  let found = []
  Withheld.read
  ->Array.flatMap(files)
  ->Array.filter(path => !(Withheld.skipped->Array.includes(path)))
  ->Array.toSorted(byText)
  ->Array.forEach(path =>
    readFileSync(urlIn(path, root))
    ->String.split("\n")
    ->Array.forEachWithIndex((line, at) => {
      Withheld.names->Array.forEach(
        name =>
          if whole(name)->RegExp.test(line) {
            found->Array.push(`${path}:${int(at + 1)}: ${name}`)
          },
      )
    })
  )
  dimension(
    "Silence",
    "Is nothing only monoflake/cloud holds named here, so this half says what it needs of a role and stops?",
    found,
    (),
  )
}
