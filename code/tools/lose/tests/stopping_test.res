/***
 * `Stopping` held to reading a call to the stopped driver as refused at once, or why not.
 */
open Node

test("a connection refused at once is a clean refusal", () => {
  let printed = "curl: (7) Failed to connect to localhost port 37483\n\n000\nexit=7\n"
  deepEqual(Stopping.refused(printed, ~took=150.), Ok("refused in 0.15s"))
  ok(Stopping.refused(printed, ~took=Stopping.quick +. 1.)->Result.isError)
})

test("an answer, a timeout or no status is no clean refusal", () => {
  ok(Stopping.refused("{}\n200\nexit=0", ~took=100.)->Result.isError)
  ok(Stopping.refused("curl: (28) timed out\n000\nexit=28", ~took=10000.)->Result.isError)
  ok(Stopping.refused("nothing", ~took=100.)->Result.isError)
})

test("the shells name the driver's unit and print the exit status last", () => {
  ok(Stopping.stop->String.includes(`systemctl stop ${Stopping.unit}`))
  ok(Stopping.start->String.includes("= 403 ]"))
  ok(Stopping.statused("curl x")->String.includes(`echo "exit=$s"`))
})
