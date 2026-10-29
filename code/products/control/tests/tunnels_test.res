/*** `Tunnels` held to Cloudflare's API as RFC rxmd9 read it, against a fetch faked. */
open Node

type sent = {method: string, url: string, authorization: option<string>, body: string}

let faked = answers => {
  let sent = []
  let fetch = async request => {
    let header = name => request->Web.requestHeaders->Web.header(name)->Nullable.toOption
    let body = Web.fromUtf8(await request->Web.bytesOf)
    sent->Array.push({
      method: request->Web.method_,
      url: request->Web.url,
      authorization: header("authorization"),
      body,
    })
    let (status, text) = answers->Array.get(sent->Array.length - 1)->Option.getOr((500, "{}"))
    Web.answered(~status, ~contentType="application/json", text)
  }
  (
    Tunnels.through(
      {api: "https://api.test/client/v4", account: "acct", credential: "edit"},
      fetch,
    ),
    sent,
  )
}

test(
  "a tunnel is made by its name, routed to one address and its token asked, each by the credential",
  async () => {
    let (tunnels, sent) = faked([
      (200, `{"success": true, "errors": [], "result": {"id": "t-1", "name": "00000001"}}`),
      (200, `{"success": true, "errors": [], "result": {"id": "r-1"}}`),
      (200, `{"success": true, "errors": [], "result": "the token"}`),
    ])
    deepEqual(await tunnels.make("00000001"), Ok("t-1"))
    deepEqual(await tunnels.route(~tunnel="t-1", ~address="10.200.0.1"), Ok())
    deepEqual(await tunnels.token("t-1"), Ok("the token"))
    deepEqual(
      sent->Array.map(s => (s.method, s.url, s.authorization)),
      [
        ("POST", "https://api.test/client/v4/accounts/acct/cfd_tunnel", Some("Bearer edit")),
        ("POST", "https://api.test/client/v4/accounts/acct/teamnet/routes", Some("Bearer edit")),
        (
          "GET",
          "https://api.test/client/v4/accounts/acct/cfd_tunnel/t-1/token",
          Some("Bearer edit"),
        ),
      ],
    )
    deepEqual(
      sent->Array.slice(~start=0, ~end=2)->Array.map(s => JSON.parseOrThrow(s.body)),
      [
        JSON.parseOrThrow(`{"name": "00000001", "config_src": "cloudflare"}`),
        JSON.parseOrThrow(`{"network": "10.200.0.1/32", "tunnel_id": "t-1"}`),
      ],
    )
  },
)

test("an answer the API marks failed, or no JSON, is its first error or its status", async () => {
  let (tunnels, _) = faked([
    (403, `{"success": false, "errors": [{"code": 10000, "message": "Authentication error"}]}`),
    (502, "bad gateway"),
    (200, `{"success": true, "result": {"name": "no id"}}`),
  ])
  deepEqual(await tunnels.make("00000001"), Error("Authentication error"))
  deepEqual(await tunnels.token("t-1"), Error("the API answered 502 and no JSON"))
  deepEqual(await tunnels.make("00000001"), Error("the API answered a tunnel with no id"))
})

test("a route refused is made already where the tunnel's routes hold its address", async () => {
  let exists = `{"success": false, "errors": [{"code": 1014, "message": "route exists"}]}`
  let (tunnels, sent) = faked([
    (409, exists),
    (
      200,
      `{"success": true, "result": [{"network": "10.200.0.9/32"}, {"network": "10.200.0.1/32"}]}`,
    ),
    (409, exists),
    (200, `{"success": true, "result": [{"network": "10.200.0.9/32"}]}`),
  ])
  deepEqual(await tunnels.route(~tunnel="t-1", ~address="10.200.0.1"), Ok())
  deepEqual(await tunnels.route(~tunnel="t-1", ~address="10.200.0.1"), Error("route exists"))
  deepEqual(
    sent->Array.map(s => (s.method, s.url))->Array.slice(~start=0, ~end=2),
    [
      ("POST", "https://api.test/client/v4/accounts/acct/teamnet/routes"),
      (
        "GET",
        "https://api.test/client/v4/accounts/acct/teamnet/routes?tunnel_id=t-1&is_deleted=false",
      ),
    ],
  )
})
