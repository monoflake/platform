/***
 * `Actions` held to restarting each unit in order and reading every unit's state.
 */
open Node

test("the driver, the entry and containerd are restarted in turn, each waited on", () => {
  deepEqual(
    Actions.restarts->Array.map(a => a.name),
    ["restart monoflake-driver", "restart monoflake-entry", "restart containerd"],
  )
  Actions.restarts->Array.forEach(a => ok(a.shell->String.includes("systemctl restart ")))
  ok((Actions.restarts->Array.getUnsafe(0)).shell->String.includes("= 403 ]"))
})

test("every unit is started where the machine has it, the entry's socket among them", () => {
  ok(Actions.units->Array.includes("monoflake-entry.socket"))
  ok(Actions.kept->String.includes(`systemctl start "$u"`))
  ok(Actions.kept->String.includes(`systemctl cat "$u"`))
})

test("every unit printed active is held, and one that is not named", () => {
  deepEqual(Actions.active("containerd active\nmonoflake-entry active\n"), Ok())
  deepEqual(
    Actions.active("containerd active\nmonoflake-entry inactive\n"),
    Error("not active: monoflake-entry inactive"),
  )
  ok(Actions.active("")->Result.isError)
})
