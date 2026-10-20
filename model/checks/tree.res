/**
 * The tree, `docs/method.md`: no directory holds more than 16 entries, and none lies more than 5
 * deep, counted from a top-level directory or a package's root, its first subdirectory 1. Either
 * limit reached asks first whether it still fits, then whether the tree is cut where it should be.
 */
open Base

let deepest = 5
let widest = 16

/** What is generated or installed, never written, and so never counted. */
let ignored = name =>
  [".git", ".jj", "node_modules", "lib", ".DS_Store"]->Array.includes(name) ||
    name->String.endsWith(".res.mjs")

/** A directory whose manifest makes it a package, so its tree counts from 1 again. */
let manifests = ["Cargo.toml", "package.json", "rescript.json"]

let run = () => {
  let found = []
  let deep = ref(("", 0))
  let wide = ref(("", 0))
  let rec walk = (at: url, path, depth) => {
    let listed = entries(at, {withFileTypes: true})->Array.filter(e => !ignored(e->entryName))
    let count = listed->Array.length
    if count > Pair.second(wide.contents) {
      wide := (path, count)
    }
    if count > widest {
      found->Array.push(`${path}: ${int(count)} entries, past ${int(widest)}`)
    }
    let names = listed->Array.map(entryName)
    let package = path != "." && manifests->Array.some(m => names->Array.includes(m))
    listed->Array.forEach(e =>
      if e->isDirectory {
        let name = e->entryName
        let inner = path == "." ? name : `${path}/${name}`
        let d = path == "." ? 0 : package ? 1 : depth + 1
        if d > Pair.second(deep.contents) {
          deep := (inner, d)
        }
        if d == deepest + 1 {
          found->Array.push(`${inner}: ${int(d)} deep, past ${int(deepest)}`)
        }
        walk(urlIn(`${name}/`, at), inner, d)
      }
    )
  }
  walk(root, ".", 0)
  dimension(
    "Tree",
    `Does every directory hold at most ${int(widest)} entries and lie at most ${int(
        deepest,
      )} deep, from a top-level directory or a package's root?`,
    found,
    ~notes=[
      `deepest: ${Pair.first(deep.contents)}, ${int(Pair.second(deep.contents))}`,
      `widest: ${Pair.first(wide.contents)}, ${int(Pair.second(wide.contents))} entries`,
    ],
    (),
  )
}
