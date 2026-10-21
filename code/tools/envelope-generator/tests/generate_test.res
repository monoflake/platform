/***
 * `Generate` held to `model/contracts.json` and to contracts of its own: what it writes, the same
 * twice over, types that name one another, a keyword's field, and where what it cannot write is.
 */
open Node

let written = text => Generate.read(text)->Result.flatMap(Generate.rescript)

/** A call's fields as `model/contracts.json` writes them, the capabilities' shape `capabilities`. */
let callFields = (~capabilities=`{"list": {"prim": "bytes"}}`) =>
  `[{"name": "interface", "key": 1, "shape": {"prim": "string"}},
    {"name": "operation", "key": 2, "shape": {"prim": "string"}},
    {"name": "input", "key": 3, "shape": {"input": "operation"}},
    {"name": "capabilities", "key": 4, "shape": ${capabilities}, "optional": true}]`

/** The answer as `model/contracts.json` writes it, the success's code `success`. */
let answer = (~success=1) =>
  `{"tag": "status", "cases": [
    {"name": "success", "code": ${Int.toString(
      success,
    )}, "fields": [{"name": "data", "key": 1, "shape": {"output": "operation"}}]},
    {"name": "error", "code": 2, "type": "error"}]}`

/** An `error` as `model/contracts.json` writes it, its message's field `message`. */
let error = (~message=`{"name": "message", "key": 3, "shape": {"prim": "string"}}`) =>
  `"error": {"record": [{"name": "failure", "key": 1, "shape": {"type": "failure"}},
    {"name": "reason", "key": 2, "shape": {"prim": "string"}}, ${message}]}`

/** Contracts holding `types` beside a `failure` of one choice and an `error`. */
let contracts = (
  ~types="",
  ~reasons="[]",
  ~messages=`{"gone": "Gone"}`,
  ~interfaces="{}",
  ~call=callFields(),
  ~answer=answer(),
  ~error=error(),
) => {
  let failure = `"failure": {"enum": [{"name": "rejected", "code": 1}], "ordered": false}, ${error}`
  let types = types == "" ? failure : `${failure}, ${types}`
  `{"shell": [], "call": {"fields": ${call}, "typ": "monoflake:call:1"}, "types": {${types}},
    "answer": ${answer}, "reasons": ${reasons}, "messages": ${messages}, "calling": [],
    "interfaces": ${interfaces}}`
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
    "type reason = {name: string, failure: Failure.t, message: string}",
    `{name: "denied", failure: Failure.Rejected, message: "The call carries no credential, or one that does not allow it"}`,
    "let messages: dict<string> = ",
    `("not_found", "Nothing of that name or id exists")`,
    "module Answer = {",
    "type t<'output> = Success('output) | Error(Error.t)",
    "let jsonToCbor = ",
    "let cborToJson = ",
    "let callJsonToCbor = ",
    "let callCborToJson = ",
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

test("an interface holds a call of each operation and the envelope it travels in", () => {
  let written = source(
    contracts(
      ~types=`"thing-got": {"record": []}`,
      ~interfaces=`{"thing": {"version": 1, "operations": [
        {"name": "get_one", "input": "failure", "output": "thing-got", "reasons": []}]}}`,
    ),
  )
  ok(written->String.includes("type call = | GetOne(Failure.t)"))
  ok(written->String.includes("type envelope = {call: call, capabilities: array<Uint8Array.t>}"))
  ok(written->String.includes(`Wire.FromJson.exactly("thing")`))
  ok(written->String.includes(`| "thing" => Some(Wire.jsonToCbor(json, Interface.Thing.fromJson`))
})

test("an answer is a union by its tag, its error the fields of error", () => {
  let written = source(contracts())
  ok(
    written->String.includes(`Wire.ToJson.case("status", "success", [Wire.ToJson.field("data", d, data)])`),
  )
  ok(
    written->String.includes(`Wire.ToCbor.case(2, [Wire.ToCbor.field(1, c.failure, Failure.toCbor)`),
  )
  ok(written->String.includes(`Wire.FromCbor.unknown("status", [1, 2])`))
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
    written(contracts(~reasons=`[{"name": "lost", "failure": "rejected"}]`)),
    unread("reasons/0/name", "a reason messages gives a message"),
  )
  deepEqual(written(contracts(~messages=`{"gone": 1}`)), unread("messages/gone", "a string"))
  deepEqual(
    written(contracts(~answer=answer(~success=2))),
    unread("answer/cases/1/code", "a code other than success's"),
  )
  deepEqual(
    written(contracts(~answer=`{"tag": "status", "cases": []}`)),
    unread("answer/cases", "two cases, success and error"),
  )
  deepEqual(
    written(
      contracts(~error=error(~message=`{"name": "status", "key": 3, "shape": {"prim": "string"}}`)),
    ),
    unread("types/error/record/2/name", "a name no other field has"),
  )
  deepEqual(
    written(
      contracts(
        ~error=error(~message=`{"name": "message", "key": 0, "shape": {"prim": "string"}}`),
      ),
    ),
    unread("types/error/record/2/key", "a key no other field has"),
  )
  deepEqual(
    written(
      contracts(
        ~interfaces=`{"thing": {"version": 1, "operations": [{"name": "get", "input": "nothing", "output": "failure", "reasons": []}]}}`,
      ),
    ),
    unread("interfaces/thing/operations/0/input", "a type declared"),
  )
  deepEqual(
    written(contracts(~call=callFields(~capabilities=`{"prim": "bool"}`))),
    unread(
      "call/fields/3",
      "the interface's name or the operation's, a string; its input; or the capabilities, an optional list of bytes",
    ),
  )
  deepEqual(
    written(
      contracts(
        ~types=`"thing": {"record": []}`,
        ~interfaces=`{"thing": {"version": 1, "operations": [{"name": "get", "input": "thing", "output": "thing", "reasons": []}]}}`,
      ),
    ),
    unread("interfaces/thing", "a name whose module hides no type's this module names"),
  )
  deepEqual(
    written(
      contracts(
        ~interfaces=`{"thing": {"version": 1, "operations": [{"name": "to_json", "input": "failure", "output": "failure", "reasons": []}]}}`,
      ),
    ),
    unread(
      "interfaces/thing/operations/0/name",
      "a name no other operation has, nor version, toJson, fromJson, toCbor or fromCbor",
    ),
  )
})
