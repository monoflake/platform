/***
 * `Instance` held to RFC n0o4l, what the machine says read, a subnet of its own chosen, the tokens
 * read in order, and what cleaning removed and left.
 */
open Node

let facts = "binding=1\nmount=/data\nsubvolumes=16\nroute=default\nroute=10.88.0.0/16\nroute=192.168.65.0/24\nlistening=0.0.0.0:37483\nlistening=[::]:22\nlistening=127.0.0.1%lo:53\nlocal=/var/lib/driver-machine/artifacts\nlargest=1073741824\narchitecture=aarch64\n"

test(
  "the facts give the live binding, the mount, the routes, the ports and what serves artifacts",
  () =>
    deepEqual(
      Instance.readFacts(facts),
      Ok({
        binding: 1,
        mount: "/data",
        routes: ["default", "10.88.0.0/16", "192.168.65.0/24"],
        listening: [37483, 22, 53],
        subvolumes: 16,
        local: Some("/var/lib/driver-machine/artifacts"),
        largest: Some(1073741824.),
        architecture: Some("arm64"),
      }),
    ),
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
  ok(
    Instance.readFacts(
      `binding=1\nsubvolumes=0\nlistening=0.0.0.0:${Int.toString(Instance.entry)}\n`,
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
  // The entry is a unit of its own, so the second driver is given a port of its own to name.
  ok(shell->String.includes(`--entry=${Int.toString(Instance.entry)}`))
  ok(Instance.entry != 36879 && Instance.entry != 37483 && Instance.entry != Instance.port)
  ok(shell->String.includes(`--bridge=${Instance.bridge} --subnet=10.250.0.0/24`))
  ok(shell->String.includes(`-le ${Int.toString(Instance.first + 1)}`))
})

test("what cleaning said is read as removed and left", () => {
  deepEqual(
    Instance.readCleaned("removed the unit u\nremoved /run/x\nleft the qgroup 1/1000\nnoise\n"),
    {removed: ["the unit u", "/run/x"], left: ["the qgroup 1/1000"]},
  )
  let shell = Instance.cleaned(~mount="/data", ~subvolumes=16, ~served=Some("/srv/a/conform"))
  ok(shell->String.includes("-le 16"))
  ok(shell->String.includes("v='/srv/a/conform'"))
  ok(shell->String.includes("for u2 in volumes buckets"))
  // What the lists made on the mount goes before the qgroups, each emptied of its members.
  let at = text => shell->String.indexOf(text)
  ok(at("btrfs subvolume delete") < at("btrfs qgroup destroy"))
  ok(at("btrfs qgroup remove") < at("btrfs qgroup destroy"))
  // A name tested as the run's is never the variable a loop reads it from.
  ok(shell->String.includes("mine() { k=") && !(shell->String.includes("mine() { n=")))
})

test("a directory, a bound or an architecture the machine does not give is none", () => {
  let read = Instance.readFacts(
    "binding=1\nsubvolumes=0\nlocal=/var/lib/a'b\nlargest=many\narchitecture=riscv64\n",
  )
  deepEqual(read->Result.map(f => (f.local, f.largest, f.architecture)), Ok((None, None, None)))
})

test("the manifest names the files to copy and those to pad, each a plain name", () => {
  let manifest = `{"built": {}, "files": ["echo-modules.tar"], "padded": [{"file": "echo-modules-oversized.tar", "from": "echo-modules.tar", "size": 1025}], "unbuilt": {}}`
  deepEqual(
    Instance.readFixtures(manifest),
    Ok({
      files: ["echo-modules.tar"],
      padded: [{file: "echo-modules-oversized.tar", from: "echo-modules.tar", size: 1025.}],
    }),
  )
  ok(Instance.readFixtures(`{"files": ["a'b.tar"]}`)->Result.isError)
  ok(Instance.readFixtures("not JSON")->Result.isError)
  let made = Instance.made(~directory="/srv/f", [{file: "b.tar", from: "a.tar", size: 1025.}])
  ok(made->String.includes("cp '/srv/f/a.tar' '/srv/f/b.tar' && truncate -s 1025 '/srv/f/b.tar'"))
  ok(
    Instance.served(
      "/var/lib/driver-machine/artifacts",
    ) == "/var/lib/driver-machine/artifacts/conform",
  )
})
