/***
 * `Instance` held to RFC n0o4l, what the machine says read, a subnet of its own chosen, the tokens
 * read in order, and what cleaning removed and left.
 */
open Node

let facts = "binding=1\nmount=/data\nsubvolumes=16\nroute=default\nroute=10.88.0.0/16\nroute=192.168.65.0/24\nlistening=0.0.0.0:37483\nlistening=[::]:22\nlistening=127.0.0.1%lo:53\n"

test("the facts give the live binding, the mount, the routes and the ports listened on", () =>
  deepEqual(
    Instance.readFacts(facts),
    Ok({
      binding: 1,
      mount: "/data",
      routes: ["default", "10.88.0.0/16", "192.168.65.0/24"],
      listening: [37483, 22, 53],
      subvolumes: 16,
    }),
  )
)

test("a machine whose binding or ports the run would take is refused", () => {
  ok(Instance.readFacts("binding=1000\nsubvolumes=0\n")->Result.isError)
  ok(Instance.readFacts("binding=\nsubvolumes=0\n")->Result.isError)
  ok(Instance.readFacts("binding=1\n")->Result.isError)
  ok(
    Instance.readFacts(
      `binding=1\nsubvolumes=0\nlistening=127.0.0.1:${Int.toString(Instance.port)}\n`,
    )->Result.isError,
  )
})

test("networks overlap where one holds an address of the other", () => {
  ok(Instance.overlaps("10.250.0.0/24", "10.0.0.0/8"))
  ok(Instance.overlaps("10.250.0.0/24", "10.250.0.7"))
  ok(Instance.overlaps("10.250.0.0/24", "default"))
  ok(!Instance.overlaps("10.250.0.0/24", "10.88.0.0/16"))
  ok(!Instance.overlaps("10.250.0.0/24", "10.251.0.0/24"))
  ok(!Instance.overlaps("10.250.0.0/24", "not a network"))
})

test("the subnet is the first of its own no route overlaps, the default route passed over", () => {
  deepEqual(Instance.subnet(["default", "10.88.0.0/16"]), Some("10.250.0.0/24"))
  deepEqual(Instance.subnet(["10.250.0.0/16"]), Some("10.251.0.0/24"))
  deepEqual(Instance.subnet(["10.0.0.0/8"]), None)
})

let secret = "A"->String.repeat(43)

test("the tokens are read in their bindings' order, each `<id>.<secret>`", () => {
  let first = Int.toString(Instance.first)
  let second = Int.toString(Instance.first + 1)
  deepEqual(
    Instance.readTokens(`${first}.${secret}\n${second}.${secret}\n`, ~count=2),
    Ok([`${first}.${secret}`, `${second}.${secret}`]),
  )
  ok(Instance.readTokens(`${first}.${secret}\n`, ~count=2)->Result.isError)
  ok(Instance.readTokens(`${second}.${secret}\n${first}.${secret}\n`, ~count=2)->Result.isError)
  ok(Instance.readTokens(`${first}.short\n`, ~count=1)->Result.isError)
})

test("the shell starts the driver on the bindings, its own port, bridge and subnet", () => {
  let shell = Instance.started(~count=2, ~subnet="10.250.0.0/24")
  ok(shell->String.includes(`--unit=${Instance.unit}`))
  ok(shell->String.includes(`--listen=127.0.0.1:${Int.toString(Instance.port)}`))
  // The entry is a unit of its own, so the second driver is given none, RFC rmll5.
  ok(!(shell->String.includes("--entry")))
  ok(shell->String.includes(`--bridge=${Instance.bridge} --subnet=10.250.0.0/24`))
  ok(shell->String.includes(`-le ${Int.toString(Instance.first + 1)}`))
})

test("what cleaning said is read as removed and left", () => {
  deepEqual(
    Instance.readCleaned("removed the unit u\nremoved /run/x\nleft the qgroup 1/1000\nnoise\n"),
    {removed: ["the unit u", "/run/x"], left: ["the qgroup 1/1000"]},
  )
  ok(Instance.cleaned(~mount="/data", ~subvolumes=16)->String.includes("-le 16"))
})
