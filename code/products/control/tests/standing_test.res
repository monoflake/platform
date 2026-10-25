/***
 * A control standing on another held to RFC rxmd9, its objects, its reaches and its relayed hosts
 * reached through that control, and its state over objects kept as the one in memory is.
 */
open Node
module Contracts = Envelope.Contracts

type sent = {
  url: string,
  authorization: option<string>,
  proxy: option<string>,
  edges: array<string>,
  body: JSON.t,
}

let json = (status, value) =>
  Web.answered(~status, ~contentType="application/json", JSON.stringify(value))
let success = data => json(200, JSON.Object(dict{"status": String("success"), "data": data}))

/** The control stood on faked, its objects a dict, every call it was sent kept. */
let stoodOn = () => {
  let objects: dict<Uint8Array.t> = dict{}
  let sent = []
  let fetch = async request => {
    let headers = request->Web.requestHeaders
    let header = name => headers->Web.header(name)->Nullable.toOption
    let body = try JSON.parseOrThrow(Web.fromUtf8(await request->Web.bytesOf)) catch {
    | _ => JSON.Null
    }
    sent->Array.push({
      url: request->Web.url,
      authorization: header("authorization"),
      proxy: header("proxy-authorization"),
      edges: headers
      ->Web.headerNames
      ->Iterator.toArray
      ->Array.filter(n => n->String.startsWith("cf-") || n == "cdn-loop" || n == "true-client-ip"),
      body,
    })
    let input = body->JSON.Decode.object->Option.flatMap(o => o->Dict.get("input"))
    let named = input->Option.flatMap(i => i->JSON.Decode.object)
    let text = key =>
      named->Option.flatMap(o => o->Dict.get(key))->Option.flatMap(JSON.Decode.string)
    switch Web.parts(request->Web.url)->Web.pathname {
    | "/object/write" =>
      switch Contracts.ObjectWrite.fromJson(input->Option.getOr(JSON.Null)) {
      | Ok({name, content}) =>
        objects->Dict.set(name, content)
        success(Contracts.ObjectWritten.toJson({}))
      | Error(_) => json(400, JSON.Null)
      }
    | "/object/read" =>
      switch text("name")->Option.flatMap(name => objects->Dict.get(name)) {
      | Some(content) =>
        success(
          Contracts.ObjectContent.toJson({
            content,
            size: content->TypedArray.length->Int.toFloat,
          }),
        )
      | None =>
        json(
          404,
          JSON.parseOrThrow(`{"status": "error", "failure": "rejected", "reason": "not_found", "message": "none"}`),
        )
      }
    | "/object/delete" =>
      switch text("name") {
      | Some(name) if objects->Dict.get(name) != None =>
        objects->Dict.delete(name)
        success(Contracts.ObjectDeleted.toJson({}))
      | Some(_) | None =>
        json(
          404,
          JSON.parseOrThrow(`{"status": "error", "failure": "rejected", "reason": "not_found", "message": "none"}`),
        )
      }
    | "/object/list" =>
      let prefix = text("prefix")->Option.getOr("")
      let after = text("after")
      let names =
        objects
        ->Dict.keysToArray
        ->Array.toSorted(String.compare)
        ->Array.filter(n => n->String.startsWith(prefix) && after->Option.mapOr(true, a => n > a))
      // Two at a time, so a list is read across its pages.
      let page = names->Array.slice(~start=0, ~end=2)
      success(
        Contracts.ObjectListed.toJson({
          objects: page->Array.map((name): Contracts.ObjectListedOne.t => {name, size: 0.}),
          next: ?(names->Array.length > 2 ? page->Array.at(-1) : None),
        }),
      )
    | "/reaches/open" =>
      success(
        Contracts.ReachOpened.toJson({
          reach: 7.,
          address: "10.200.0.7",
          tunnel: Web.utf8("token of binding-7"),
        }),
      )
    | path => Web.answered(~status=200, `relayed ${path}`)
    }
  }
  (fetch, objects, sent)
}

let origin = "https://foundation.test"
let token = "o1.token"

test(
  "an object is written, read, missed and listed across pages by the organization's token",
  async () => {
    let (fetch, _, sent) = stoodOn()
    let objects = Objects.through(~origin, ~token, fetch)
    deepEqual(await objects.write("state/a", Web.utf8("one")), Ok())
    ignore(await objects.write("state/b", Web.utf8("two")))
    ignore(await objects.write("state/c", Web.utf8("three")))
    ignore(await objects.write("other/d", Web.utf8("four")))
    deepEqual(
      (await objects.read("state/b"))->Result.map(o => o->Option.map(Web.fromUtf8)),
      Ok(Some("two")),
    )
    deepEqual(await objects.read("state/none"), Ok(None))
    deepEqual(await objects.list("state/"), Ok(["state/a", "state/b", "state/c"]))
    // An object removed is read as none, and one removed twice is no fault.
    deepEqual(await objects.delete("state/c"), Ok())
    deepEqual(await objects.delete("state/c"), Ok())
    deepEqual(await objects.read("state/c"), Ok(None))
    deepEqual(
      sent->Array.slice(~start=0, ~end=1)->Array.map(s => (s.url, s.authorization)),
      [("https://foundation.test/object/write", Some("Bearer o1.token"))],
    )
  },
)

test("a reach is opened of the control stood on, its tunnel's token as text", async () => {
  let (fetch, _, sent) = stoodOn()
  let standing = Standing.through(~origin, ~token, fetch)
  deepEqual(await standing.reach(), Ok({address: "10.200.0.7", tunnel: Some("token of binding-7")}))
  deepEqual(sent->Array.map(s => s.url), ["https://foundation.test/reaches/open"])
})

test(
  "a relayed host is reached at the relay's path, the organization's token its proxy's",
  async () => {
    let (fetch, _, sent) = stoodOn()
    let reach = Reach.relayed(~origin, ~token, fetch)
    let at = reach.origin(~address="10.200.0.7", ~port=37483)
    deepEqual(at, "https://foundation.test/relay/10.200.0.7/37483")
    let answer = await reach.fetch(
      Web.request(
        `${at}/deployments/describe`,
        {
          method: "POST",
          headers: dict{"authorization": "Bearer 1.host"},
        },
      ),
    )
    deepEqual(await answer->Web.text, "relayed /relay/10.200.0.7/37483/deployments/describe")
    deepEqual(
      sent->Array.map(s => (s.authorization, s.proxy)),
      [(Some("Bearer 1.host"), Some("Bearer o1.token"))],
    )
  },
)

test("a relayed request carries none of the headers Cloudflare's edge set", async () => {
  let (fetch, _, sent) = stoodOn()
  let reach = Reach.relayed(~origin, ~token, fetch)
  let at = reach.origin(~address="10.200.0.7", ~port=36879)
  let _ = await reach.fetch(
    Web.request(
      `${at}/`,
      {
        method: "GET",
        headers: dict{
          "cf-connecting-ip": "192.0.2.1",
          "cf-ray": "0-LAX",
          "cf-ipcountry": "US",
          "cdn-loop": "cloudflare",
          "true-client-ip": "192.0.2.1",
          "x-forwarded-host": "00000001.b1",
        },
      },
    ),
  )
  // Sent back through Cloudflare, CF-Connecting-IP among them got its edge's 403, rxmd9's step 5.
  deepEqual(sent->Array.map(s => s.edges), [[]])
})

/** What a state keeps, asked alike of each kind of state. */
let kept = async (state: State.t) => {
  let secret = Uint8Array.fromLength(32)
  let other = Web.random(32)
  let first = await state.openOrganization("first", ~secret)
  let again = await state.openOrganization("first", ~secret=other)
  let second = await state.openOrganization("second", ~secret=other)
  let storage = await state.openBinding(
    ~organization=first.id,
    ~secret,
    ~relayed=false,
    ~random=Memory.counting(),
  )
  let relayed = await state.openBinding(
    ~organization=first.id,
    ~secret,
    ~relayed=true,
    ~random=Memory.counting(),
  )
  ignore(await state.addressed(~binding=relayed, ~address="10.200.0.2"))
  await state.routed(~binding=relayed)
  let unbound = await state.storage(first.id)
  ignore(await state.addressed(~binding=storage, ~address="10.200.0.1"))
  await state.routed(~binding=storage)
  await state.tunneled(~binding=storage, ~tunnel="tunnel-1")
  await state.putRelease({hash: "aa", form: Modules, size: 3.})
  await state.putRelease({hash: "aa", form: Image, size: 9.})
  await state.deploy({app: 4., binding: storage, release: "aa", capacity: 1.})
  let drawn = await state.drawApp(~random=() => 16777224.)
  await state.deploy({app: drawn, binding: storage, release: "aa", capacity: 0.})
  let forgotten = (
    await state.forgetApp(4.),
    await state.forgetApp(drawn),
    await state.forgetApp(drawn),
    await state.deployment(drawn),
    await state.drawApp(~random=() => 16777224.),
  )
  (
    forgotten,
    (first.id, again.id, again.secret == secret, second.id),
    (await state.hasOrganization(2.), await state.hasOrganization(3.)),
    (await state.organizationSecret(2.))->Option.map(s => s == other),
    (unbound, (await state.storage(first.id))->Option.map(b => (b.id, b.tunnel))),
    (await state.addressedAt("10.200.0.2"))->Option.map(b => (b.id, b.relayed)),
    await state.release("aa"),
    await state.deployment(4.),
    await state.deployment(5.),
  )
}

test("a state over objects keeps what the state in memory keeps", async () => {
  let (fetch, objects, _) = stoodOn()
  let sealing = Sealing.ofKey(Some(Envelope.Base64url.encode(Web.random(32))))
  let overObjects = await kept(State.ofObjects(Objects.through(~origin, ~token, fetch), ~sealing))
  deepEqual(overObjects, await kept(Memory.state()))
  // An app that ran is kept, one drawn and never run forgotten once, and its id drawn again.
  let (forgotten, _, _, _, _, _, _, _, _) = overObjects
  deepEqual(forgotten, (false, true, false, None, 16777224.))
  ok(
    objects->Dict.keysToArray->Array.every(n => n->String.startsWith("state/")),
    ~message="every record is under state/",
  )
})

test("an artifact kept as an object is served whole, and one not kept is none", async () => {
  let (fetch, _, _) = stoodOn()
  let artifacts = Artifacts.ofObjects(Objects.through(~origin, ~token, fetch))
  await artifacts.put("ab", Web.utf8("a bundle"))
  switch await artifacts.served("ab") {
  | Some(served) => deepEqual(await served->Web.text, "a bundle")
  | None => ok(false, ~message="the artifact was not served")
  }
  deepEqual((await artifacts.served("cd"))->Option.isSome, false)
})

test("a forget over a control that does not delete, or keeps what it deleted, fails", async () => {
  let refusing = `{"status": "error", "failure": "rejected", "reason": "malformed", "message": "the interface object has no operation delete"}`
  let answering = [
    // A control stood on relays the delete to its driver, and a refusal there is no removal.
    _ => json(400, JSON.parseOrThrow(refusing)),
    // One that answers done and keeps the object is no removal either.
    _ => success(Contracts.ObjectDeleted.toJson({})),
  ]
  for i in 0 to answering->Array.length - 1 {
    let (fetch, _, _) = stoodOn()
    let answer = answering->Array.getUnsafe(i)
    let old = async request =>
      Web.parts(request->Web.url)->Web.pathname == "/object/delete"
        ? answer(request)
        : await fetch(request)
    let sealing = Sealing.ofKey(Some(Envelope.Base64url.encode(Web.random(32))))
    let state = State.ofObjects(Objects.through(~origin, ~token, old), ~sealing)
    let app = await state.drawApp(~random=() => 16777224.)
    let failed = switch await state.forgetApp(app) {
    | _ => false
    | exception JsExn(_) => true
    }
    let again = switch await state.drawApp(~random=() => 16777224.) {
    | _ => false
    | exception JsExn(_) => true
    }
    deepEqual((failed, again), (true, true), ~message=Int.toString(i))
  }
})

test("a retire over a control that does not delete, or keeps what it deleted, fails", async () => {
  let refusing = `{"status": "error", "failure": "rejected", "reason": "malformed", "message": "the interface object has no operation delete"}`
  let answering = [
    _ => json(400, JSON.parseOrThrow(refusing)),
    _ => success(Contracts.ObjectDeleted.toJson({})),
  ]
  for i in 0 to answering->Array.length - 1 {
    let (fetch, _, _) = stoodOn()
    let answer = answering->Array.getUnsafe(i)
    let old = async request =>
      Web.parts(request->Web.url)->Web.pathname == "/object/delete"
        ? answer(request)
        : await fetch(request)
    let sealing = Sealing.ofKey(Some(Envelope.Base64url.encode(Web.random(32))))
    let state = State.ofObjects(Objects.through(~origin, ~token, old), ~sealing)
    let app = await state.drawApp(~random=() => 16777224.)
    await state.deploy({app, binding: 2., release: "aa", capacity: 1.})
    let failed = switch await state.retireApp(app) {
    | () => false
    | exception JsExn(_) => true
    }
    deepEqual(
      (failed, (await state.deployment(app))->Option.isSome),
      (true, true),
      ~message=Int.toString(i),
    )
  }
})
