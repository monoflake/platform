let unit = "driver-machine"

let stop = `systemctl stop ${unit} && ! systemctl is-active --quiet ${unit}
`

/** driver-machine's port on the machine, as driver's `dev` asks it. */
let port = 37483

let start = `systemctl start ${unit} || exit 1
for _ in $(seq 100); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:${Int.toString(
    port,
  )}/management/describe)" = 403 ] && exit
  sleep 0.2
done
echo "${unit} did not answer within 20 s" >&2; exit 1
`

let state = `systemctl is-active ${unit} || true
`

let statused = shell =>
  `( ${shell} ) 2>&1; s=$?; echo; echo "exit=$s"
`

let quick = 3000.

// curl's exit status 7 is a connection refused, 28 a timeout.
let refused = (text, ~took) => {
  let lines = text->String.trimEnd->String.split("\n")
  let said = lines->Array.slice(~start=0, ~end=lines->Array.length - 1)->Array.join(" ")
  let seconds = (took /. 1000.)->Float.toFixed(~digits=2)
  switch lines->Array.at(-1)->Option.map(String.trim) {
  | Some("exit=7") if took <= quick => Ok(`refused in ${seconds}s`)
  | Some("exit=7") => Error(`refused, but only after ${seconds}s`)
  | Some("exit=0") => Error(`answered while the driver is stopped, ${said}`)
  | Some("exit=28") => Error(`no answer until curl gave up after ${seconds}s`)
  | Some(last) if last->String.startsWith("exit=") => Error(`${last}, ${said}`)
  | _ => Error(`no exit status printed, ${text->String.trim}`)
  }
}
