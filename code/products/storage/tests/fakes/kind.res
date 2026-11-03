/***
 * The `object` kind faked behind a service binding, its names held in memory, each request it is
 * sent kept, and its answer replaced by any text where a test asks.
 */
module Contracts = Envelope.Contracts

type sent = {url: string, method: string, contentType: option<string>, body: JSON.t}

type t = {
  fetcher: Worker.fetcher,
  held: dict<Uint8Array.t>,
  sent: array<sent>,
  /** A status and text every request is answered with in place of the kind's answer. */
  replaced: ref<option<(int, string)>>,
}

let asFetcher = Casts.asFetcher
let asRequest = Casts.asRequest
let ofResponse = Casts.ofResponse

let notFound = Contracts.Answer.Error({
  failure: Rejected,
  reason: "not_found",
  message: "Nothing of that name or id exists",
})

let answered = (read, input, run, toJson) =>
  switch read(input) {
  | Ok(input) => Contracts.Answer.toJson(run(input), toJson)
  | Error(_) =>
    Contracts.Answer.toJson(
      Contracts.Answer.Error({failure: Rejected, reason: "malformed", message: "malformed"}),
      _ => JSON.Null,
    )
  }

let make = (): t => {
  let held = dict{}
  let sent = []
  let replaced = ref(None)
  let size = bytes => Int.toFloat(TypedArray.length(bytes))
  let answer = (operation, body) =>
    switch operation {
    | "write" =>
      answered(
        Contracts.ObjectWrite.fromJson,
        body,
        (input: Contracts.ObjectWrite.t) => {
          held->Dict.set(input.name, input.content)
          Contracts.Answer.Success(({}: Contracts.ObjectWritten.t))
        },
        Contracts.ObjectWritten.toJson,
      )
    | "read" =>
      answered(
        Contracts.ObjectRead.fromJson,
        body,
        (input: Contracts.ObjectRead.t) =>
          switch held->Dict.get(input.name) {
          | Some(content) =>
            Contracts.Answer.Success({Contracts.ObjectContent.content, size: size(content)})
          | None => notFound
          },
        Contracts.ObjectContent.toJson,
      )
    | "describe" =>
      answered(
        Contracts.ObjectName.fromJson,
        body,
        (input: Contracts.ObjectName.t) => Contracts.Answer.Success(
          ({size: ?(held->Dict.get(input.name)->Option.map(size))}: Contracts.ObjectDescribed.t),
        ),
        Contracts.ObjectDescribed.toJson,
      )
    | "delete" =>
      answered(
        Contracts.ObjectName.fromJson,
        body,
        (input: Contracts.ObjectName.t) => {
          held->Dict.delete(input.name)
          Contracts.Answer.Success(({}: Contracts.ObjectDeleted.t))
        },
        Contracts.ObjectDeleted.toJson,
      )
    | _ =>
      answered(
        Contracts.ObjectList.fromJson,
        body,
        (input: Contracts.ObjectList.t) => {
          let after = input.after->Option.getOr("")
          let names =
            held
            ->Dict.keysToArray
            ->Array.filter(name => name->String.startsWith(input.prefix) && name > after)
            ->Array.toSorted(String.compare)
          let limit = input.limit->Option.mapOr(1000, Float.toInt)
          let taken = names->Array.slice(~start=0, ~end=limit)
          Contracts.Answer.Success({
            Contracts.ObjectListed.objects: taken->Array.map(name => {
              Contracts.ObjectListedOne.name,
              size: size(held->Dict.getUnsafe(name)),
            }),
            next: ?(names->Array.length > limit ? taken->Array.at(-1) : None),
          })
        },
        Contracts.ObjectListed.toJson,
      )
    }
  let fetch = async request => {
    let body = JSON.parseOrThrow(await request->Web.requestText)
    let url = request->Web.url
    sent->Array.push({
      url,
      method: request->Web.method_,
      contentType: request->Web.requestHeaders->Web.header("content-type")->Nullable.toOption,
      body,
    })
    switch replaced.contents {
    | Some((status, text)) => Web.response(text, {status, headers: dict{}})
    | None =>
      let operation = url->String.split("/")->Array.at(-1)->Option.getOr("")
      Web.json(~status=200, answer(operation, body))
    }
  }
  {fetcher: asFetcher(fetch), held, sent, replaced}
}
