open Envelope

@new external bytesResponse: (Uint8Array.t, Web.responseInit) => Web.response = "Response"
@new external emptyResponse: (Null.t<string>, Web.responseInit) => Web.response = "Response"

let bucketPattern = /^[0-9a-f]{8}$/

let answered = (status, message) =>
  Web.response(message, {status, headers: dict{"content-type": "text/plain"}})

/** The bucket and object a path names, none for any other spelling. */
let addressed = path =>
  switch path->String.split("/") {
  | ["", "v1", "storage", bucket, object] if bucketPattern->RegExp.test(bucket) =>
    switch Names.parse(object) {
    | Some({hash, extension}) if Names.object(~hash, ~extension) == object =>
      Some((Float.parseInt(bucket, ~radix=16), object, hash, extension))
    | _ => None
    }
  | _ => None
  }

let matched = (header, etag) =>
  switch header {
  | None => false
  | Some(value) =>
    value
    ->String.split(",")
    ->Array.some(candidate => {
      let candidate = candidate->String.trim
      candidate == etag || candidate == "*"
    })
  }

let fetch = async (context: Operations.context, request) => {
  let path = Web.parts(request->Web.url)->Web.pathname
  switch addressed(path) {
  | None => answered(404, "not found")
  | Some((bucket, object, hash, extension)) =>
    let method = request->Web.method_
    if method != "GET" && method != "HEAD" {
      Web.response(
        "method not allowed",
        {status: 405, headers: dict{"content-type": "text/plain", "allow": "GET, HEAD"}},
      )
    } else {
      switch await Operations.read(context, {bucket, object}) {
      | Contracts.Answer.Error({reason: "not_found"}) => answered(404, "not found")
      | Error({reason: "unavailable"}) => answered(503, "unavailable")
      | Error(_) => answered(500, "fault")
      | Success({content, size}) =>
        let etag = `"${Hex.encode(hash)}"`
        let cache = "public, max-age=31536000, immutable"
        let none = request->Web.requestHeaders->Web.header("if-none-match")->Nullable.toOption
        if matched(none, etag) {
          emptyResponse(
            Null.null,
            {status: 304, headers: dict{"etag": etag, "cache-control": cache}},
          )
        } else {
          let mediaType = Names.mediaType(extension)
          let headers = dict{
            "content-type": mediaType,
            "content-length": Float.toString(size),
            "etag": etag,
            "cache-control": cache,
            "x-content-type-options": "nosniff",
            "access-control-allow-origin": "*",
          }
          if mediaType != "application/pdf" {
            headers->Dict.set("content-security-policy", "sandbox")
          }
          method == "HEAD"
            ? emptyResponse(Null.null, {status: 200, headers})
            : bytesResponse(content, {status: 200, headers})
        }
      }
    }
  }
}
