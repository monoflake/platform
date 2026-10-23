type t = {name: string, address: string}

/** An origin, its scheme and its authority alone. */
let origin = /^https?:\/\/[^\/?#]+$/

let control = args =>
  switch args->Array.indexOf("--control") {
  | -1 => Ok((None, args))
  | at =>
    let rest = args->Array.filterWithIndex((_, i) => i != at && i != at + 1)
    switch args->Array.get(at + 1) {
    | Some(given) =>
      let trimmed = given->String.endsWith("/") ? given->String.slice(~start=0, ~end=-1) : given
      origin->RegExp.test(trimmed)
        ? Ok((Some(trimmed), rest))
        : Error(`--control ${given} is no control's origin, http or https and no path`)
    | None => Error("--control names no control's origin")
    }
  }

let gateway = (~origin, ~app) => `${origin}/v1/app-${Int.toString(app)}/`

let chosen = (~control, ~tunnel, ~app) =>
  switch (control, tunnel->Result.map(String.trim)) {
  | (Some(origin), _) => Some({name: "gateway", address: gateway(~origin, ~app)})
  | (None, Ok("") | Error(_)) => None
  | (None, Ok(address)) => Some({name: "tunnel", address})
  }
