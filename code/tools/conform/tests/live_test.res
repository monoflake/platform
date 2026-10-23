/***
 * `Live` held to reading what the live driver answers, its list, its refusals and hello.
 */
open Node

let answered = (status, body): Live.answered => {status, body}

test("an answer is its body and then its status on a line of its own", () => {
  deepEqual(Live.readAnswered("{\"a\": 1}\n200"), Ok(answered(200, "{\"a\": 1}")))
  deepEqual(Live.readAnswered("hello\nfrom\n403\n"), Ok(answered(403, "hello\nfrom")))
  ok(Live.readAnswered("no status")->Result.isError)
})

test("describe's answer is read as the contract's list", () => {
  let body = `{"status": "success", "data": {"generation": 1, "policy": 0, "grace": 604800, "items": []}}`
  deepEqual(Live.list(answered(200, body))->Result.map(list => list.generation), Ok(1.))
  ok(Live.list(answered(200, `{"status": "success", "data": {"generation": 1}}`))->Result.isError)
  ok(Live.list(answered(500, "not JSON"))->Result.isError)
})

let error = (reason, message) =>
  `{"status": "error", "failure": "rejected", "reason": "${reason}", "message": "${message}"}`

test("a call with no token is denied, and an unknown interface refused naming it", () => {
  deepEqual(Live.denied(answered(403, error("denied", "no credential"))), Ok())
  ok(Live.denied(answered(200, error("denied", "no credential")))->Result.isError)
  let unknown = error("malformed", "no interface nothing, one of management")
  deepEqual(Live.refused(answered(400, unknown)), Ok())
  ok(Live.refused(answered(400, error("malformed", "not JSON")))->Result.isError)
})

test("hello is a 200 saying so", () => {
  deepEqual(Live.greeted(answered(200, "hello from a machine")), Ok())
  ok(Live.greeted(answered(502, "hello"))->Result.isError)
  ok(Live.greeted(answered(200, "bad gateway"))->Result.isError)
})

test("the shells read the token on the machine and name the app's host", () => {
  ok(Live.described->String.includes(`Authorization: Bearer $(t)`))
  ok(!(Live.untokened->String.includes("Authorization")))
  ok(Live.unknown->String.includes("/nothing/describe"))
  ok(Live.hello(~app=1, ~binding=1)->String.includes("Host: app-1.b1"))
  ok(Live.hello(~app=1, ~binding=1)->String.includes("--value driver-machine-entry"))
  let deployment = Live.deployment(~app=1)
  ok(deployment->String.includes("/deployments/describe"))
  ok(deployment->String.includes(`"runs":{"name":"app","id":1}`))
  ok(Live.binding->String.includes("cut -s -d. -f1"))
})
