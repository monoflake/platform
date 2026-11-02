/** The SQL inventory refuses a new statement before any fixture reaches it. */
open Testing

test("the control SQL budget holds even while its block is in work", () => {
  deepEqual(Cost_runner.run(), 0)
})

test("an added state statement has no budget", () => {
  deepEqual(
    Sql_cost.missing("let added = \"SELECT id FROM binding WHERE secret = ?\""),
    ["SELECT id FROM binding WHERE secret = ?"],
  )
  deepEqual(
    Sql_cost.missing("let added = \"select id from binding where secret = ?\""),
    ["select id from binding where secret = ?"],
  )
})
