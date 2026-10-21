/***
 * Features, RFC wnqvu: what a version cannot say, held by both sides. `src/features.rs` is the same
 * in Rust.
 */

type t = {has: array<string>, needs: array<string>}

type malformed =
  | Name(string)
  | Unheld(string)

/** Whether a name is one: not empty, and lowercase ASCII letters, digits and hyphens alone. */
let named = name => /^[a-z0-9-]+$/->RegExp.test(name)

/** The names sorted, each once. */
let sorted = names => {
  let names = names->Array.toSorted(String.compare)
  names->Array.filterWithIndex((name, at) => at == 0 || names->Array.get(at - 1) != Some(name))
}

let make = (~has, ~needs) =>
  switch has->Array.findMap(name => named(name) ? None : Some(Name(name))) {
  | Some(malformed) => Error(malformed)
  | None =>
    switch needs->Array.findMap(name =>
      if !named(name) {
        Some(Name(name))
      } else if !(has->Array.includes(name)) {
        Some(Unheld(name))
      } else {
        None
      }
    ) {
    | Some(malformed) => Error(malformed)
    | None => Ok({has: sorted(has), needs: sorted(needs)})
    }
  }

type missing = {first: array<string>, second: array<string>}

/** What `needs` holds that `has` does not, in the order of `needs`. */
let lacked = (needs, has) => needs->Array.filter(name => !(has->Array.includes(name)))

let agreed = (first, second) =>
  switch (lacked(first.needs, second.has), lacked(second.needs, first.has)) {
  | ([], []) => Ok(first.has->Array.filter(name => second.has->Array.includes(name)))
  | (inFirst, inSecond) => Error({first: inFirst, second: inSecond})
  }
