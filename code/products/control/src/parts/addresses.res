/*** The private addresses a binding's host is reached at, the lowest free of `10.200.0.0/16`. */

/** The address of the `n`th host in `10.200.0.0/16`, from 1. */
let nth = n => `10.200.${Int.toString(n / 256)}.${Int.toString(mod(n, 256))}`

/** How many addresses the range holds, its first passed over as no binding's id gave it. */
let count = 65535

/** The lowest address of the range none of `held` is, none where every one is. */
let lowest = held => {
  let taken = Set.fromArray(held)
  let rec find = n =>
    if n > count {
      None
    } else if taken->Set.has(nth(n)) {
      find(n + 1)
    } else {
      Some(nth(n))
    }
  find(1)
}
