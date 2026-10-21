/**
 * A database's copies, any two majorities of each count sharing a copy, writes taken while a
 * majority lives and the lock released only by configuring fewer. RFC vuanj.
 */
open Base

let run = () => {
  let found = []
  let majority = Database.majority
  let counts = Array.fromInitializer(~length=Database.copiesMost, i => i + 1)
  counts->Array.forEach(n => {
    if 2 * majority(n) <= n {
      found->Array.push(`${int(n)} copies: two majorities of ${int(majority(n))} may share none`)
    }
    if majority(n) > n {
      found->Array.push(`${int(n)} copies: a majority of ${int(majority(n))}, more than there are`)
    }
    Array.fromInitializer(~length=n, alive => alive)->Array.forEach(alive =>
      if alive < majority(n) {
        let released = Database.releasing(alive)
        if alive > 0 && released == [] {
          found->Array.push(
            `${int(n)} copies, ${int(alive)} alive: no configuration releases the lock`,
          )
        }
        released->Array.forEach(
          m =>
            if m >= n {
              found->Array.push(
                `${int(n)} copies, ${int(alive)} alive: released by ${int(
                    m,
                  )}, no fewer than were configured`,
              )
            },
        )
      }
    )
  })
  dimension(
    "Copies",
    "Do any two majorities of a database's copies share one, and is its read-only lock released only by configuring fewer?",
    found,
    ~notes=counts->Array.map(n =>
      `${int(n)}: a write held by ${int(majority(n))}; read-only below, released from ${int(
          majority(n) - 1,
        )} alive by ${Database.releasing(majority(n) - 1)->Array.map(m => int(m))->orNone(" or ")}`
    ),
    (),
  )
}
