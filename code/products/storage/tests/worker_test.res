/***
 * The Worker's two sockets, its binding to the `object` kind and what it refuses before any
 * operation runs.
 */
open Node
module Contracts = Envelope.Contracts

let saltText = String.repeat("ab", 32)

let request = (~method="POST", ~headers=dict{}, ~body=?, path) =>
  Kind.asRequest(Web.request(`http://storage${path}`, {method, headers, ?body}))

let caller = dict{"caller": "0000002a"}

let env = (kind: Kind.t): Worker.env => {
  socket: "data",
  salt: saltText,
  objects: kind.fetcher,
}

let fetched = async (request, env) => {
  let response = Kind.ofResponse(await Worker.fetch(request, env))
  let text = await response->Web.text
  (response->Web.status, text)
}

let errorOf = text =>
  switch Contracts.Answer.fromJson(JSON.parseOrThrow(text), _ => Ok()) {
  | Ok(Error({failure, reason})) => Some((failure, reason))
  | Ok(Success()) | Error(_) => None
  }

let succeeded = read =>
  switch read {
  | Ok(Contracts.Answer.Success(data)) => Some(data)
  | Ok(Error(_)) | Error(_) => None
  }

let messageOf = json =>
  switch Contracts.Answer.fromJson(json, _ => Ok()) {
  | Ok(Error({message})) => message
  | Ok(Success()) | Error(_) => ""
  }

testAsync("a salt is 64 lowercase hex read as 32 bytes, and nothing else", async () => {
  deepEqual(Worker.salt(saltText), Some(Uint8Array.fromArray(Array.make(~length=32, 0xab))))
  let refused = [
    "",
    String.repeat("AB", 32),
    String.repeat("ab", 31) ++ "a",
    String.repeat("ab", 33),
    String.repeat("ab", 31) ++ "zz",
  ]
  deepEqual(refused->Array.map(Worker.salt), refused->Array.map(_ => None))
})

let described = answer => Contracts.Answer.toJson(answer, Contracts.ObjectDescribed.toJson)

testAsync("each operation is a POST of its input's JSON to the kind at its path", async () => {
  let kind = Kind.make()
  let objects = Worker.objects(kind.fetcher)
  let bytes = Uint8Array.fromArray([104, 105])
  deepEqual(await objects.write({name: "content/aa", content: bytes}), Success({}))
  deepEqual(
    await objects.read({name: "content/aa"}),
    Success({Contracts.ObjectContent.content: bytes, size: 2.}),
  )
  deepEqual(described(await objects.describe({name: "content/aa"})), described(Success({size: 2.})))
  deepEqual(
    Contracts.Answer.toJson(
      await objects.list({prefix: "content/"}),
      Contracts.ObjectListed.toJson,
    ),
    Contracts.Answer.toJson(
      Success({Contracts.ObjectListed.objects: [{name: "content/aa", size: 2.}]}),
      Contracts.ObjectListed.toJson,
    ),
  )
  deepEqual(await objects.delete({name: "content/aa"}), Success({}))
  deepEqual(described(await objects.describe({name: "content/aa"})), described(Success({})))
  deepEqual(await objects.read({name: "content/aa"}), Kind.notFound)
  deepEqual(
    kind.sent->Array.map(sent => (sent.url, sent.method, sent.contentType)),
    ["write", "read", "describe", "list", "delete", "describe", "read"]->Array.map(operation => (
      `http://object/object/${operation}`,
      "POST",
      Some("application/json"),
    )),
  )
  deepEqual(
    kind.sent->Array.slice(~start=0, ~end=2)->Array.map(sent => sent.body),
    [
      ("write", Contracts.ObjectWrite.toJson({name: "content/aa", content: bytes})),
      ("read", Contracts.ObjectRead.toJson({name: "content/aa"})),
    ]->Array.map(((operation, input)) => JSON.Object(
      dict{
        "interface": JSON.String("object"),
        "operation": JSON.String(operation),
        "input": input,
      },
    )),
  )
})

testAsync("an answer that is not JSON, or not as its type writes it, is a fault", async () => {
  let kind = Kind.make()
  let objects = Worker.objects(kind.fetcher)
  let replies = [
    (200, "not json"),
    (500, ""),
    (200, `{"status":"success","data":{"size":"two"}}`),
    (200, `{"status":"later"}`),
    (200, `{"status":"success","data":{}}`),
  ]
  for i in 0 to replies->Array.length - 1 {
    kind.replaced := replies->Array.get(i)
    switch await objects.read({name: "content/aa"}) {
    | Error({failure, reason}) => deepEqual((failure, reason), (Unknown, "fault"))
    | Success(_) => deepEqual(replies->Array.get(i), None)
    }
  }
  kind.replaced := Some((200, `{"status":"success","data":{}}`))
  deepEqual(described(await objects.describe({name: "content/aa"})), described(Success({})))
})

let context = (kind: Kind.t): Operations.context => {
  salt: Worker.salt(saltText)->Option.getOrThrow,
  objects: Worker.objects(kind.fetcher),
}

testAsync("a name no object operation has, or malformed input, answers malformed", async () => {
  let kind = Kind.make()
  let asked = async (operation, input) =>
    errorOf(JSON.stringify(await Worker.call(context(kind), ~operation, input)))
  let malformed = Some((Contracts.Failure.Rejected, "malformed"))
  let operations = [
    "object_write",
    "object_read",
    "object_describe",
    "object_delete",
    "object_list",
  ]
  for i in 0 to operations->Array.length - 1 {
    let operation = operations->Array.getUnsafe(i)
    deepEqual(await asked(operation, JSON.Null), malformed, ~message=operation)
    deepEqual(await asked(operation, JSON.Object(dict{"bucket": String("one")})), malformed)
  }
  let unnamed = ["file_write", "publish", "", "object_writes"]
  for i in 0 to unnamed->Array.length - 1 {
    let operation = unnamed->Array.getUnsafe(i)
    let answer = await Worker.call(context(kind), ~operation, JSON.Object(dict{}))
    deepEqual(errorOf(JSON.stringify(answer)), malformed, ~message=operation)
    deepEqual(messageOf(answer)->String.includes(`named ${operation}`), true)
  }
  deepEqual(kind.sent, [])
})

testAsync("a Worker missing its socket, salt or kind answers 500 with a fault", async () => {
  let kind = Kind.make()
  let given = env(kind)
  let broken: array<Worker.env> = [
    {...given, socket: ?None},
    {...given, socket: "other"},
    {...given, salt: ?None},
    {...given, salt: String.repeat("AB", 32)},
    {...given, objects: ?None},
    {},
  ]
  for i in 0 to broken->Array.length - 1 {
    let (status, text) = await fetched(
      request(~headers=caller, ~body="{}", "/storage/object_read"),
      broken->Array.getUnsafe(i),
    )
    deepEqual((status, errorOf(text)), (500, Some((Contracts.Failure.Unknown, "fault"))))
  }
})

testAsync("the data socket takes only a POST to an operation carrying its caller", async () => {
  let kind = Kind.make()
  let forbidden = (403, Some((Contracts.Failure.Rejected, "forbidden")))
  let refused = [
    request(~method="GET", ~headers=caller, "/storage/object_read"),
    request(~method="PUT", ~headers=caller, ~body="{}", "/storage/object_read"),
    request(~body="{}", "/storage/object_read"),
    request(~headers=dict{"caller": "0000002A"}, ~body="{}", "/storage/object_read"),
    request(~headers=dict{"caller": "000002a"}, ~body="{}", "/storage/object_read"),
    request(~headers=dict{"caller": "00000002a"}, ~body="{}", "/storage/object_read"),
    request(~headers=caller, ~body="{}", "/storage/"),
    request(~headers=caller, ~body="{}", "/storage"),
    request(~headers=caller, ~body="{}", "/storage/object_read/extra"),
    request(~headers=caller, ~body="{}", "/object/read"),
    request(~headers=caller, ~body="{}", "/"),
  ]
  for i in 0 to refused->Array.length - 1 {
    let (status, text) = await fetched(refused->Array.getUnsafe(i), env(kind))
    deepEqual((status, errorOf(text)), forbidden, ~message=Int.toString(i))
  }
  let malformed = (200, Some((Contracts.Failure.Rejected, "malformed")))
  let unread = [
    request(~headers=caller, ~body="not json", "/storage/object_read"),
    request(~headers=caller, ~body="{}", "/storage/file_read"),
    request(~headers=caller, ~body="{}", "/storage/object_read"),
  ]
  for i in 0 to unread->Array.length - 1 {
    let (status, text) = await fetched(unread->Array.getUnsafe(i), env(kind))
    deepEqual((status, errorOf(text)), malformed, ~message=Int.toString(i))
  }
  deepEqual(kind.sent, [])
})

testAsync("the public socket refuses a call and answers every other path 404", async () => {
  let kind = Kind.make()
  let public = {...env(kind), socket: "public"}
  let calls = [
    request(~headers=caller, ~body="{}", "/storage/object_read"),
    request(~method="GET", "/storage/"),
    request(~method="GET", "/storage"),
  ]
  for i in 0 to calls->Array.length - 1 {
    let (status, text) = await fetched(calls->Array.getUnsafe(i), public)
    deepEqual((status, errorOf(text)), (403, Some((Contracts.Failure.Rejected, "forbidden"))))
  }
  let others = ["/", "/v1/storage/00000001/aa", "/storages/x", "/object/read"]
  for i in 0 to others->Array.length - 1 {
    let (status, text) = await fetched(request(~method="GET", others->Array.getUnsafe(i)), public)
    deepEqual((status, text), (404, "not found"))
  }
  deepEqual(kind.sent, [])
})

testAsync("the default export is the Worker's fetch", async () => {
  let kind = Kind.make()
  let response = Kind.ofResponse(
    await Worker.default.fetch(request(~method="GET", "/"), {...env(kind), socket: "public"}),
  )
  deepEqual(response->Web.status, 404)
})

let bucket = 1.

testAsync("an object written by a call is read, described, listed and deleted", async () => {
  let kind = Kind.make()
  let call = async (operation, input) => await Worker.call(context(kind), ~operation, input)
  let written = await call(
    "object_write",
    Contracts.BucketObjectWrite.toJson({
      bucket,
      content: Uint8Array.fromArray([104, 105]),
      extension: "txt",
    }),
  )
  let object =
    Contracts.Answer.fromJson(written, Contracts.BucketObject.fromJson)
    ->succeeded
    ->Option.getOrThrow
  deepEqual(object.size, 2.)
  let read = await call(
    "object_read",
    Contracts.BucketObjectRead.toJson({bucket, object: object.object}),
  )
  deepEqual(
    Contracts.Answer.fromJson(read, Contracts.ObjectContent.fromJson),
    Ok(Success({content: Uint8Array.fromArray([104, 105]), size: 2.})),
  )
  let named = Contracts.BucketObjectName.toJson({bucket, object: object.object})
  deepEqual(
    Contracts.Answer.fromJson(
      await call("object_describe", named),
      Contracts.ObjectDescribed.fromJson,
    ),
    Ok(Success({size: 2.})),
  )
  deepEqual(
    await call("object_list", Contracts.BucketObjectList.toJson({bucket: bucket})),
    Contracts.Answer.toJson(
      Success({Contracts.BucketObjectListed.objects: [object]}),
      Contracts.BucketObjectListed.toJson,
    ),
  )
  deepEqual(
    Contracts.Answer.fromJson(await call("object_delete", named), Contracts.ObjectDeleted.fromJson),
    Ok(Success({})),
  )
})

testAsync("a call on the data socket is answered 200 with the operation's answer", async () => {
  let kind = Kind.make()
  let body = JSON.stringify(
    Contracts.BucketObjectWrite.toJson({bucket, content: Uint8Array.fromArray([104, 105])}),
  )
  let (status, text) = await fetched(
    request(~headers=caller, ~body, "/storage/object_write"),
    env(kind),
  )
  deepEqual(status, 200)
  deepEqual(
    Contracts.Answer.fromJson(JSON.parseOrThrow(text), Contracts.BucketObject.fromJson)
    ->succeeded
    ->Option.map(object => object.size),
    Some(2.),
  )
})

testAsync(
  "a call's step read from the input reaches the kind on the name's write alone",
  async () => {
    let kind = Kind.make()
    let step: Contracts.CallStep.t = {
      id: "0123456789abcdef",
      sequence: 1.,
      expires: 1767225600000.,
      last: false,
    }
    let written = await Worker.call(
      context(kind),
      ~operation="object_write",
      Contracts.BucketObjectWrite.toJson({
        bucket,
        content: Uint8Array.fromArray([104, 105]),
        call: step,
      }),
    )
    deepEqual(
      Contracts.Answer.fromJson(written, Contracts.BucketObject.fromJson)
      ->succeeded
      ->Option.map(object => object.size),
      Some(2.),
    )
    let steps =
      kind.sent
      ->Array.filter(sent => sent.url == "http://object/object/write")
      ->Array.map(sent =>
        sent.body
        ->JSON.Decode.object
        ->Option.flatMap(call => call->Dict.get("input"))
        ->Option.flatMap(
          input =>
            switch Contracts.ObjectWrite.fromJson(input) {
            | Ok(input) => input.call
            | Error(_) => None
            },
        )
      )
    deepEqual(steps, [None, Some(step)])
  },
)
