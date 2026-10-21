/*** How a name of `model/contracts.json` is written in ReScript, as `names.rs` does in Rust. */
open Model

/** The words ReScript's parser refuses as a field's or a value's name. */
let keywords = [
  "and",
  "as",
  "assert",
  "await",
  "constraint",
  "else",
  "exception",
  "external",
  "false",
  "for",
  "if",
  "in",
  "include",
  "let",
  "module",
  "mutable",
  "of",
  "open",
  "private",
  "rec",
  "switch",
  "true",
  "try",
  "type",
  "when",
  "while",
]

/** The modules the written source names beside its own, which no type's module may hide. */
let reserved = ["Wire", "Malformed", "Codec", "JSON", "Uint8Array", "Shell", "Answer", "Interface"]

let words = name => name->String.replaceAll("-", "_")->String.split("_")
let capital = word => word->String.charAt(0)->String.toUpperCase ++ word->String.slice(~start=1)

let upperName = /^[A-Z][A-Za-z0-9]*$/
let lowerName = /^[a-z][A-Za-z0-9]*$/
let fieldName = /^[a-z][A-Za-z0-9_]*$/

let upper = (name, at) => {
  let upper = words(name)->Array.map(capital)->Array.join("")
  upperName->RegExp.test(upper) ? upper : fail(at, "a name of letters and digits")
}

let lower = (name, at) => {
  let lower = switch words(name) {
  | [] => ""
  | words => words->Array.mapWithIndex((word, i) => i == 0 ? word : capital(word))->Array.join("")
  }
  if !(lowerName->RegExp.test(lower)) {
    fail(at, "a name of letters and digits, opening with a lowercase one")
  }
  keywords->Array.includes(lower) ? `${lower}_` : lower
}

/** A field's name in ReScript, a keyword's followed by an underscore. */
let label = (name, at) => {
  if !(fieldName->RegExp.test(name)) {
    fail(at, "a name of lowercase letters, digits and underscores")
  }
  keywords->Array.includes(name) ? `${name}_` : name
}

let quote = text => JSON.stringify(JSON.String(text))

/** Each of `names` once, or where the second stands. */
let distinct = (names, at, expected) =>
  names->Array.forEachWithIndex((name, i) =>
    if names->Array.slice(~start=0, ~end=i)->Array.includes(name) {
      fail(at(i), expected)
    }
  )
