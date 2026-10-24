/***
 * A send made on the machine a deployment runs on, over ssh, RFC p8e8k.
 */

/** What a URL may hold to be put in a shell between single quotes. */
let plain = /^https?:\/\/[A-Za-z0-9._~:\/\[\]-]+$/

let posted = url =>
  plain->RegExp.test(url)
    ? Ok(
        `curl -sS -m 30 -w '\\n%{http_code}' -X POST -H 'Content-Type: application/json' \\
  -H 'Accept: application/json' --data-binary @- '${url}'
`,
      )
    : Error(`${url} holds what no plain URL does`)

/** A newline's byte. */
let newline = 10

let readPosted = bytes => {
  let length = bytes->TypedArray.length
  // What curl writes after the body is its status, so the last newline stands before it.
  let end_ = bytes->TypedArray.get(length - 1) == Some(newline) ? length - 1 : length
  let rec last = at =>
    at < 0 ? None : bytes->TypedArray.get(at) == Some(newline) ? Some(at) : last(at - 1)
  switch last(end_ - 1) {
  | None => Error(`no status printed after ${Web.text(bytes)}`)
  | Some(at) =>
    let status = Web.text(bytes->TypedArray.slice(~start=at + 1, ~end=end_))->String.trim
    switch Int.fromString(status) {
    | Some(n) if Int.toString(n) == status => Ok((n, bytes->TypedArray.slice(~start=0, ~end=at)))
    | Some(_) | None => Error(`no status printed after ${Web.text(bytes)}`)
    }
  }
}

let fault = (message): Envelope.Contracts.Error.t => {failure: Unknown, reason: "fault", message}

// What the runner sends is JSON, so the request's own content type is not put in the shell.
let post = ssh =>
  async (url, request: Host.Handed.request) =>
    switch posted(Http.plainHttp(url)) {
    | Error(why) => Error(fault(why))
    | Ok(shell) =>
      switch await System.piped("ssh", ssh->Array.concat([shell]), request.body) {
      | Error(why) => Error(fault(`ssh: ${why}`))
      | Ok((0, out, _)) =>
        readPosted(out)
        ->Result.map(((status, body)): Host.Handed.response => {status, contentType: None, body})
        ->Result.mapError(fault)
      | Ok((_, _, err)) => Error(fault(Web.text(err)->String.trim))
      }
    }
