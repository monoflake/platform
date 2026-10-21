/***
 * A version, RFC wnqvu, the frozen core, a reader's range and what is written among them, as
 * `src/version.rs` is in Rust.
 */

let max = 9007199254740991.

type t = float

let make = number =>
  number >= 0. && number <= max && Math.floor(number) == number ? Some(number) : None

type range = {lowest: t, highest: t}

let range = (lowest, highest) => lowest <= highest ? Some({lowest, highest}) : None

type refused =
  | Older({version: t, range: range})
  | Newer({version: t, range: range})

let reads = (range, version) =>
  if version < range.lowest {
    Error(Older({version, range}))
  } else if version > range.highest {
    Error(Newer({version, range}))
  } else {
    Ok()
  }

type unchosen =
  | Empty
  | Apart({highest: t, above: array<int>})

let written = ranges =>
  switch ranges->Array.reduce(None, (lowest, r) =>
    switch lowest {
    | Some(highest) if highest <= r.highest => lowest
    | Some(_) | None => Some(r.highest)
    }
  ) {
  | None => Error(Empty)
  | Some(highest) =>
    switch ranges
    ->Array.mapWithIndex((r, at) => r.lowest > highest ? Some(at) : None)
    ->Array.keepSome {
    | [] => Ok(highest)
    | above => Error(Apart({highest, above}))
    }
  }
