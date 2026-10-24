/***
 * A control standing on another held to RFC rxmd9, its objects, its reaches and its relayed hosts
 * reached through that control, and its state over objects kept as the one in memory is.
 */
open Node
module Contracts = Envelope.Contracts

type sent = {url: string, authorization: option<string>, proxy: option<string>, body: JSON.t}

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

/** What a state keeps, asked alike of each kind of state. */
let kept = async (state: State.t) => {
  let secret = Uint8Array.fromLength(32)
  let other = Web.random(32)
  let first = await state.openOrganization("first", ~secret)
  let again = await state.openOrganization("first", ~secret=other)
  let second = await state.openOrganization("second", ~secret=other)
  let storage = await state.openBinding(~organization=first.id, ~secret, ~relayed=false)
  let relayed = await state.openBinding(~organization=first.id, ~secret, ~relayed=true)
  await state.addressed(~binding=relayed, ~address="10.200.0.2")
  let unbound = await state.storage(first.id)
  await state.addressed(~binding=storage, ~address="10.200.0.1")
  await state.tunneled(~binding=storage, ~tunnel="tunnel-1")
  await state.putRelease({hash: "aa", form: Modules, size: 3.})
  await state.putRelease({hash: "aa", form: Image, size: 9.})
  await state.deploy({app: 4., binding: storage, release: "aa", capacity: 1.})
  (
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
  let overObjects = await kept(State.ofObjects(Objects.through(~origin, ~token, fetch)))
  deepEqual(overObjects, await kept(Memory.state()))
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
