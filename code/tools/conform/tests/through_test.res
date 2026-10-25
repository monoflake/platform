/*** `Through` held to RFC rxmd9, a control's gateway asked in place of the machine's tunnel. */
open Node

test("--control is taken out with its origin, a trailing slash dropped", () => {
  deepEqual(
    Through.control(["local", "--control", "http://localhost:8787/", "--dry-run"]),
    Ok((Some("http://localhost:8787"), ["local", "--dry-run"])),
  )
  deepEqual(Through.control(["local"]), Ok((None, ["local"])))
  ok(Through.control(["local", "--control"])->Result.isError)
  ok(Through.control(["local", "--control", "localhost:8787"])->Result.isError)
  deepEqual(
    Through.control(["local", "--control", "https://c.example/v1/00000002/"]),
    Ok((Some("https://c.example/v1/00000002"), ["local"])),
  )
  ok(Through.control(["local", "--control", "https://c.example/v1?x=1"])->Result.isError)
})

test("a control's gateway is asked where one is named, the tunnel otherwise", () => {
  deepEqual(
    Through.chosen(~control=Some("https://c.example"), ~tunnel=Ok("https://t.example"), ~app=1.),
    Some({name: "gateway", address: "https://c.example/v1/00000001/"}),
  )
  deepEqual(
    Through.chosen(~control=None, ~tunnel=Ok("https://t.example\n"), ~app=1.),
    Some({name: "tunnel", address: "https://t.example"}),
  )
  deepEqual(Through.chosen(~control=None, ~tunnel=Ok(""), ~app=1.), None)
  deepEqual(Through.chosen(~control=None, ~tunnel=Error("no ssh"), ~app=1.), None)
})

test("the gateway's address names the app in 8 hex digits, every bit of 32 kept", () => {
  let app = 4275878552.
  deepEqual(Through.gateway(~origin="https://c.example", ~app), "https://c.example/v1/fedcba98/")
})
