/*** Compatibility held to the table monoflake/platform's overlap.tla exports, RFC w0w82. */
open Node

type row = {
  control: int,
  lowest: int,
  @as("driver_lowest") driverLowest: int,
  @as("driver_highest") driverHighest: int,
  overlaps: bool,
}
external rowsOf: JSON.t => array<row> = "%identity"

let rows = () => readText(fromRoot("model/protocol/overlap-table.json"))->JSON.parseOrThrow->rowsOf

let range = (lowest, highest) => JSON.Object(
  dict{"lowest": JSON.Number(Int.toFloat(lowest)), "highest": JSON.Number(Int.toFloat(highest))},
)

test("control's lowest read is the specification's at every version", async () => {
  rows()->Array.forEach(row =>
    deepEqual((row.control, Compatibility.lowestRead(row.control)), (row.control, row.lowest))
  )
})

test(
  "control refuses a driver's range exactly where the specification says it does not overlap",
  async () => {
    Compatibility.supported->Array.forEach(((name, current)) => {
      let held = rows()->Array.filter(row => row.control == current)
      ok(
        held->Array.length > 0,
        ~message=`the table holds no row for ${name} at ${Int.toString(current)}`,
      )
      held->Array.forEach(
        row => {
          let reported = Compatibility.supported->Array.reduce(
            dict{},
            (all, (other, version)) => {
              all->Dict.set(other, range(version, version))
              all
            },
          )
          reported->Dict.set(name, range(row.driverLowest, row.driverHighest))
          let answer = Compatibility.check(
            JSON.Object(dict{"versions": JSON.Object(reported)}),
            ~driver="table",
            ~warn=_ => ok(false),
          )
          deepEqual((name, row, answer->Result.isOk), (name, row, row.overlaps))
        },
      )
    })
  },
)
