/***
 * `Remote` held to reaching a machine as deploy does, and to a forward on a connection of its own.
 */
open Node

test("local is localhost's port 2222, and any other name is ssh's own", () => {
  let local = Remote.target("local")
  deepEqual(local.host, "root@localhost")
  ok(local.options->Array.includes("2222"))
  let machine = Remote.target("root@machine.example")
  deepEqual(machine.host, "root@machine.example")
  ok(!(machine.options->Array.includes("2222")))
})

test("a forward holds a port of the machine's loopback on a connection shared with nothing", () => {
  let args = Remote.forward(Remote.target("root@machine.example"), ~local=50000, ~remote=47483)
  // ssh takes an option's first value, so what comes first wins over the shared connection's.
  deepEqual(
    args->Array.slice(~start=0, ~end=4),
    ["-o", "ControlMaster=no", "-o", "ControlPath=none"],
  )
  ok(args->Array.includes("50000:127.0.0.1:47483"))
  ok(args->Array.includes("-N"))
  deepEqual(args->Array.at(-1), Some("root@machine.example"))
})
