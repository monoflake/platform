/***
 * `Machine` held to RFC n0o4l, a target reached as driver's `dev` reaches it, what the machine says
 * of itself read, and an answer read as its output's type.
 */
open Node

module Contracts = Envelope.Contracts

test("local is localhost's port 2222, and any other name is ssh's own", () => {
  let local = Machine.target("local")
  deepEqual(local.host, "root@localhost")
  ok(local.options->Array.includes("2222"))
  let machine = Machine.target("root@machine.example")
  deepEqual(machine.host, "root@machine.example")
  ok(!(machine.options->Array.includes("2222")))
})

test("the facts give the directory, the binding and a tunnel only where one answers", () => {
  deepEqual(
    Machine.readFacts(
      "directory=/var/lib/driver-machine/artifacts\nbinding=1\ntunnel=https://a.example\n",
    ),
    Ok({
      directory: "/var/lib/driver-machine/artifacts",
      binding: "1",
      tunnel: Some("https://a.example"),
    }),
  )
  deepEqual(
    Machine.readFacts("directory=/d\nbinding=2\ntunnel=\n"),
    Ok({directory: "/d", binding: "2", tunnel: None}),
  )
  ok(Machine.readFacts("directory=\nbinding=1\n")->Result.isError)
  ok(Machine.readFacts("directory=/d\nbinding=\n")->Result.isError)
})

test("a call names its interface and operation, and reads the token on the machine", () => {
  let shell = Machine.call(
    Contracts.Interface.Management.toJson({
      call: Apply({generation: 1., items: []}),
      capabilities: [],
    }),
  )
  ok(shell->String.includes(`/management/apply`))
  ok(shell->String.includes(`$(o bindings)`))
  ok(shell->String.includes("--data-binary @-"))
})

test("an answer gives its output, its error's reason, or unread", () => {
  let held = Contracts.ManagementHeld.fromJson
  deepEqual(
    Machine.answer(`{"status": "success", "data": {"generation": 3}}`, held),
    Ok({generation: 3.}),
  )
  deepEqual(
    Machine.answer(
      `{"status": "error", "failure": "rejected", "reason": "not_found", "message": "none"}`,
      held,
    ),
    Error({reason: "not_found", message: "none"}),
  )
  let reason = text => Machine.answer(text, held)->Result.mapError(r => r.reason)
  deepEqual(reason("<html>"), Error("unread"))
  deepEqual(reason(`{"status": "success", "data": {}}`), Error("unread"))
})
