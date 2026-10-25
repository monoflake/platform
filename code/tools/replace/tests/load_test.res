/***
 * `Load` held to reading each ask the shell printed and what curl and fetch make of it.
 */
open Node

test("a line is its client, its times, curl's exit and the status", () => {
  deepEqual(
    Load.read("3 1000 1012 0 200"),
    Some({Load.began: 1000., ended: 1012., outcome: Answered}),
  )
  deepEqual(
    Load.read("1 1000 1001 7 000\n")->Option.map(a => a.outcome),
    Some(Refused("connection refused")),
  )
  deepEqual(Load.read(""), None)
  deepEqual(Load.read("1 x 1001 0 200"), None)
  deepEqual(Load.read("entry on 127.0.0.1:36879"), None)
})

test("a refusal is a connection refused, and anything else not 200 a failure", () => {
  deepEqual(Load.curled(~exit=0, ~status="200"), Answered)
  deepEqual(Load.curled(~exit=0, ~status="503"), Failed("HTTP 503"))
  deepEqual(Load.curled(~exit=7, ~status="000"), Refused("connection refused"))
  deepEqual(Load.curled(~exit=56, ~status="000"), Failed("connection reset"))
  deepEqual(Load.curled(~exit=3, ~status="000"), Failed("curl exit 3"))
})

test("through the tunnel, a 200 saying hello answers and a refused cause refuses", () => {
  deepEqual(Load.fetched(~status=200, ~body="hello from a machine"), Answered)
  ok(
    switch Load.fetched(~status=502, ~body="bad gateway") {
    | Failed(_) => true
    | Answered | Refused(_) => false
    },
  )
  deepEqual(
    Load.thrown(~code=Some("ECONNREFUSED"), ~message="fetch failed"),
    Refused("connection refused"),
  )
  deepEqual(
    Load.thrown(~code=Some("ECONNRESET"), ~message="fetch failed"),
    Failed("fetch failed, ECONNRESET"),
  )
  deepEqual(Load.thrown(~code=None, ~message="timed out"), Failed("timed out"))
})

test("the shell asks the app's host on a new connection each time until it is stopped", () => {
  let shell = Load.shell(~app=1., ~binding=2., ~stop="/tmp/stop")
  ok(shell->String.includes("Host: 00000001.b00000002"))
  ok(shell->String.includes(`[ ! -e "$stop" ]`))
  ok(shell->String.includes(`seq ${Int.toString(Load.clients)}`))
  ok(shell->String.includes("--value driver-machine-entry"))
  let high = Load.shell(~app=4275878552., ~binding=169552957., ~stop="/s")
  ok(high->String.includes("-H 'Host: fedcba98.b0a1b2c3d'"))
})
