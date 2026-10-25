/*** `Id` held to RFC b8f35, an id written as 8 lowercase hex digits, read back, and taken. */
open Node

test("an id is 8 lowercase hex digits, leading zeros kept, and read back alone", () => {
  deepEqual(Id.text(1.), "00000001")
  deepEqual(Id.text(169552957.), "0a1b2c3d")
  deepEqual(Id.text(4275878552.), "fedcba98")
  deepEqual(Id.ofText("0a1b2c3d"), Some(169552957.))
  deepEqual(Id.ofText("ffffffff"), Some(4294967295.))
  deepEqual(Id.ofText("fedcba98")->Option.map(Id.text), Some("fedcba98"))
})

test("no other text is an id, a decimal, a prefix, capitals, another width or 0", () =>
  deepEqual(
    [
      "2",
      "app-2",
      "b0a1b2c3d",
      "0A1B2C3D",
      "a1b2c3d",
      "0a1b2c3d0",
      "00000000",
      " 0a1b2c3d",
      "",
    ]->Array.map(Id.ofText),
    [None, None, None, None, None, None, None, None, None],
  )
)

test("4 bytes are read big-endian, in the order the hex digits write them", () => {
  deepEqual(Id.ofBytes(Uint8Array.fromArray([0x0a, 0x1b, 0x2c, 0x3d])), 169552957.)
  deepEqual(Id.ofBytes(Uint8Array.fromArray([0xff, 0xff, 0xff, 0xff])), 4294967295.)
  deepEqual(Id.ofBytes(Uint8Array.fromArray([0, 0, 0, 0])), 0.)
})

test("a flag is taken out with its id, and left none where it is absent", () => {
  deepEqual(
    Id.taken(["local", "--app", "0a1b2c3d", "--dry-run"], ~flag="app"),
    Ok((Some(169552957.), ["local", "--dry-run"])),
  )
  deepEqual(
    Id.taken(["local", "--binding", "00000001"], ~flag="binding"),
    Ok((Some(1.), ["local"])),
  )
  deepEqual(Id.taken(["local", "--dry-run"], ~flag="app"), Ok((None, ["local", "--dry-run"])))
})

test("a flag given no id, one not 8 hex digits or twice, is refused", () => {
  deepEqual(
    Id.taken(["local", "--app"], ~flag="app"),
    Error("--app is given no id, 8 lowercase hex digits"),
  )
  deepEqual(
    Id.taken(["local", "--app", "2"], ~flag="app"),
    Error("--app 2 is no id, 8 lowercase hex digits"),
  )
  ok(Id.taken(["--app", "app-2"], ~flag="app")->Result.isError)
  ok(Id.taken(["--app", "00000000"], ~flag="app")->Result.isError)
  ok(Id.taken(["--app", "0a1b2c3d", "--app", "0a1b2c3e"], ~flag="app")->Result.isError)
})
