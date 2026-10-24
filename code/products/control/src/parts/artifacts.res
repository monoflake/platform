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

/** Thrown where the store did not answer, as the API answers what throws. */
let held = result =>
  switch result {
  | Ok(value) => value
  | Error(why) => JsError.throwWithMessage(`the objects were not reached, ${why}`)
  }

let ofObjects = (objects: Objects.t) => {
  put: async (hash, bytes) => held(await objects.write(`artifacts/${hash}`, bytes)),
  served: async hash =>
    held(await objects.read(`artifacts/${hash}`))->Option.map(bytes =>
      Web.response(bytes, {status: 200, headers: dict{"content-type": "application/octet-stream"}})
    ),
}
