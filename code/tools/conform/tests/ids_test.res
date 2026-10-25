/*** `Ids` held to RFC b8f35, an app's id written as 8 lowercase hex digits and read back alone. */
open Node

test("an id is 8 lowercase hex digits, leading zeros kept, and read back to the same bits", () => {
  deepEqual(Ids.text(1), "00000001")
  deepEqual(Ids.text(0x0a1b2c3d), "0a1b2c3d")
  deepEqual(Ids.ofText("0a1b2c3d"), Some(0x0a1b2c3d))
  deepEqual(Ids.ofText("fedcba98")->Option.map(Ids.text), Some("fedcba98"))
  deepEqual(Ids.ofText("fedcba98")->Option.map(Ids.toFloat), Some(4275878552.))
})

test("no other text is an id, a decimal, a prefix, capitals, another width or 0", () =>
  deepEqual(
    ["2", "app-2", "0A1B2C3D", "a1b2c3d", "0a1b2c3d0", "00000000", " 0a1b2c3d"]->Array.map(
      Ids.ofText,
    ),
    [None, None, None, None, None, None, None],
  )
)

test("--app is taken out with its id, and refused where absent or not 8 hex digits", () => {
  deepEqual(
    Ids.app(["local", "--app", "0a1b2c3d", "--dry-run"]),
    Ok((0x0a1b2c3d, ["local", "--dry-run"])),
  )
  ok(Ids.app(["local"])->Result.isError)
  ok(Ids.app(["local", "--app"])->Result.isError)
  ok(Ids.app(["local", "--app", "2"])->Result.isError)
  ok(Ids.app(["local", "--app", "app-2"])->Result.isError)
})
