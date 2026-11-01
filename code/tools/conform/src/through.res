type t = {name: string, address: string}

/** A gateway's address, its scheme, its authority and a path where it stands beneath one. */
let origin = /^https?:\/\/[^\/?#]+(\/[^?#]*)?$/

let flagged = args =>
  switch args->Array.indexOf("--gateway") {
  | -1 => Ok((None, args))
  | at =>
    let rest = args->Array.filterWithIndex((_, i) => i != at && i != at + 1)
    switch args->Array.get(at + 1) {
    | Some(given) =>
      let trimmed = given->String.endsWith("/") ? given->String.slice(~start=0, ~end=-1) : given
      origin->RegExp.test(trimmed)
        ? Ok((Some(trimmed), rest))
        : Error(`--gateway ${given} is no gateway's address, http or https with no query`)
    | None => Error("--gateway names no gateway's origin")
    }
  }

let scope = "hello"

let gateway = (~origin) => `${origin}/v1/${scope}/`

let chosen = (~gateway as named, ~tunnel) =>
  switch (named, tunnel->Result.map(String.trim)) {
  | (Some(origin), _) => Some({name: "gateway", address: gateway(~origin)})
  | (None, Ok("") | Error(_)) => None
  | (None, Ok(address)) => Some({name: "tunnel", address})
  }
