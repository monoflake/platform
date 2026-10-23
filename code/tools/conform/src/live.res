module Contracts = Envelope.Contracts

type answered = {status: int, body: string}

/** The live driver's command line, `o` printing one of its flags, and `t` its binding's token. */
let flags = `a=$(systemctl show -p ExecStart --value monoflake-driver) || exit 1
o() { printf '%s\\n' "$a" | grep -o -- "--$1=[^ ;]*" | head -n 1 | cut -d= -f2-; }
t() { tr -d '\\n' < "$(o bindings)"; }
l=$(o listen); l=\${l:-localhost:37483}
`

/** A call to the live driver's path, its body the call of an interface's describe. */
let posted = (
  ~interface,
  ~token,
  ~body=`{"interface": "${interface}", "operation": "describe", "input": {}}`,
) =>
  `${flags}curl -sS -m 10 -w '\\n%{http_code}' -X POST "http://$l/${interface}/describe" \\
  ${token
      ? `-H "Authorization: Bearer $(t)" `
      : ""}-H 'Content-Type: application/json' -H 'Accept: application/json' \\
  --data '${body}'
`

let described = posted(~interface="management", ~token=true)
let untokened = posted(~interface="management", ~token=false)
let unknown = posted(~interface="nothing", ~token=true)

let deployment = (~app) =>
  posted(
    ~interface="deployments",
    ~token=true,
    ~body=Contracts.Interface.Deployments.toJson({
      call: Describe({runs: App({id: Int.toFloat(app)})}),
      capabilities: [],
    })->JSON.stringify,
  )

let binding = `${flags}head -n 1 "$(o bindings)" | cut -s -d. -f1
`

/** The entry's address, its own unit's `--listen`, RFC rmll5. */
let entered = `e=$(systemctl show -p ExecStart --value monoflake-entry | grep -o -- "--listen=[^ ;]*" | head -n 1 | cut -d= -f2-)
[ -n "$e" ] || { echo "monoflake-entry names no address to listen on" >&2; exit 1; }
`

let hello = (~app, ~binding) =>
  `${entered}curl -sS -m 10 -w '\\n%{http_code}' -H 'Host: app-${Int.toString(app)}.b${Int.toString(
      binding,
    )}' "http://$e/"
`

let tunnel = "cat /run/monoflake/tunnel/address 2> /dev/null || true\n"

let readAnswered = text => {
  let text = text->String.trimEnd
  switch text->String.lastIndexOf("\n") {
  | -1 => Error(`no status printed after ${text}`)
  | at =>
    switch Int.fromString(text->String.slice(~start=at + 1)->String.trim) {
    | Some(status) => Ok({status, body: text->String.slice(~start=0, ~end=at)})
    | None => Error(`no status printed after ${text}`)
    }
  }
}

let parsed = body =>
  try Ok(JSON.parseOrThrow(body)) catch {
  | JsExn(_) => Error(`no JSON answered, ${body}`)
  }

let list = ({status, body}) =>
  parsed(body)->Result.flatMap(json =>
    switch Contracts.Answer.fromJson(json, Contracts.ManagementDescribed.fromJson) {
    | Ok(Success(list)) if status == 200 => Ok(list)
    | Ok(Success(_)) => Error(`HTTP ${Int.toString(status)} beside a list`)
    | Ok(Error({reason, message})) => Error(`${reason}: ${message}`)
    | Error({expected}) => Error(`the answer is not as the contract writes a list, ${expected}`)
    }
  )

/** The reason and message of an answer that is an error, or why it is none. */
let error = body =>
  parsed(body)->Result.flatMap(json =>
    switch Contracts.Answer.fromJson(json, data => Ok(data)) {
    | Ok(Error({reason, message})) => Ok((reason, message))
    | Ok(Success(_)) => Error(`a success answered, ${body}`)
    | Error({expected}) => Error(`the answer is not as the contract writes one, ${expected}`)
    }
  )

let denied = ({status, body}) =>
  error(body)->Result.flatMap(((reason, _)) =>
    status == 403 && reason == "denied"
      ? Ok()
      : Error(`HTTP ${Int.toString(status)} and ${reason}, not 403 and denied`)
  )

let refused = ({status, body}) =>
  error(body)->Result.flatMap(((reason, message)) =>
    status == 400 && reason == "malformed" && message->String.includes("no interface nothing")
      ? Ok()
      : Error(`HTTP ${Int.toString(status)} and ${reason}, ${message}`)
  )

let greeted = ({status, body}) =>
  status == 200 && body->String.toLowerCase->String.includes("hello")
    ? Ok()
    : Error(`HTTP ${Int.toString(status)}, ${body->String.slice(~start=0, ~end=200)}`)
