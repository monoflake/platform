module Stopping = Lose.Stopping

type action = {name: string, shell: string}

/** A unit restarted and waited on until systemd holds it active. */
let restarted = unit =>
  `systemctl restart ${unit} || exit 1
for _ in $(seq 50); do systemctl is-active --quiet ${unit} && exit; sleep 0.2; done
echo "${unit} not active within 10 s" >&2; exit 1
`

let restarts = [
  {
    name: `restart ${Stopping.unit}`,
    shell: `systemctl restart ${Stopping.unit} || exit 1
${Stopping.start}`,
  },
  {name: "restart driver-machine-entry", shell: restarted("driver-machine-entry")},
  {name: "restart containerd", shell: restarted("containerd")},
]

let units = ["containerd", "driver-machine-entry.socket", "driver-machine-entry", Stopping.unit]

let each = body =>
  `for u in ${units->Array.join(" ")}; do
  systemctl cat "$u" > /dev/null 2>&1 || continue
  ${body}
done
`

let kept = `${each(`systemctl start "$u" || s=1`)}exit \${s:-0}
`

let states = `${each(`echo "$u $(systemctl is-active "$u")"`)}true
`

let clock = "date +%s%3N\n"

let active = text => {
  let lines = text->String.trim->String.split("\n")->Array.filter(l => l->String.trim != "")
  let down = lines->Array.filter(l => !(l->String.trim->String.endsWith(" active")))
  switch (lines, down) {
  | ([], _) => Error("no unit's state printed")
  | (_, []) => Ok()
  | (_, down) => Error(`not active: ${down->Array.join(", ")}`)
  }
}
