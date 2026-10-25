/***
 * A behavior file read, RFC p8e8k, each refusal leading with where it stands.
 */
type expect =
  | Output(JSON.t)
  | Answer(JSON.t)
  | Failure({failure: string, reason: string})

type send = {to: JSON.t, export: string, key: option<string>, body: option<JSON.t>}

type step =
  | Call({
      operation: string,
      input: JSON.t,
      expect: expect,
      within: option<int>,
      as_: option<string>,
      bearer: option<string>,
      fixture: option<string>,
    })
  | Send({send: send, expect: expect, within: option<int>})
  | Lose(int)
  | Wait(int)

type case = {
  description: string,
  given: option<JSON.t>,
  copies: option<int>,
  network: bool,
  tunnel: bool,
  steps: array<step>,
}

type file = {interface: string, cases: array<case>}

exception Unread(string)

let fail = why => throw(Unread(why))

/** A reading within a step of the path, which leads where it was refused. */
let within = (at, read) =>
  try read() catch {
  | Unread(why) => fail(`${at}/${why}`)
  }

let member = (o, name) => o->Dict.get(name)

let object = (json, what) =>
  switch json->JSON.Decode.object {
  | Some(o) => o
  | None => fail(`${what}: not an object`)
  }

let string = (o, name) =>
  switch member(o, name)->Option.map(JSON.Decode.string) {
  | Some(Some(text)) => text
  | Some(None) => fail(`${name}: not a string`)
  | None => fail(`${name}: absent`)
  }

let optionalString = (o, name) =>
  switch member(o, name)->Option.map(JSON.Decode.string) {
  | Some(Some(text)) => Some(text)
  | Some(None) => fail(`${name}: not a string`)
  | None => None
  }

let optionalInt = (o, name) =>
  switch member(o, name)->Option.map(JSON.Decode.float) {
  | Some(Some(n)) if Math.floor(n) == n && n >= 0. => Some(Float.toInt(n))
  | Some(Some(_) | None) => fail(`${name}: not a whole number`)
  | None => None
  }

let int = (o, name) =>
  switch optionalInt(o, name) {
  | Some(n) => n
  | None => fail(`${name}: absent`)
  }

let optionalBool = (o, name) =>
  switch member(o, name)->Option.map(JSON.Decode.bool) {
  | Some(Some(truth)) => truth
  | Some(None) => fail(`${name}: not a boolean`)
  | None => false
  }

/** A step's bearer, `{"$use": name}` and nothing more, by the name of what a step captured. */
let bearerOf = o =>
  switch member(o, "bearer") {
  | None => None
  | Some(bearer) =>
    switch bearer->JSON.Decode.object->Option.map(Dict.toArray) {
    | Some([("$use", name)]) =>
      switch name->JSON.Decode.string {
      | Some(name) => Some(name)
      | None => fail("bearer: a $use names a capture")
      }
    | Some(_) | None => fail(`bearer: not {"$use": name}`)
    }
  }

let list = (o, name) =>
  switch member(o, name)->Option.map(JSON.Decode.array) {
  | Some(Some(items)) => items
  | Some(None) => fail(`${name}: not an array`)
  | None => fail(`${name}: absent`)
  }

let expectOf = o => {
  let e = object(member(o, "expect")->Option.getOr(JSON.Null), "expect")
  switch (member(e, "failure"), member(e, "output"), member(e, "answer")) {
  | (Some(_), _, _) =>
    within("expect", () => Failure({failure: string(e, "failure"), reason: string(e, "reason")}))
  | (None, Some(output), _) => Output(output)
  | (None, None, Some(answer)) => Answer(answer)
  | (None, None, None) => fail("expect: neither an output, an answer nor a failure")
  }
}

let stepOf = json => {
  let o = object(json, "step")
  switch (member(o, "call"), member(o, "send"), member(o, "lose"), member(o, "wait")) {
  | (Some(_), _, _, _) =>
    Call({
      operation: string(o, "call"),
      input: member(o, "input")->Option.getOr(JSON.Null),
      expect: expectOf(o),
      within: optionalInt(o, "within"),
      as_: optionalString(o, "as"),
      bearer: bearerOf(o),
      fixture: optionalString(o, "fixture"),
    })
  | (None, Some(send), _, _) =>
    let d = within("send", () => object(send, "send"))
    Send({
      send: within("send", () => {
        to: switch member(d, "to") {
        | Some(to) => to
        | None => fail("to: absent")
        },
        export: string(d, "export"),
        key: optionalString(d, "key"),
        body: member(d, "body"),
      }),
      expect: expectOf(o),
      within: optionalInt(o, "within"),
    })
  | (None, None, Some(_), _) => Lose(int(o, "lose"))
  | (None, None, None, Some(_)) => Wait(int(o, "wait"))
  | (None, None, None, None) => fail("neither a call, a send, a lose nor a wait")
  }
}

let caseOf = json => {
  let o = object(json, "case")
  {
    description: string(o, "description"),
    given: member(o, "given"),
    copies: optionalInt(o, "copies"),
    network: optionalBool(o, "network"),
    tunnel: optionalBool(o, "tunnel"),
    steps: list(o, "steps")->Array.mapWithIndex((step, k) =>
      within(`steps/${Int.toString(k)}`, () => stepOf(step))
    ),
  }
}

let read = text =>
  switch JSON.parseOrThrow(text) {
  | exception JsExn(e) => Error(`no JSON: ${e->JsExn.message->Option.getOr("unread")}`)
  | json =>
    try {
      let o = object(json, "a behavior file")
      switch (member(o, "interface"), member(o, "checker")) {
      | (None, Some(_)) => Error("a property, which only a history shows: no behavior file")
      | (Some(_), _) | (None, None) =>
        Ok({
          interface: string(o, "interface"),
          cases: list(o, "cases")->Array.mapWithIndex((case, n) =>
            within(`cases/${Int.toString(n)}`, () => caseOf(case))
          ),
        })
      }
    } catch {
    | Unread(why) => Error(why)
    }
  }
