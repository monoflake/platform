module Live = Conform.Live

type outcome = Answered | Refused(string) | Failed(string)

type asked = {began: float, ended: float, outcome: outcome}

let clients = 4

// Each ask a new connection, so a listener closed for a moment is seen as a refusal.
let shell = (~app, ~binding, ~stop) =>
  `${Live.entered}stop='${stop}'; most=$(( $(date +%s) + 1800 ))
ask() {
  while [ ! -e "$stop" ] && [ "$(date +%s)" -lt "$most" ]; do
    b=$(date +%s%3N)
    s=$(curl -s -o /dev/null -m 5 -w '%{http_code}' -H 'Host: ${Ids.Id.text(app)}.b${Ids.Id.text(
      binding,
    )}' "http://$e/"); c=$?
    echo "$1 $b $(date +%s%3N) $c $s"
  done
}
for i in $(seq ${Int.toString(clients)}); do ask "$i" & done
wait; rm -f "$stop"
`

// curl's exit status 7 is a connection refused, 28 a timeout, 52 no reply and 56 a reset.
let curled = (~exit, ~status) =>
  switch exit {
  | 0 if status == "200" => Answered
  | 0 => Failed(`HTTP ${status}`)
  | 7 => Refused("connection refused")
  | 28 => Failed("timed out")
  | 52 => Failed("no reply")
  | 56 => Failed("connection reset")
  | n => Failed(`curl exit ${Int.toString(n)}`)
  }

let read = line =>
  switch line->String.trim->String.split(" ") {
  | [_, began, ended, exit, status] =>
    switch (Float.fromString(began), Float.fromString(ended), Int.fromString(exit)) {
    | (Some(began), Some(ended), Some(exit)) =>
      Some({began, ended, outcome: curled(~exit, ~status)})
    | (None, _, _) | (_, None, _) | (_, _, None) => None
    }
  | _ => None
  }

let fetched = (~status, ~body) =>
  switch Live.greeted({status, body}) {
  | Ok() => Answered
  | Error(why) => Failed(why)
  }

let thrown = (~code, ~message) =>
  switch code {
  | Some("ECONNREFUSED") => Refused("connection refused")
  | Some(code) => Failed(`${message}, ${code}`)
  | None => Failed(message)
  }
