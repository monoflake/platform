/***
 * The stores Lookup asks, faked, the database's status socket and the storage service binding,
 * each answering one way and keeping what it was asked.
 */
type answer = Steps(array<int>, bool) | NotFound | Forgotten | Refused

type t = {
  database: Worker.database,
  storage: Worker.service,
  ids: array<string>,
  asked: array<Worker.request>,
}

let stepsJson = (committed, finished) => JSON.Object(
  dict{
    "committed": JSON.Array(committed->Array.map(sequence => JSON.Number(Int.toFloat(sequence)))),
    "expires": JSON.Number(253402300799000.),
    "finished": JSON.Boolean(finished),
  },
)

let refusal = reason => JSON.Object(
  dict{
    "status": JSON.String("error"),
    "failure": JSON.String("rejected"),
    "reason": JSON.String(reason),
    "message": JSON.String("The store's status message"),
  },
)

let make = (~database, ~storage) => {
  let ids = []
  let asked = []
  let status = async id => {
    ids->Array.push(id)
    switch database {
    | Steps(committed, finished) => stepsJson(committed, finished)
    | NotFound => JsError.throwWithMessage("not_found: no call of that id")
    | Forgotten => JsError.throwWithMessage("forgotten: the call is past retention")
    | Refused => JsError.throwWithMessage("unavailable: the database is down")
    }
  }
  let fetch = async request => {
    asked->Array.push(request)
    let answer = switch storage {
    | Steps(committed, finished) =>
      JSON.Object(dict{"status": JSON.String("success"), "data": stepsJson(committed, finished)})
    | NotFound => refusal("not_found")
    | Forgotten => refusal("forgotten")
    | Refused => JsError.throwWithMessage("storage unavailable")
    }
    Node.response(
      JSON.stringify(answer),
      {status: 200, headers: dict{"content-type": "application/json"}},
    )
  }
  {database: {status: status}, storage: {fetch: fetch}, ids, asked}
}
