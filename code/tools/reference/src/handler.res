let greeting = stamp => `reference ${stamp}\n`

let unreached = (Reach.Unreached(kind)) =>
  Web.response(`no binding reaches ${kind}, RFC dg903's question 3`, {status: 501})

let fetch = (~stamp, request) => {
  let path = request->Web.address->Web.url->Web.pathname
  let method = request->Web.method
  let answer = switch (method, path->String.split("/")) {
  | ("GET", ["", ""]) => Web.response(greeting(stamp), {status: 200})
  | ("PUT" | "GET", ["", "row", key]) if key != "" => unreached(Reach.database())
  | ("PUT" | "GET", ["", "object", name]) if name != "" => unreached(Reach.object())
  | _ => Web.response("not found", {status: 404})
  }
  Promise.resolve(answer)
}
