/***
 * `Instance` held to RFC n0o4l, what the machine says read, a subnet of its own chosen, the tokens
 * read in order, and what cleaning removed and left.
 */
open Node

/** What the machine said read for a run of 8 bindings. */
let readFacts = text => Instance.readFacts(text, ~count=8)

let facts = "binding=1\nmount=/data\nsubvolumes=16\nroute=default\nroute=10.88.0.0/16\nroute=192.168.65.0/24\nlistening=0.0.0.0:37483\nlistening=[::]:22\nlistening=127.0.0.1%lo:53\nlocal=/var/lib/driver-machine/artifacts\nlargest=1073741824\narchitecture=aarch64\n"

test(
  "the facts give the live binding, the mount, the routes, the ports and what serves artifacts",
  () =>
    deepEqual(
      readFacts(facts),
      Ok({
        binding: 1.,
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

test("the live binding is read as its token writes it, a decimal of 32 bits", () => {
  let binding = text =>
    readFacts(`binding=${text}\nsubvolumes=0\n`)->Result.map(facts => facts.binding)
  deepEqual(binding("4275878552"), Ok(4275878552.))
  deepEqual(binding("999"), Ok(999.))
  deepEqual(binding("1008"), Ok(1008.))
  ok(binding("0")->Result.isError)
  ok(binding("01")->Result.isError)
  ok(binding("4294967296")->Result.isError)
  ok(binding("fedcba98")->Result.isError)
})

test("a machine whose binding or ports the run would take is refused", () => {
  ok(readFacts("binding=1000\nsubvolumes=0\n")->Result.isError)
  ok(readFacts("binding=1007\nsubvolumes=0\n")->Result.isError)
  ok(readFacts("binding=\nsubvolumes=0\n")->Result.isError)
  ok(readFacts("binding=1\n")->Result.isError)
  ok(
    readFacts(
      `binding=1\nsubvolumes=0\nlistening=127.0.0.1:${Int.toString(Instance.port)}\n`,
    )->Result.isError,
  )
  ok(
    readFacts(
      `binding=1\nsubvolumes=0\nlistening=0.0.0.0:${Int.toString(Instance.entry)}\n`,
    )->Result.isError,
  )
})

test(
  "a port an earlier run's unit holds is passed, and refused where anything else holds it",
  () => {
    let entryAt = `10.250.0.1:${Int.toString(Instance.entry)}`
    let driverAt = `127.0.0.1:${Int.toString(Instance.port)}`
    let leftover = `binding=1\nsubvolumes=0\nlistening=${entryAt}\nlistening=${driverAt}\nours=${entryAt}\nours=${driverAt}\n`
    ok(readFacts(leftover)->Result.isOk)
    // What the run left is still told as listening, so only the excuse is new.
    deepEqual(
      readFacts(leftover)->Result.map(f => f.listening),
      Ok([Instance.entry, Instance.port]),
    )
    ok(
      readFacts(
        `binding=1\nsubvolumes=0\nlistening=0.0.0.0:${Int.toString(
            Instance.entry,
          )}\nours=${entryAt}\n`,
      )->Result.isError,
    )
    ok(
      readFacts(
        `binding=1\nsubvolumes=0\nlistening=${driverAt}\nlistening=[::1]:${Int.toString(
            Instance.port,
          )}\nours=${driverAt}\n`,
      )->Result.isError,
    )
    // The shell names an address ours by the entry's socket and by the driver's own process.
    ok(
      Instance.facts->String.includes(
        `systemctl show -p Listen --value ${Instance.unit}-entry.socket`,
      ),
    )
    ok(
      Instance.facts->String.includes(`systemctl show -p MainPID --value ${Instance.unit}.service`),
    )
  },
)

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

test(
  "the shell starts an entry of its own on the bridge's address, its subnet and containerd",
  () => {
    let shell = Instance.started(~count=1, ~subnet="10.251.0.0/24")
    let at = `10.251.0.1:${Int.toString(Instance.entry)}`
    ok(shell->String.includes(`--unit=${Instance.unit}-entry`))
    ok(
      shell->String.includes(`--socket-property=ListenStream=${at} --socket-property=FreeBind=yes`),
    )
    ok(shell->String.includes(`entry --listen=${at} --containerd="$c" --subnet=10.251.0.0/24`))
    ok(shell->String.includes("c=${c:-/run/containerd/containerd.sock}"))
    // The live entry's port is never taken, nor the address on the live bridge.
    ok(!(shell->String.includes(":36879")) && !(shell->String.includes("10.88.")))
    ok(shell->String.includes(`systemctl is-active --quiet ${Instance.unit}-entry.service`))
  },
)

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
  // The entry's socket and service are stopped before the driver and looked for again after.
  ok(shell->String.includes(`e=${Instance.unit}-entry `))
  ok(at(`systemctl stop "$e.$k"`) < at(`systemctl stop "$u.service"`))
  ok(shell->String.includes(`echo "removed the unit $e.$k"`))
  ok(shell->String.includes(`echo "left the unit $e.$k"`))
  ok(shell->String.includes("for k in socket service"))
  // A reacher's fence element is removed where it is the run's own, and looked for again after.
  ok(shell->String.includes(`nft delete element inet fence reaching "{ $el }"`))
  ok(shell->String.includes(`echo "left the fence element $el"`))
  ok(shell->String.includes(`$5 == ${Int.toString(Instance.entry)} && $1 ~ /^(10\\.250\\.0|`))
  ok(!(shell->String.includes("10\\.88")) && !(shell->String.includes("36879")))
  ok(at("fenced | while read") > at("fenced() {"))
})

test("a name is the run's only where the record names its binding, in hex or in decimal", () => {
  let shell = Instance.cleaned(~mount="/data", ~subvolumes=0, ~served=None)
  ok(shell->String.includes(`r=${Instance.recorded}`))
  ok(shell->String.includes(`[ -f "$r" ] && grep -qx -- "$1" "$r"`))
  // No numbered range is read, so a binding the record lacks is never taken.
  ok(!(shell->String.includes(`-ge "$f"`)) && !(shell->String.includes(`-lt "$l"`)))
  // Eight characters are hex, so b000003e8 is binding 1000 and b00000001 a live one.
  ok(shell->String.includes(`[0-9a-f]`->String.repeat(8) ++ ") k=$((0x$k));;"))
  // A qgroup's id is decimal, so it is never read as hex.
  ok(shell->String.includes(`numbered "\${g#1/}" || continue`))
  // Each binding something is left of is kept in the record, and only those.
  let kept = shell->String.split(`&& keep "`)->Array.length - 1
  ok(kept == 5)
  ok(shell->String.includes(`echo "left the namespace $ns" && keep "$k"`))
  ok(shell->String.includes(`echo "left the qgroup $g" && keep "\${g#1/}"`))
  ok(shell->String.includes(`sort -nu "$r.left" > "$r.new" && mv "$r.new" "$r"`))
  ok(shell->String.includes(`rm "$r" && echo "removed the record $r"`))
  // A listing containerd did not answer leaves the record whole, and counts as something left.
  ok(shell->String.includes(`left=1 unread=1`))
  ok(shell->String.includes(`if [ -n "$unread" ] || [ ! -f "$r" ]; then`))
  // A unit still there counts as something left.
  ok(shell->String.includes(`echo "left the unit $u" && left=1`))
})

test("the record is written before the driver starts, one binding a line", () => {
  let shell = Instance.started(~count=2, ~subnet="10.250.0.0/24")
  let at = text => shell->String.indexOf(text)
  ok(shell->String.includes(`printf '%s\\n' "$i" >> "$r.new"`))
  let moved = at(`mv "$r.new" "$r"`)
  ok(moved >= 0 && moved < at(`systemd-run --quiet --collect --unit=${Instance.unit} `))
  ok(Instance.recorded->String.startsWith("/var/lib/"))
})

test("a volume, bucket or qgroup of the run's bindings no earlier run recorded is refused", () => {
  let base = "binding=1\nsubvolumes=0\nnamespace=b1\nheld=1\n"
  ok(readFacts(base)->Result.isOk)
  ok(readFacts(base ++ "held=1005\n")->Result.isError)
  ok(readFacts(base ++ "held=1005\nrecorded=1005\n")->Result.isOk)
  ok(readFacts(base ++ "namespace=b000003ed\n")->Result.isError)
  ok(readFacts(base ++ "namespace=b000003ed-x\nrecorded=1005\n")->Result.isOk)
  ok(readFacts(base ++ "namespaces=unread\n")->Result.isError)
})

test("a namespace of the run's bindings no earlier run recorded is refused", () => {
  let base = "binding=1\nsubvolumes=0\nnamespace=b1\n"
  ok(readFacts(base)->Result.isOk)
  ok(readFacts(base ++ "namespace=b000003e8\n")->Result.isError)
  ok(readFacts(base ++ "namespace=b1001\n")->Result.isError)
  ok(readFacts(base ++ "namespace=b000003e8\nrecorded=1000\n")->Result.isOk)
  ok(readFacts(base ++ "namespace=b000003e8\nrecorded=1001\n")->Result.isError)
  // A binding beyond the run's own is never its business.
  ok(readFacts(base ++ "namespace=b000003f0\n")->Result.isOk)
})

test("a directory, a bound or an architecture the machine does not give is none", () => {
  let read = readFacts(
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
