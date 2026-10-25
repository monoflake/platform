/***
 * A binding bound by its origin, RFC 8j7b0, its call back proven, its origin kept, its token spent
 * by its first bind, and every call sent there.
 */
open Node
open Called

/** A request an origin was sent, its URL, its bearer and how it follows a redirect. */
type called = {url: string, authorization: option<string>, redirect: string}

/** How a faked origin answers, `Edge` as Cloudflare's edge does for an origin it cannot reach. */
type answering = Driver | Page | Refusing | Moved | Edge(int) | Silent | Gated(promise<unit>)

let described = () =>
  Host.success(
    Contracts.ManagementDescribed.toJson({generation: 0., policy: 0., grace: 0., items: []}),
  )

/** An origin faked behind the direct fetch, answering as `answering` says and keeping each call. */
let origin = (answering: ref<answering>) => {
  let seen = []
  let direct: Web.fetch = async request => {
    let header = name => request->Web.requestHeaders->Web.header(name)->Nullable.toOption
    seen->Array.push({
      url: request->Web.url,
      authorization: header("authorization"),
      redirect: request->redirectOf,
    })
    switch answering.contents {
    | Driver => described()
    | Gated(gate) =>
      await gate
      described()
    | Page => Web.answered(~status=200, ~contentType="text/html", "<html>Example Domain</html>")
    | Refusing =>
      Host.json(
        403,
        JSON.parseOrThrow(`{"status": "error", "failure": "rejected", "reason": "denied", "message": "no"}`),
      )
    | Moved =>
      Web.response(
        Uint8Array.fromLength(0),
        {status: 302, headers: dict{"location": "http://10.0.0.1/"}},
      )
    | Edge(status) => Web.answered(~status, ~contentType="text/html", "<html>error code</html>")
    | Silent => JsError.throwWithMessage("getaddrinfo ENOTFOUND driver.invalid")
    }
  }
  (direct, seen)
}

/** A stand with an open binding whose origin answers as given, and the binding's id. */
let originStand = async (~tunnels=?, answering) => {
  let (direct, seen) = origin(answering)
  let stood = stand(~tunnels?, ~direct)
  ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
  let id = await openBinding(stood, 1.)
  (stood, seen, id)
}

let byOrigin = origin => bindings(Bind({reach: Origin({origin: origin})}))

let originOf = async (stood, id) =>
  (await stood.parts.state.binding(id))->Option.flatMap(b => b.origin)

let message = json => json->member("message")->JSON.Decode.string->Option.getOr("")

test(
  "an origin the parser refuses, or not https on a DNS name and its default port, is malformed",
  async () => {
    let (stood, seen, id) = await originStand(ref(Driver))
    let refused = [
      "http://driver.example.com",
      "https://192.0.2.10",
      "https://0xc0000210",
      "https://3221226000",
      "https://0300.0.2.10",
      "https://[2001:db8::10]",
      "https://2001:db8::10",
      "https://driver.example.com:8443",
      "https://driver.example.com/management",
      "https://driver.example.com?binding=1",
      "https://admin@driver.example.com",
      "https://driver.example.com#describe",
      "https://localhost",
      "https://driver.localhost",
      "https://printer.local",
      "https://driver.internal",
      "https://router.home.arpa",
      "https://example",
      "https://-driver.example.com",
      "https://driver.example.com.",
      "https://xn--a.example.com",
      "https://xn--ab.example.com",
      "https://xn--99999999999.example.com",
      "https://driver\u0000.example.com",
      "driver.example.com",
    ]
    for i in 0 to refused->Array.length - 1 {
      let given = refused->Array.getUnsafe(i)
      let (status, answer) = await called(stood, Host(id), byOrigin(given))
      deepEqual((status, answer->reason), (400, Some("malformed")), ~message=given)
    }
    deepEqual(seen, [])
    deepEqual(await originOf(stood, id), None)
  },
)

test(
  "an origin is judged as the parser leaves it, punycode and the default port among it",
  async () => {
    let given = [
      ("HTTPS://Driver.Example.com/", "https://driver.example.com"),
      ("https://driver.example.com:443", "https://driver.example.com"),
      ("https://bücher.example.com", "https://xn--bcher-kva.example.com"),
      ("https://xn--bcher-kva.example.com", "https://xn--bcher-kva.example.com"),
    ]
    for i in 0 to given->Array.length - 1 {
      let (text, kept) = given->Array.getUnsafe(i)
      let (stood, seen, id) = await originStand(ref(Driver))
      let (_, bound) = await called(stood, Host(id), byOrigin(text))
      deepEqual(
        (bound->data->member("reached")->member("origin"), seen->Array.map(s => s.url)),
        (JSON.String(kept), [`${kept}/management/describe`]),
        ~message=text,
      )
    }
  },
)

test("an origin proven by its call back is kept and answered", async () => {
  let (stood, seen, id) = await originStand(ref(Driver))
  let (status, bound) = await called(stood, Host(id), byOrigin("https://driver.example.com"))
  deepEqual(
    (status, bound->data),
    (
      200,
      JSON.parseOrThrow(
        `{"binding": ${Float.toString(
            id,
          )}, "reached": {"name": "origin", "origin": "https://driver.example.com"}}`,
      ),
    ),
  )
  let token =
    (await stood.parts.state.binding(id))->Option.map(b =>
      `Bearer ${Access.tokenText(b.id, b.secret)}`
    )
  deepEqual(
    seen,
    [
      {
        url: "https://driver.example.com/management/describe",
        authorization: token,
        redirect: "manual",
      },
    ],
  )
  deepEqual(await originOf(stood, id), Some("https://driver.example.com"))
})

test(
  "an origin that answered and is no driver of the binding is not proven, and not kept",
  async () => {
    let answering = ref(Page)
    let (stood, _, id) = await originStand(answering)
    let answers = []
    [Page, Refusing, Moved, Edge(500), Edge(404)]->Array.forEach(a => answers->Array.push(a))
    let reasons = []
    for i in 0 to answers->Array.length - 1 {
      answering := answers->Array.getUnsafe(i)
      let (status, answer) = await called(stood, Host(id), byOrigin("https://example.com"))
      reasons->Array.push((status, answer->reason, answer->message))
    }
    deepEqual(
      reasons,
      Array.make(
        ~length=5,
        (
          400,
          Some("not_proven"),
          `https://example.com answered, and not as binding ${Ids.text(id)}'s driver`,
        ),
      ),
    )
    deepEqual(await originOf(stood, id), None)
  },
)

test(
  "an origin not answering, or Cloudflare's edge saying so, is unreachable in one message",
  async () => {
    let answering = ref(Silent)
    let (stood, _, id) = await originStand(answering)
    let answers = [Silent, Edge(521), Edge(522), Edge(523), Edge(524), Edge(530)]
    let reasons = []
    for i in 0 to answers->Array.length - 1 {
      answering := answers->Array.getUnsafe(i)
      let (status, answer) = await called(stood, Host(id), byOrigin("https://driver.invalid"))
      reasons->Array.push((status, answer->reason, answer->message))
    }
    deepEqual(
      reasons,
      Array.make(
        ~length=6,
        (
          503,
          Some("unreachable"),
          `https://driver.invalid did not answer binding ${Ids.text(id)}'s call back`,
        ),
      ),
    )
    deepEqual(await originOf(stood, id), None)
  },
)

test("an origin binding's token is spent by its first bind, any bind after it denied", async () => {
  let (stood, seen, id) = await originStand(ref(Driver))
  ignore(await called(stood, Host(id), byOrigin("https://driver.example.com")))
  let again = [
    await called(stood, Host(id), byOrigin("https://driver.example.com")),
    await called(stood, Host(id), byOrigin("https://other.example.com")),
    await called(stood, Host(id), bindings(Bind({reach: Tunnel}))),
  ]
  deepEqual(
    again->Array.map(((status, answer)) => (status, answer->reason)),
    Array.make(~length=3, (403, Some("denied"))),
  )
  deepEqual(
    (seen->Array.length, await originOf(stood, id)),
    (1, Some("https://driver.example.com")),
  )
})

test("two binds by origin at once fix one origin, and the other is denied", async () => {
  let release = ref(() => ())
  let gate = Promise.make((resolve, _) => release := (() => resolve()))
  let (stood, seen, id) = await originStand(ref(Gated(gate)))
  let first = called(stood, Host(id), byOrigin("https://driver.example.com"))
  let second = called(stood, Host(id), byOrigin("https://other.example.com"))
  release.contents()
  let answers = await Promise.all([first, second])
  deepEqual(
    (answers->Array.map(((_, a)) => a->reason), seen->Array.length),
    ([None, Some("denied")], 2),
  )
  deepEqual(await originOf(stood, id), Some("https://driver.example.com"))
})

test(
  "a binding bound by its tunnel is refused an origin as invalid, never called back",
  async () => {
    let (stood, seen, id) = await originStand(ref(Driver))
    ignore(await called(stood, Host(id), bindings(Bind({reach: Tunnel}))))
    let (status, refused) = await called(stood, Host(id), byOrigin("https://driver.example.com"))
    let (_, again) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
    deepEqual(
      (
        (status, refused->member("failure"), refused->reason),
        seen,
        await originOf(stood, id),
        again->data->member("reached")->member("name"),
      ),
      ((400, JSON.String("rejected"), Some("invalid")), [], None, JSON.String("tunnel")),
    )
  },
)

test("a binding bound by its origin is called there for every call", async () => {
  let (stood, seen, id) = await originStand(ref(Driver))
  ignore(await called(stood, Host(id), byOrigin("https://driver.example.com")))
  ignore(await called(stood, Operator, releases(Put({form: Modules, artifact}))))
  let release = await Web.sha256(artifact)
  ignore(await called(stood, Operator, releases(Deploy({binding: id, release}))))
  // The bind's call back, then the deploy's own, which the faked origin answers only in part.
  deepEqual(
    seen->Array.slice(~start=0, ~end=3)->Array.map(s => s.url),
    [
      "https://driver.example.com/management/describe",
      "https://driver.example.com/management/describe",
      "https://driver.example.com/management/apply",
    ],
  )
  let token =
    (await stood.parts.state.binding(id))->Option.map(b =>
      `Bearer ${Access.tokenText(b.id, b.secret)}`
    )
  ok(seen->Array.every(s => s.authorization == token), ~message="every call carries the token")
  deepEqual(stood.host.seen, [])
})

test(
  "a direct reach is its origin whatever address and port, its redirects not followed",
  async () => {
    let sent = ref(None)
    let reach = Reach.direct("https://driver.example.com", async request => {
      sent := Some(request->redirectOf)
      Web.answered(~status=200, "")
    })
    deepEqual(reach.origin(~address="10.200.0.1", ~port=37483), "https://driver.example.com")
    ignore(
      await reach.fetch(
        Web.request("https://driver.example.com/x", {method: "GET", headers: dict{}}),
      ),
    )
    deepEqual(sent.contents, Some("manual"))
  },
)

test(
  "a route not made keeps its address unbound, the next binding taking the next and binding",
  async () => {
    let (faked, made, routes) = tunnels(~unrouted=1)
    let (stood, _, id) = await originStand(~tunnels=faked, ref(Driver))
    let (status, refused) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
    let kept = (await stood.parts.state.binding(id))->Option.map(b => (b.address, b.bound))
    let next = await openBinding(stood, 1.)
    let (nextStatus, nextBound) = await called(stood, Host(next), bindings(Bind({reach: Tunnel})))
    // Unbound, it is no host to deploy onto, and may still be bound by its origin.
    let release = Uint8Array.fromLength(32)
    let (_, unbound) = await called(stood, Operator, releases(Deploy({binding: id, release})))
    let (bound, answer) = await called(stood, Host(id), byOrigin("https://driver.example.com"))
    deepEqual(
      (
        (status, refused->reason, kept),
        (nextStatus, nextBound->data->member("reached")->member("address")),
        (made.contents, routes),
        unbound->reason,
        (bound, answer->data->member("reached")->member("name")),
      ),
      (
        (503, Some("unreachable"), Some((Some("10.200.0.1"), None))),
        (200, JSON.String("10.200.0.2")),
        (
          2,
          [
            (`tunnel-${Api.tunnelName(id)}`, "10.200.0.1"),
            (`tunnel-${Api.tunnelName(next)}`, "10.200.0.2"),
          ],
        ),
        Some("unbound"),
        (200, JSON.String("origin")),
      ),
    )
  },
)

test(
  "a deploy whose app is forgotten as its container is made is never sent to its host",
  async () => {
    let base = stand()
    base.host.slow := true
    let drawn = ref(0.)
    let caller = ref(None)
    let forgotten = ref(None)
    let state = base.parts.state
    let stood = {
      ...base,
      parts: {
        ...base.parts,
        state: {
          ...state,
          drawApp: async (~random) => {
            drawn := (await state.drawApp(~random))
            drawn.contents
          },
        },
        // The forget lands while the host makes the deploy's container, before it is declared.
        wait: async () =>
          switch (caller.contents, forgotten.contents) {
          | (Some(stood), None) =>
            forgotten :=
              Some(await called(stood, Operator, releases(Forget({app: drawn.contents}))))
          | (Some(_) | None, _) => ()
          },
      },
    }
    caller := Some(stood)
    let (binding, hash) = await opened(stood)
    let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
    let (status, answer) = await called(stood, Operator, releases(Deploy({binding, release})))
    let app = drawn.contents
    deepEqual(
      (
        forgotten.contents->Option.map(((status, _)) => status),
        (status, answer->reason, answer->member("message")->JSON.Decode.string),
        stood.host.deployed.contents,
        await stood.parts.state.deployment(app),
      ),
      (
        Some(200),
        (
          404,
          Some("not_found"),
          Some(`app ${Ids.text(app)}, app ${Ids.text(app)} was removed as it was deployed`),
        ),
        None,
        None,
      ),
    )
  },
)

test(
  "a tunnel not made gives its address back, so the binding may still be bound by its origin",
  async () => {
    let (faked, made, routes) = tunnels(~failing=true)
    let (stood, _, id) = await originStand(~tunnels=faked, ref(Driver))
    let (status, refused) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
    let kept = (await stood.parts.state.binding(id))->Option.flatMap(b => b.address)
    let (bound, answer) = await called(stood, Host(id), byOrigin("https://driver.example.com"))
    deepEqual(
      (
        (status, refused->reason, kept),
        (made.contents, routes),
        (bound, answer->data->member("reached")->member("name")),
      ),
      ((503, Some("unreachable"), None), (1, []), (200, JSON.String("origin"))),
    )
  },
)
