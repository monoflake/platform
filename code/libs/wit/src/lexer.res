/***
 * WIT's text as tokens, each where it begins, and the problems a file of it can have.
 */

type construct =
  | Resource
  | Own
  | Borrow
  | Include
  | Foreign(string)
  | Beyond(string)

type problem =
  | Refused(construct)
  | Unexpected({found: option<string>, expected: string})
  | Name(string)
  | Character(int)
  | Undefined(string)
  | Repeated(string)
  | Recursive(string)
  | Nested
  | NoWorld
  | SecondWorld

type refusal = {problem: problem, line: int, column: int}

type place = {line: int, column: int}

type primitive = [
  | #bool
  | #s8
  | #s16
  | #s32
  | #s64
  | #u8
  | #u16
  | #u32
  | #u64
  | #f32
  | #f64
  | #char
  | #string
]

type token =
  | Word(string)
  | Escaped(string)
  | Mark(string)
  | Number(string)
  | Version(string)
  | Text(string)
  | Bad(string)
  | End

type lexed = {token: token, place: place}

/** WIT's keywords, none of them a name unless it is escaped with `%`. */
let keywords = [
  "as",
  "async",
  "bool",
  "borrow",
  "char",
  "constructor",
  "enum",
  "export",
  "f32",
  "f64",
  "flags",
  "from",
  "func",
  "future",
  "import",
  "include",
  "interface",
  "list",
  "map",
  "option",
  "own",
  "package",
  "record",
  "resource",
  "result",
  "s16",
  "s32",
  "s64",
  "s8",
  "static",
  "stream",
  "string",
  "tuple",
  "type",
  "u16",
  "u32",
  "u64",
  "u8",
  "use",
  "variant",
  "with",
  "world",
]

/** A kebab-case label, each word all lowercase or all uppercase, the first opening on a letter. */
let label = /^([a-z][0-9a-z]*|[A-Z][0-9A-Z]*)(-([0-9a-z]+|[0-9A-Z]+))*$/

/** Control characters but tab, newline and return, and the bidirectional overrides. */
let forbidden = c =>
  (c < 0x20 && c != 9 && c != 10 && c != 13) ||
  c >= 0x7f && c <= 0x9f ||
  c >= 0x202a && c <= 0x202e ||
  (c >= 0x2066 && c <= 0x2069)

let isLetter = c => (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
let isDigit = c => c >= 48 && c <= 57
let marks = "=,:;(){}<>*/.@_"

/** Every token of a text, the end last, a character it forbids reported and passed over. */
let lex = (text, refuse) => {
  let tokens = []
  let at = ref(0)
  let line = ref(1)
  let column = ref(1)
  let length = String.length(text)
  let code = i => text->String.charCodeAt(i)->Option.getOr(-1)
  let step = () => {
    let c = code(at.contents)
    at := at.contents + 1
    if c == 10 {
      line := line.contents + 1
      column := 1
    } else if c < 0xdc00 || c > 0xdfff {
      // A low surrogate ends a code point its high one counted already.
      column := column.contents + 1
    }
  }
  let passed = place => {
    let c = code(at.contents)
    if forbidden(c) {
      refuse(Character(c), place())
    }
    step()
  }
  let here = () => {line: line.contents, column: column.contents}
  let push = (token, place) => tokens->Array.push({token, place})
  while at.contents < length {
    let c = code(at.contents)
    let next = code(at.contents + 1)
    let place = here()
    let start = at.contents
    if c == 32 || c == 9 || c == 10 || c == 13 {
      step()
    } else if c == 47 && next == 47 {
      while at.contents < length && code(at.contents) != 10 {
        passed(here)
      }
    } else if c == 47 && next == 42 {
      step()
      step()
      let depth = ref(1)
      while depth.contents > 0 && at.contents < length {
        let c = code(at.contents)
        let next = code(at.contents + 1)
        if c == 47 && next == 42 {
          step()
          step()
          depth := depth.contents + 1
        } else if c == 42 && next == 47 {
          step()
          step()
          depth := depth.contents - 1
        } else {
          passed(here)
        }
      }
      if depth.contents > 0 {
        push(Bad("/*"), place)
      }
    } else if forbidden(c) {
      refuse(Character(c), place)
      step()
    } else if isLetter(c) || c == 37 {
      step()
      let continues = () => {
        let c = code(at.contents)
        isLetter(c) || isDigit(c) || (c == 45 && code(at.contents + 1) != 62)
      }
      while at.contents < length && continues() {
        step()
      }
      let word = text->String.slice(~start, ~end=at.contents)
      let escaped = c == 37
      let name = escaped ? word->String.slice(~start=1) : word
      if !(label->RegExp.test(name)) {
        refuse(Name(name), place)
      }
      push(escaped ? Escaped(name) : Word(name), place)
    } else if isDigit(c) {
      let afterAt = tokens->Array.at(-1)->Option.map(t => t.token) == Some(Mark("@"))
      let continues = () => {
        let c = code(at.contents)
        let then = code(at.contents + 1)
        // A dot ends a version where no letter or digit follows it, as in `@0.2.0.{name}`.
        let dot = c == 46 && (isLetter(then) || isDigit(then))
        isDigit(c) || (afterAt && (isLetter(c) || dot || c == 43 || c == 45))
      }
      while at.contents < length && continues() {
        step()
      }
      let digits = text->String.slice(~start, ~end=at.contents)
      push(afterAt ? Version(digits) : Number(digits), place)
    } else if c == 45 && next == 62 {
      step()
      step()
      push(Mark("->"), place)
    } else if marks->String.includes(String.fromCharCode(c)) {
      step()
      push(Mark(String.fromCharCode(c)), place)
    } else if c == 34 {
      step()
      while at.contents < length && code(at.contents) != 34 && code(at.contents) != 10 {
        if code(at.contents) == 92 {
          step()
        }
        passed(here)
      }
      if code(at.contents) == 34 {
        step()
        push(Text(text->String.slice(~start=start + 1, ~end=at.contents - 1)), place)
      } else {
        push(Bad("\""), place)
      }
    } else {
      step()
      if c >= 0xd800 && c <= 0xdbff {
        step()
      }
      push(Bad(text->String.slice(~start, ~end=at.contents)), place)
    }
  }
  push(End, here())
  tokens
}
