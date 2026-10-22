/***
 * The reading of tokens one at a time, a type among them, a token out of place throwing `Stop`
 * once it is reported.
 */

open Lexer

/** A type as written, a refused one already reported where it was read. */
type rec ty =
  | Primitive(primitive)
  | Named(string, place)
  | ListOf(ty)
  | OptionOf(ty, place)
  | TupleOf(array<ty>)
  | ResultOf(option<ty>, option<ty>)
  | Refused

type named = {name: string, place: place}

/** A version as semantic versioning writes one, its prerelease and its build optional. */
let semver = RegExp.fromString(
  "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)" ++ "(-[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?(\\+[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?$",
)

exception Stop

type state = {tokens: array<lexed>, mutable at: int, refusals: array<refusal>}

let refuse = (s, problem, place: place) =>
  s.refusals->Array.push({problem, line: place.line, column: place.column})

let peek = (s, n) =>
  switch s.tokens->Array.get(s.at + n) {
  | Some(t) => t
  | None =>
    switch s.tokens->Array.at(-1) {
    | Some(t) => t
    | None => {token: End, place: {line: 1, column: 1}}
    }
  }

let advance = s =>
  if s.at < s.tokens->Array.length - 1 {
    s.at = s.at + 1
  }

let found = token =>
  switch token {
  | Word(w) | Mark(w) | Number(w) | Version(w) | Bad(w) => Some(w)
  | Escaped(w) => Some(`%${w}`)
  | Text(t) => Some(`"${t}"`)
  | End => None
  }

let unexpected = (s, expected) => {
  let t = peek(s, 0)
  refuse(s, Unexpected({found: found(t.token), expected}), t.place)
  throw(Stop)
}

let isMark = (s, m) => peek(s, 0).token == Mark(m)
let isWord = (s, w) => peek(s, 0).token == Word(w)

let expect = (s, m) => isMark(s, m) ? advance(s) : unexpected(s, `\`${m}\``)

let isName = token =>
  switch token {
  | Word(w) => !(keywords->Array.includes(w))
  | Escaped(_) => true
  | Mark(_) | Number(_) | Version(_) | Text(_) | Bad(_) | End => false
  }

let name = (s, ~expected="a name") => {
  let t = peek(s, 0)
  switch t.token {
  | Word(w) | Escaped(w) if isName(t.token) =>
    advance(s)
    {name: w, place: t.place}
  | Word(_) | Escaped(_) | Mark(_) | Number(_) | Version(_) | Text(_) | Bad(_) | End =>
    unexpected(s, expected)
  }
}

/** The tokens from an opening mark to its closing one, nested, passed over. */
let skip = (s, opening, closing) => {
  expect(s, opening)
  let depth = ref(1)
  while depth.contents > 0 {
    switch peek(s, 0).token {
    | End => unexpected(s, `\`${closing}\``)
    | Mark(m) if m == opening => depth := depth.contents + 1
    | Mark(m) if m == closing => depth := depth.contents - 1
    | Word(_) | Escaped(_) | Mark(_) | Number(_) | Version(_) | Text(_) | Bad(_) => ()
    }
    advance(s)
  }
}

/** Items to a closing mark, comma separated, a trailing comma taken, at least one where asked. */
let sequence = (s, closing, item, ~least=0, ~expected) => {
  let items = []
  if least > 0 && isMark(s, closing) {
    unexpected(s, expected)
  }
  while !isMark(s, closing) {
    items->Array.push(item())
    if isMark(s, ",") {
      advance(s)
    } else if !isMark(s, closing) {
      unexpected(s, `\`,\` or \`${closing}\``)
    }
  }
  advance(s)
  items
}

/** Each name repeated in a list reported where it is repeated. */
let unique = (s, names: array<named>) =>
  names->Array.forEachWithIndex((n, at) =>
    if names->Array.findIndex(m => m.name == n.name) != at {
      refuse(s, Repeated(n.name), n.place)
    }
  )

let version = s => {
  expect(s, "@")
  switch peek(s, 0).token {
  | Version(v) if semver->RegExp.test(v) =>
    advance(s)
    v
  | Word(_) | Escaped(_) | Mark(_) | Number(_) | Version(_) | Text(_) | Bad(_) | End =>
    unexpected(s, "a semantic version")
  }
}

/** A use path, an interface of this file by its name or another package's by its whole path. */
let path = s => {
  let first = name(s)
  if isMark(s, ":") {
    let text = ref(first.name)
    while isMark(s, ":") {
      advance(s)
      text := `${text.contents}:${name(s).name}`
    }
    while isMark(s, "/") {
      advance(s)
      text := `${text.contents}/${name(s).name}`
    }
    if isMark(s, "@") {
      text := `${text.contents}@${version(s)}`
    }
    Error(text.contents)
  } else {
    Ok(first)
  }
}

let gates = s =>
  while isMark(s, "@") {
    let place = peek(s, 0).place
    advance(s)
    let gate = switch peek(s, 0).token {
    | Word(w) => w
    | Escaped(_) | Mark(_) | Number(_) | Version(_) | Text(_) | Bad(_) | End =>
      unexpected(s, "a gate")
    }
    advance(s)
    refuse(s, Refused(Beyond(`@${gate}`)), place)
    if isMark(s, "(") {
      skip(s, "(", ")")
    }
  }

let primitives: array<primitive> = [
  #bool,
  #s8,
  #s16,
  #s32,
  #s64,
  #u8,
  #u16,
  #u32,
  #u64,
  #f32,
  #f64,
  #char,
  #string,
]

let rec ty = s => {
  let t = peek(s, 0)
  let refused = construct => {
    refuse(s, Refused(construct), t.place)
    Refused
  }
  let within = parse => {
    expect(s, "<")
    let inner = parse()
    expect(s, ">")
    inner
  }
  switch t.token {
  | Word(w) if keywords->Array.includes(w) =>
    advance(s)
    switch (primitives->Array.find(p => (p :> string) == w), w) {
    | (Some(p), _) => Primitive(p)
    | (None, "list") =>
      within(() => {
        let element = ty(s)
        if isMark(s, ",") {
          advance(s)
          switch peek(s, 0).token {
          | Number(_) => advance(s)
          | Word(_) | Escaped(_) | Mark(_) | Version(_) | Text(_) | Bad(_) | End =>
            unexpected(s, "a length")
          }
          refused(Beyond("fixed-length list"))
        } else {
          ListOf(element)
        }
      })
    | (None, "option") => within(() => OptionOf(ty(s), t.place))
    | (None, "tuple") =>
      expect(s, "<")
      TupleOf(sequence(s, ">", () => ty(s), ~least=1, ~expected="a type"))
    | (None, "result") =>
      if isMark(s, "<") {
        within(() => {
          let success = if isMark(s, "_") {
            advance(s)
            if !isMark(s, ",") {
              unexpected(s, "`,`")
            }
            None
          } else {
            Some(ty(s))
          }
          let failure = if isMark(s, ",") {
            advance(s)
            Some(ty(s))
          } else {
            None
          }
          ResultOf(success, failure)
        })
      } else {
        ResultOf(None, None)
      }
    | (None, "map") =>
      within(() => {
        let _ = ty(s)
        expect(s, ",")
        let _ = ty(s)
      })
      refused(Beyond("map"))
    | (None, ("future" | "stream") as w) =>
      if isMark(s, "<") {
        within(() => ty(s))->ignore
      }
      refused(Beyond(w))
    | (None, ("own" | "borrow") as w) =>
      within(() => name(s))->ignore
      refused(w == "own" ? Own : Borrow)
    | (None, _) =>
      s.at = s.at - 1
      unexpected(s, "a type")
    }
  | Word(_) | Escaped(_) =>
    let n = name(s)
    Named(n.name, n.place)
  | Mark(_) | Number(_) | Version(_) | Text(_) | Bad(_) | End => unexpected(s, "a type")
  }
}
