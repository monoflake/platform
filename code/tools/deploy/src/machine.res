module Contracts = Envelope.Contracts

type target = {host: string, options: array<string>}

/** One connection kept open between the phases, so each costs no handshake. */
let kept = [
  "-o",
  "BatchMode=yes",
  "-o",
  "ControlMaster=auto",
  "-o",
  // Under the home, as the system's own temporary directory is too long a path for a socket.
  "ControlPath=~/.ssh/monoflake-deploy-%C",
  "-o",
  "ControlPersist=120",
]

let isLocal = name => name == "local"

let target = name =>
  isLocal(name)
    ? {
        host: "root@localhost",
        options: [
          ...kept,
          "-p",
          "2222",
          "-o",
          "StrictHostKeyChecking=no",
          "-o",
          "UserKnownHostsFile=/dev/null",
          "-o",
          "LogLevel=ERROR",
        ],
      }
    : {host: name, options: kept}

let port = 37483

/** The driver's command line, and `o` printing the first value of one of its flags. */
let flags = `a=$(systemctl show -p ExecStart --value monoflake-driver) || exit 1
o() { printf '%s\\n' "$a" | grep -o -- "--$1=[^ ;]*" | head -n 1 | cut -d= -f2-; }
`

// The binding's token is `<id>.<secret>`, and only what stands before its dot is printed.
let facts = `${flags}b=$(o bindings) && [ -n "$b" ] || { echo "the driver names no binding" >&2; exit 1; }
echo "directory=$(o local)"
echo "binding=$(head -n 1 "$b" | cut -s -d. -f1)"
echo "tunnel=$(cat /run/monoflake/tunnel/address 2> /dev/null)"
`

type facts = {directory: string, binding: string, tunnel: option<string>}

let readFacts = text => {
  let said =
    text
    ->String.split("\n")
    ->Array.filterMap(line =>
      switch line->String.indexOf("=") {
      | -1 => None
      | at => Some((line->String.slice(~start=0, ~end=at), line->String.slice(~start=at + 1)))
      }
    )
    ->Dict.fromArray
  let given = name => said->Dict.get(name)->Option.map(String.trim)->Option.filter(v => v != "")
  switch (given("directory"), given("binding")) {
  | (None, _) => Error("the driver was started with no --local directory to fetch artifacts from")
  | (_, None) => Error("the binding's token names no id before its dot")
  | (Some(directory), Some(binding)) => Ok({directory, binding, tunnel: given("tunnel")})
  }
}

let call = envelope => {
  let named = key =>
    envelope
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get(key))
    ->Option.flatMap(JSON.Decode.string)
    ->Option.getOr("")
  let (interface, operation) = (named("interface"), named("operation"))
  `${flags}curl -sS -X POST http://localhost:${Int.toString(port)}/${interface}/${operation} \\
  -H "Authorization: Bearer $(tr -d '\\n' < "$(o bindings)")" \\
  -H 'Content-Type: application/json' -H 'Accept: application/json' --data-binary @-
`
}

/** The entry's address, its own unit's `--listen`, RFC rmll5. */
let entered = `e=$(systemctl show -p ExecStart --value monoflake-entry | grep -o -- "--listen=[^ ;]*" | head -n 1 | cut -d= -f2-)
[ -n "$e" ] || { echo "monoflake-entry names no address to listen on" >&2; exit 1; }
`

let asked = host =>
  `${entered}curl -sS -m 10 -H 'Host: ${host}' "http://$e/"
`

type refused = {reason: string, message: string}

let answer = (text, data) =>
  switch JSON.parseOrThrow(text) {
  | exception JsExn(_) => Error({reason: "unread", message: `no JSON answered, ${text}`})
  | json =>
    switch Contracts.Answer.fromJson(json, data) {
    | Ok(Success(output)) => Ok(output)
    | Ok(Error({reason, message})) => Error({reason, message})
    | Error({expected}) =>
      Error({reason: "unread", message: `the answer is not as its type writes it, ${expected}`})
    }
  }
