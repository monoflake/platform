/***
 * `Generate` held to `model/contracts.json` and to contracts of its own: what it writes, the same
 * twice over, types that name one another, a keyword's field, and where what it cannot write is.
 */
open Node

let written = text => Generate.read(text)->Result.flatMap(Generate.rescript)

/** Contracts holding `types` beside a `failure` of one choice. */
let contracts = (~types="", ~reasons="[]", ~interfaces="{}") => {
  let failure = `"failure": {"enum": [{"name": "rejected", "code": 1}], "ordered": false}`
  let types = types == "" ? failure : `${failure}, ${types}`
  `{"shell": [], "types": {${types}}, "reasons": ${reasons}, "calling": [], "interfaces": ${interfaces}}`
}

let source = text =>
  switch written(text) {
  | Ok(source) => source
  | Error({at, expected}) => JsError.throwWithMessage(`at ${at}: ${expected}`)
  }

test("model/contracts.json is written, the same twice over", () => {
  let text = readFileSync(fromRoot("model/contracts.json"))
  let once = source(text)
  deepEqual(source(text), once)
  [
    "module BucketKind = {",
    "module Rights = {",
    "module Shell = {",
    "module Interface = {",
    "let reasons: array<reason> = ",
    "let calling: array<reason> = ",
    "let jsonToCbor = ",
    "let cborToJson = ",
  ]->Array.forEach(expected => ok(once->String.includes(expected), ~message=expected))
})

test("types that name one another are written as recursive modules, the rest as modules", () => {
  let written = source(
    contracts(
      ~types=`"tree": {"record": [{"name": "nodes", "key": 1, "shape": {"list": {"type": "node"}}}]},
        "node": {"union": {"tag": "name", "cases": [
          {"name": "leaf", "code": 1, "fields": []},
          {"name": "branch", "code": 2, "fields": [{"name": "tree", "key": 1, "shape": {"type": "tree"}}]}
        ]}},
        "leaf": {"record": [{"name": "self", "key": 1, "shape": {"type": "leaf"}, "optional": true}]},
        "plain": {"record": []}`,
    ),
  )
  ok(written->String.includes("module rec Tree: {"))
  ok(written->String.includes("and Node: {"))
  ok(written->String.includes("module rec Leaf: {"))
  ok(written->String.includes("module Plain = {"))
})

test("a keyword names its field followed by an underscore, under @as", () => {
  let written = source(
    contracts(
      ~types=`"typed": {"record": [{"name": "type", "key": 1, "shape": {"prim": "string"}}]}`,
    ),
  )
  ok(written->String.includes(`@as("type") type_: string`))
  ok(written->String.includes(`v.type_`))
})

test("what cannot be written is unread, where it stands", () => {
  let unread = (at, expected): result<string, Generate.unread> => Error({at, expected})
  deepEqual(written("{"), unread("", "JSON"))
  deepEqual(written(`{"types": {}}`), unread("shell", "present"))
  deepEqual(
    written(contracts(~types=`"a": {"record": [{"name": "b", "key": 1, "shape": {"type": "c"}}]}`)),
    unread("types/a/record/0/shape", "a type declared"),
  )
  deepEqual(
    written(contracts(~types=`"a-b": {"record": []}, "a_b": {"record": []}`)),
    unread("types/a_b", "a name whose module no other has"),
  )
  deepEqual(
    written(
      contracts(
        ~types=`"u": {"union": {"tag": "name", "cases": [{"name": "c", "code": 1, "fields": [{"name": "f", "key": 0, "shape": {"prim": "bool"}}]}]}}`,
      ),
    ),
    unread("types/u/union/cases/0/fields/0/key", "a key no other field has"),
  )
  deepEqual(
    written(contracts(~reasons=`[{"name": "gone", "failure": "lost"}]`)),
    unread("reasons/0/failure", "one of rejected"),
  )
  deepEqual(
    written(
      contracts(
        ~interfaces=`{"thing": {"version": 1, "operations": [{"name": "get", "input": "nothing", "output": "failure", "reasons": []}]}}`,
      ),
    ),
    unread("interfaces/thing/operations/0/input", "a type declared"),
  )
})
