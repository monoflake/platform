/**
 * The reserved names, `model/names/reserved.res`: every label the platform's own organizations hold
 * is reserved, so no one takes it first, and each is a label as v7v3w writes one.
 */
open Base

let isLabel = s =>
  s->String.length >= 3 &&
  s->String.length <= 16 &&
  /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/->RegExp.test(s) &&
  !(s->String.startsWith("xn--")) &&
  !(/^[0-9a-f]{8}$/->RegExp.test(s))

let run = () => {
  let found = []
  let vendored: array<string> = switch JSON.parseOrThrow(
    readFileSync(urlIn(Reserved.vendored, root)),
  ) {
  | Array(names) => names->Array.filterMap(JSON.Decode.string)
  | _ =>
    found->Array.push(`${Reserved.vendored}: no list of names`)
    []
  }
  let reserved = Set.fromArray(
    [vendored, Reserved.mailboxes, Reserved.words, Reserved.providers]->Array.flat,
  )
  Reserved.own->Array.forEach(o => {
    if !(reserved->Set.has(o.label)) {
      found->Array.push(
        `${o.label}: the platform's own, yet not reserved, so anyone may take it first`,
      )
    }
    if !isLabel(o.label) {
      found->Array.push(`${o.label}: not a label as v7v3w writes one`)
    }
  })
  dimension(
    "Names",
    "Is every label the platform's own organizations hold reserved, so the ordinary flow gives it to no one, and written as a label is?",
    found,
    ~notes=[
      `reserved: ${int(reserved->Set.size)} names, of ${int(
          vendored->Array.length,
        )} vendored, ${int(Reserved.mailboxes->Array.length)} of RFC 2142's, ${int(
          Reserved.words->Array.length,
        )} of the platform's words and ${int(Reserved.providers->Array.length)} providers'`,
      `given by the operator: ${Reserved.own->Array.map(o => o.label)->Array.join(", ")}`,
    ],
    (),
  )
}
