/**
 * The two platforms' names, RFC 94y0d: foundation, production, internal and external stand only
 * before platform, never alone, in what the design is written in. The lessons quote others, and are
 * not read.
 */
open Base

let run = () => {
  let found = []
  let alone = /\b(foundation|production|internal|external)\b(?!(\s+and\s+(foundation|production|internal|external))?\s+platforms?\b)/gi
  let read = path => {
    let text = readFileSync(urlIn(path, root))
    let go = ref(true)
    while go.contents {
      switch alone->RegExp.exec(text) {
      | Some(m) =>
        let at = text->String.slice(~start=0, ~end=m->RegExp.Result.index)
        let line = at->String.split("\n")->Array.length
        found->Array.push(`${path}:${int(line)}: ${m->RegExp.Result.fullMatch} stands alone`)
      | None => go := false
      }
    }
  }
  let rfcs = urlIn("docs/rfcs/", root)
  readdirSync(rfcs)
  ->Array.filter(f => f->String.endsWith(".md"))
  ->Array.toSorted(byText)
  ->Array.forEach(f => read(`docs/rfcs/${f}`))
  ["docs/method.md", "docs/scope.md", "AGENTS.md"]->Array.forEach(read)
  dimension(
    "Words",
    "Is each platform named as a platform, foundation, production, internal and external never alone?",
    found,
    (),
  )
}
