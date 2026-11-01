/*** `Through` held to RFC oomwh, a gateway's mount asked in place of the machine's tunnel. */
open Node

test("--gateway is taken out with its origin, a trailing slash dropped", () => {
  deepEqual(
    Through.flagged(["local", "--gateway", "http://localhost:8787/", "--dry-run"]),
    Ok((Some("http://localhost:8787"), ["local", "--dry-run"])),
  )
  deepEqual(Through.flagged(["local"]), Ok((None, ["local"])))
  ok(Through.flagged(["local", "--gateway"])->Result.isError)
  ok(Through.flagged(["local", "--gateway", "localhost:8787"])->Result.isError)
  deepEqual(
    Through.flagged(["local", "--gateway", "https://c.example/under/"]),
    Ok((Some("https://c.example/under"), ["local"])),
  )
  ok(Through.flagged(["local", "--gateway", "https://c.example/v1?x=1"])->Result.isError)
})

test("a gateway's mount is asked where one is named, the tunnel otherwise", () => {
  deepEqual(
    Through.chosen(~gateway=Some("https://c.example"), ~tunnel=Ok("https://t.example")),
    Some({name: "gateway", address: "https://c.example/v1/hello/"}),
  )
  deepEqual(
    Through.chosen(~gateway=None, ~tunnel=Ok("https://t.example\n")),
    Some({name: "tunnel", address: "https://t.example"}),
  )
  deepEqual(Through.chosen(~gateway=None, ~tunnel=Ok("")), None)
  deepEqual(Through.chosen(~gateway=None, ~tunnel=Error("no ssh")), None)
})

test("the gateway's address names hello's scope, no app id", () =>
  deepEqual(Through.gateway(~origin="https://c.example"), "https://c.example/v1/hello/")
)
