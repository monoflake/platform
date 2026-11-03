open Node

test("the plain Worker answers the fixed text and supplied build stamp", async () => {
  let answer = await Handler.fetch(
    ~stamp="build",
    request("https://reference.invalid/", {method: "GET"}),
  )
  equal(status(answer), 200)
  equal(await text(answer), "reference build\n")
})

["GET", "PUT"]->Array.forEach(method =>
  ["row", "object"]->Array.forEach(kind =>
    test(
      `${method} ${kind} fails with the undecided reach and never holds data`,
      async () => {
        let answer = await Handler.fetch(
          ~stamp="build",
          request(`https://reference.invalid/${kind}/key`, {method: method}),
        )
        equal(status(answer), 501)
        let binding = kind == "row" ? "database" : "object"
        equal(await text(answer), `no binding reaches ${binding}, RFC dg903's question 3`)
      },
    )
  )
)

test("unknown routes and methods answer 404", async () => {
  (
    await Promise.all(
      ["/row/", "/object/", "/row/key/extra", "/missing"]->Array.map(async path => {
        let answer = await Handler.fetch(
          ~stamp="build",
          request(`https://reference.invalid${path}`, {method: "GET"}),
        )
        equal(status(answer), 404)
      }),
    )
  )->ignore
  let answer = await Handler.fetch(
    ~stamp="build",
    request("https://reference.invalid/row/key", {method: "DELETE"}),
  )
  equal(status(answer), 404)
})
