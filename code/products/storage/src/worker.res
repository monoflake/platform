open Envelope

type request = Web.request
type response = Web.response
type fetcher = Web.fetcher
type env = {
  @as("SOCKET") socket?: string,
  @as("SALT") salt?: string,
  @as("OBJECT") objects?: fetcher,
}

/** An error answer of a reason the contracts name, its message their default unless given. */
let refused = (name, ~message=?) => {
  let failure =
    Contracts.reasons
    ->Array.find(reason => reason.name == name)
    ->Option.mapOr(Contracts.Failure.Rejected, reason => reason.failure)
  Contracts.Answer.Error({
    failure,
    reason: name,
    message: message->Option.getOr(Contracts.messages->Dict.get(name)->Option.getOr(name)),
  })
}

let fault = () => refused("fault")
let errorJson = answer => Contracts.Answer.toJson(answer, _ => JSON.Null)

let asked = async (fetcher, operation, input, fromJson) =>
  try {
    let answer = await fetcher->Web.fetchThrough(
      Web.request(
        `http://object/object/${operation}`,
        {
          method: "POST",
          headers: dict{"content-type": "application/json"},
          // The envelope's call form, as every driver call is sent.
          body: JSON.stringify(
            JSON.Object(
              dict{
                "interface": JSON.String("object"),
                "operation": JSON.String(operation),
                "input": input,
              },
            ),
          ),
        },
      ),
    )
    switch Contracts.Answer.fromJson(JSON.parseOrThrow(await answer->Web.text), fromJson) {
    | Ok(answer) => answer
    | Error(_) => fault()
    }
  } catch {
  | _ => fault()
  }

let objects = (fetcher): Operations.objects => {
  write: input =>
    asked(fetcher, "write", Contracts.ObjectWrite.toJson(input), Contracts.ObjectWritten.fromJson),
  read: input =>
    asked(fetcher, "read", Contracts.ObjectRead.toJson(input), Contracts.ObjectContent.fromJson),
  describe: input =>
    asked(
      fetcher,
      "describe",
      Contracts.ObjectName.toJson(input),
      Contracts.ObjectDescribed.fromJson,
    ),
  delete: input =>
    asked(fetcher, "delete", Contracts.ObjectName.toJson(input), Contracts.ObjectDeleted.fromJson),
  list: input =>
    asked(fetcher, "list", Contracts.ObjectList.toJson(input), Contracts.ObjectListed.fromJson),
}

let salt = text => String.length(text) == 64 ? Hex.decode(text) : None

let ran = async (input, fromJson, run, toJson) =>
  switch fromJson(input) {
  | Error(_) => errorJson(refused("malformed"))
  | Ok(read) =>
    try Contracts.Answer.toJson(await run(read), toJson) catch {
    | _ => errorJson(fault())
    }
  }

let call = (context, ~operation, input) =>
  switch operation {
  | "object_write" =>
    ran(
      input,
      Contracts.BucketObjectWrite.fromJson,
      Operations.write(context, ...),
      Contracts.BucketObject.toJson,
    )
  | "object_read" =>
    ran(
      input,
      Contracts.BucketObjectRead.fromJson,
      Operations.read(context, ...),
      Contracts.ObjectContent.toJson,
    )
  | "object_describe" =>
    ran(
      input,
      Contracts.BucketObjectName.fromJson,
      Operations.describe(context, ...),
      Contracts.ObjectDescribed.toJson,
    )
  | "object_delete" =>
    ran(
      input,
      Contracts.BucketObjectName.fromJson,
      Operations.delete(context, ...),
      Contracts.ObjectDeleted.toJson,
    )
  | "object_list" =>
    ran(
      input,
      Contracts.BucketObjectList.fromJson,
      Operations.list(context, ...),
      Contracts.BucketObjectListed.toJson,
    )
  | _ =>
    Promise.resolve(
      errorJson(refused("malformed", ~message=`The storage has no operation named ${operation}`)),
    )
  }

let forbidden = message =>
  Web.json(
    ~status=403,
    errorJson(Contracts.Answer.Error({failure: Rejected, reason: "forbidden", message})),
  )

let callerPattern = /^[0-9a-f]{8}$/

/** The operation a path calls, none where it is not `/storage/{operation}`. */
let operationOf = path =>
  switch path->String.split("/") {
  | ["", "storage", operation] if operation != "" => Some(operation)
  | _ => None
  }

let called = path => path == "/storage" || path->String.startsWith("/storage/")

let fetch = async (request, env) => {
  let path = Web.parts(request->Web.url)->Web.pathname
  switch (env.socket, env.salt->Option.flatMap(salt), env.objects) {
  | (Some("data"), Some(salt), Some(fetcher)) =>
    let caller = request->Web.requestHeaders->Web.header("caller")->Nullable.toOption
    switch (request->Web.method_, operationOf(path), caller) {
    | ("POST", Some(operation), Some(caller)) if callerPattern->RegExp.test(caller) =>
      let input = try Some(JSON.parseOrThrow(await request->Web.requestText)) catch {
      | _ => None
      }
      let answer = switch input {
      | Some(input) => await call({salt, objects: objects(fetcher)}, ~operation, input)
      | None => errorJson(refused("malformed"))
      }
      Web.json(~status=200, answer)
    | _ => forbidden("Only a call carrying Caller is taken on the data socket")
    }
  | (Some("public"), Some(salt), Some(fetcher)) =>
    called(path)
      ? forbidden("A call is never taken on the public socket")
      : await Serving.fetch({salt, objects: objects(fetcher)}, request)
  | _ => Web.json(~status=500, errorJson(fault()))
  }
}

type worker = {fetch: (request, env) => promise<response>}
let default: worker = {fetch: fetch}
