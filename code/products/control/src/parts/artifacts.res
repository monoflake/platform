type t = {
  put: (string, Uint8Array.t) => promise<unit>,
  served: string => promise<option<Web.response>>,
}

let ofBucket = bucket => {
  put: (hash, bytes) => bucket->Stores.put(hash, bytes),
  served: async hash =>
    (await bucket->Stores.get(hash))
    ->Nullable.toOption
    ->Option.map(held =>
      Web.streamed(
        held.body,
        {
          status: 200,
          headers: dict{
            "content-type": "application/octet-stream",
            "content-length": Float.toString(held.size),
          },
        },
      )
    ),
}
