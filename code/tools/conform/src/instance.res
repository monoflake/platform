let unit = "monoflake-conform"
let directory = "/run/monoflake-conform"
let port = 47483
let first = 1000
let bridge = "conform0"

/** The subnets it may take, each a /24 apart from the live driver's. */
let candidates = ["10.250.0.0/24", "10.251.0.0/24", "10.252.0.0/24", "10.253.0.0/24"]

let int = Int.toString

/** The live driver's command line, and `o` printing the first value of one of its flags. */
let flags = `a=$(systemctl show -p ExecStart --value monoflake-driver) || exit 1
o() { printf '%s\\n' "$a" | grep -o -- "--$1=[^ ;]*" | head -n 1 | cut -d= -f2-; }
`

// The live token's id is what stands before its dot, and only that is printed.
let facts = `${flags}b=$(o bindings) && [ -n "$b" ] || { echo "the driver names no binding" >&2; exit 1; }
m=$(o mount); m=\${m:-/data}
echo "binding=$(head -n 1 "$b" | cut -s -d. -f1)"
echo "mount=$m"
echo "subvolumes=$(btrfs subvolume list "$m" | wc -l)"
ip -4 route show | awk '{ print "route=" $1 }'
ss -Hltn | awk '{ print "listening=" $4 }'
echo "local=$(o local)"
echo "largest=$(o largest)"
echo "architecture=$(uname -m)"
`

type facts = {
  binding: int,
  mount: string,
  routes: array<string>,
  listening: array<int>,
  subvolumes: int,
  local: option<string>,
  largest: option<float>,
  architecture: option<string>,
}

/** A path put in a shell between single quotes, which nothing of it may close. */
let plainPath = /^\/[A-Za-z0-9._\/-]+$/

/** An architecture as OCI names it, by what `uname -m` prints. */
let architectureOf = machine =>
  switch machine {
  | "aarch64" | "arm64" => Some("arm64")
  | "x86_64" | "amd64" => Some("amd64")
  | _ => None
  }

/** Each line's name and value, split at its first `=`. */
let said = text =>
  text
  ->String.split("\n")
  ->Array.filterMap(line =>
    switch line->String.indexOf("=") {
    | -1 => None
    | at =>
      Some((line->String.slice(~start=0, ~end=at), line->String.slice(~start=at + 1)->String.trim))
    }
  )

let valuesOf = (said, name) =>
  said->Array.filterMap(((key, value)) => key == name && value != "" ? Some(value) : None)

let whole = text =>
  switch Int.fromString(text) {
  | Some(n) if Int.toString(n) == text => Some(n)
  | _ => None
  }

/** The port an address `ss` writes ends in, after its last colon. */
let portOf = address =>
  switch address->String.lastIndexOf(":") {
  | -1 => None
  | at => whole(address->String.slice(~start=at + 1))
  }

let readFacts = text => {
  let said = said(text)
  let one = name => valuesOf(said, name)->Array.get(0)
  let listening = valuesOf(said, "listening")->Array.filterMap(portOf)
  switch (one("binding")->Option.flatMap(whole), one("subvolumes")->Option.flatMap(whole)) {
  | (None, _) => Error("the live binding's token names no id before its dot")
  | (_, None) => Error("the subvolumes of the mount were not counted")
  | (Some(binding), _) if binding >= first =>
    Error(`the live binding ${int(binding)} is among those from ${int(first)} this run takes`)
  | (_, Some(_)) if listening->Array.includes(port) =>
    Error(`something listens on port ${int(port)} already`)
  | (Some(binding), Some(subvolumes)) =>
    Ok({
      binding,
      mount: one("mount")->Option.getOr("/data"),
      routes: valuesOf(said, "route"),
      listening,
      subvolumes,
      local: one("local")->Option.filter(l => plainPath->RegExp.test(l)),
      largest: one("largest")
      ->Option.flatMap(Float.fromString)
      ->Option.filter(n => Math.floor(n) == n && n > 0.),
      architecture: one("architecture")->Option.flatMap(architectureOf),
    })
  }
}

let served = local => `${local}/monoflake-conform`

type padded = {file: string, from: string, size: float}

type fixtures = {files: array<string>, padded: array<padded>}

/** A file's name as the runner's build writes one, with nothing a shell reads. */
let plainFile = /^[a-z0-9-]+\.tar$/

let readFixtures = manifest => {
  let field = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))
  let text = (json, name) => field(json, name)->Option.flatMap(JSON.Decode.string)
  switch JSON.parseOrThrow(manifest) {
  | exception JsExn(_) => Error("the fixtures' manifest is no JSON")
  | json =>
    let files =
      field(json, "files")
      ->Option.flatMap(JSON.Decode.array)
      ->Option.getOr([])
      ->Array.map(JSON.Decode.string)
    let padded =
      field(json, "padded")
      ->Option.flatMap(JSON.Decode.array)
      ->Option.getOr([])
      ->Array.map(p =>
        switch (
          text(p, "file"),
          text(p, "from"),
          field(p, "size")->Option.flatMap(JSON.Decode.float),
        ) {
        | (Some(file), Some(from), Some(size)) => Some({file, from, size})
        | (Some(_) | None, Some(_) | None, Some(_) | None) => None
        }
      )
    let named = name => plainFile->RegExp.test(name)
    switch (
      files->Array.every(f => f->Option.mapOr(false, named)),
      padded->Array.every(p =>
        p->Option.mapOr(false, p => named(p.file) && named(p.from) && Math.floor(p.size) == p.size)
      ),
    ) {
    | (true, true) =>
      Ok({files: files->Array.filterMap(f => f), padded: padded->Array.filterMap(p => p)})
    | (false, _) | (_, false) => Error("the fixtures' manifest names a file no build writes")
    }
  }
}

let emptied = directory =>
  `rm -rf '${directory}' && mkdir -m 755 '${directory}'
`

let copied = (~directory, ~file) =>
  `cat > '${directory}/${file}'
`

let made = (~directory, padded) =>
  padded
  ->Array.map(({file, from, size}) =>
    `cp '${directory}/${from}' '${directory}/${file}' && truncate -s ${size->Float.toString} '${directory}/${file}'
`
  )
  ->Array.join("")

/** An IPv4 address as a number, or none where it is not four octets. */
let addressOf = text => {
  let octets = text->String.split(".")->Array.filterMap(whole)
  octets->Array.length == 4 && octets->Array.every(o => o >= 0 && o <= 255)
    ? Some(octets->Array.reduce(0., (n, o) => n *. 256. +. Int.toFloat(o)))
    : None
}

/** A network's first address and prefix length, a bare address being its own /32. */
let networkOf = text =>
  switch text->String.split("/") {
  | [address] => addressOf(address)->Option.map(a => (a, 32))
  | [address, length] =>
    switch (addressOf(address), whole(length)) {
    | (Some(a), Some(n)) if n >= 0 && n <= 32 => Some((a, n))
    | _ => None
    }
  | _ => None
  }

let overlaps = (a, b) =>
  switch (
    a == "default" ? Some((0., 0)) : networkOf(a),
    b == "default" ? Some((0., 0)) : networkOf(b),
  ) {
  | (Some((x, m)), Some((y, n))) =>
    let size = Math.pow(2., ~exp=Int.toFloat(32 - Math.Int.min(m, n)))
    Math.floor(x /. size) == Math.floor(y /. size)
  | _ => false
  }

// A default route overlaps every network, so it is passed over as the bridge's route is not one.
let subnet = routes =>
  candidates->Array.find(c => !(routes->Array.some(r => r != "default" && overlaps(c, r))))

let started = (~count, ~subnet) => {
  let last = first + count - 1
  `set -e
${flags}p=$(systemctl show -p Environment --value monoflake-driver | tr ' ' '\\n' | sed -n 's/^PATH=//p')
bin=$(printf '%s\\n' "$a" | sed -n 's/^{ path=\\([^ ;]*\\) .*/\\1/p')
kept=$(printf '%s\\n' "$a" | grep -oE -- '--(runc|crun|youki|plugins|btrfs|largest|local|mount|containerd|workerd)=[^ ;]*' | tr '\\n' ' ')
d=${directory}
mkdir -m 700 "$d"
mkdir -m 700 "$d/bindings" "$d/state" "$d/secrets"
i=${int(first)}
while [ "$i" -le ${int(last)} ]; do
  printf '%s.%s\\n' "$i" "$(head -c 32 /dev/urandom | basenc --base64url | tr -d '=')" > "$d/bindings/$i"
  set -- "$@" "--bindings=$d/bindings/$i"
  i=$((i + 1))
done
systemd-run --quiet --collect --unit=${unit} --setenv=PATH="$p" "$bin" $kept "$@" \\
  --listen=127.0.0.1:${int(port)} \\
  --state="$d/state" --secrets="$d/secrets" --bridge=${bridge} --subnet=${subnet}
n=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:${int(
      port,
    )}/management/describe)" = 403 ]; do
  n=$((n + 1))
  [ "$n" -lt 100 ] || { echo "the driver did not answer within 10 s" >&2; journalctl -u ${unit} -n 20 --no-pager >&2; exit 1; }
  sleep 0.1
done
i=${int(first)}
while [ "$i" -le ${int(last)} ]; do cat "$d/bindings/$i"; i=$((i + 1)); done
`
}

let secretLength = 43

let readTokens = (text, ~count) => {
  let lines = text->String.split("\n")->Array.map(String.trim)->Array.filter(l => l != "")
  let wellMade = (k, line) =>
    switch line->String.split(".") {
    | [id, secret] =>
      id == int(first + k) &&
      secret->String.length == secretLength &&
      /^[A-Za-z0-9_-]+$/->RegExp.test(secret)
    | _ => false
    }
  if lines->Array.length != count {
    Error(`${int(lines->Array.length)} tokens printed of the ${int(count)} made`)
  } else if !(lines->Array.everyWithIndex((line, k) => wellMade(k, line))) {
    Error("a token printed is not its binding's, `<id>.<secret>`")
  } else {
    Ok(lines)
  }
}

let cleaned = (~mount, ~subvolumes, ~served) =>
  `u=${unit} d=${directory} m=${mount} f=${int(first)} br=${bridge} v='${served->Option.getOr("")}'
numbered() { case "$1" in ''|*[!0-9]*) return 1;; esac; [ "$1" -ge "$f" ]; }
mine() { k=\${1#b}; k=\${k%%-*}; case "$k" in ''|*[!0-9]*) return 1;; esac; [ "$k" -ge "$f" ]; }
q=inet\\ cni_plugins_masquerade\\ masq_checks
rules() { nft -a list chain $q 2> /dev/null | grep "net: $br," | sed 's/.*# handle //'; }
if systemctl list-units --all --no-legend "$u.service" | grep -q .; then
  systemctl stop "$u.service" 2> /dev/null; systemctl reset-failed "$u.service" 2> /dev/null
  echo "removed the unit $u"
fi
for ns in $(ctr namespaces ls -q); do
  mine "$ns" || continue
  for t in $(ctr -n "$ns" tasks ls -q); do
    ctr -n "$ns" tasks kill -s SIGKILL "$t" 2> /dev/null; ctr -n "$ns" tasks rm -f "$t"
  done
  for c in $(ctr -n "$ns" containers ls -q); do ctr -n "$ns" containers rm "$c"; done
  ctr -n "$ns" leases ls -q | xargs -r ctr -n "$ns" leases rm --sync
  ctr -n "$ns" images ls -q | xargs -r ctr -n "$ns" images rm --sync
  for pass in 1 2 3 4 5 6 7 8; do
    for s in $(ctr -n "$ns" snapshots --snapshotter btrfs ls | awk 'NR > 1 { print $1 }'); do
      ctr -n "$ns" snapshots --snapshotter btrfs rm "$s" 2> /dev/null
    done
  done
  ctr -n "$ns" content ls -q | xargs -r ctr -n "$ns" content rm
  ctr namespaces rm "$ns" > /dev/null && echo "removed the namespace $ns"
done
for u2 in volumes buckets; do
  for b in "$m/$u2"/*; do
    [ -d "$b" ] && numbered "\${b##*/}" || continue
    for sv in "$b"/*; do [ -d "$sv" ] && btrfs subvolume delete "$sv" > /dev/null && echo "removed the subvolume $sv"; done
    rmdir "$b" && echo "removed $b"
  done
done
btrfs qgroup clear-stale "$m" > /dev/null 2>&1
for g in $(btrfs qgroup show --raw "$m" 2> /dev/null | awk '{ print $1 }' | grep '^1/'); do
  mine "b\${g#1/}" || continue
  for c in $(btrfs qgroup show --raw -c "$m" 2> /dev/null | awk -v g="$g" '$1 == g { print $4 }' | tr ',' ' '); do
    case "$c" in 0/*) btrfs qgroup remove "$c" "$g" "$m" > /dev/null 2>&1;; esac
  done
  btrfs qgroup destroy "$g" "$m" && echo "removed the qgroup $g"
done
for n in $(ip netns list | awk '{ print $1 }'); do
  mine "$n" && ip netns delete "$n" && echo "removed the network namespace $n"
done
for h in $(rules); do nft delete rule $q handle "$h" && echo "removed a masquerade rule of $br"; done
if ip link show "$br" > /dev/null 2>&1; then ip link delete "$br" && echo "removed the bridge $br"; fi
for c in /sys/fs/cgroup/b*; do
  [ -d "$c" ] && mine "\${c##*/}" && find "$c" -depth -type d -exec rmdir {} + && echo "removed the cgroup $c"
done
if [ -e "$d" ]; then rm -rf "$d" && echo "removed $d"; fi
if [ -n "$v" ] && [ -e "$v" ]; then rm -rf "$v" && echo "removed $v"; fi
systemctl list-units --all --no-legend "$u.service" | grep -q . && echo "left the unit $u"
for ns in $(ctr namespaces ls -q); do mine "$ns" && echo "left the namespace $ns"; done
for g in $(btrfs qgroup show --raw "$m" 2> /dev/null | awk '{ print $1 }' | grep '^1/'); do
  mine "b\${g#1/}" && echo "left the qgroup $g"
done
for n in $(ip netns list | awk '{ print $1 }'); do mine "$n" && echo "left the network namespace $n"; done
[ -z "$(rules)" ] || echo "left a masquerade rule of $br"
ip link show "$br" > /dev/null 2>&1 && echo "left the bridge $br"
for c in /sys/fs/cgroup/b*; do [ -d "$c" ] && mine "\${c##*/}" && echo "left the cgroup $c"; done
for u2 in volumes buckets; do
  for b in "$m/$u2"/*; do [ -d "$b" ] && numbered "\${b##*/}" && echo "left $b"; done
done
[ -e "$d" ] && echo "left $d"
[ -n "$v" ] && [ -e "$v" ] && echo "left $v"
s=$(btrfs subvolume list "$m" | wc -l)
[ "$s" -le ${int(subvolumes)} ] || echo "left $((s - ${int(
      subvolumes,
    )})) subvolumes more than before"
true
`

type cleaned = {removed: array<string>, left: array<string>}

let readCleaned = text => {
  let lines = text->String.split("\n")->Array.map(String.trim)
  let after = word =>
    lines->Array.filterMap(line =>
      line->String.startsWith(`${word} `)
        ? Some(line->String.slice(~start=word->String.length + 1))
        : None
    )
  {removed: after("removed"), left: after("left")}
}
