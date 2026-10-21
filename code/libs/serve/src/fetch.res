type jsRequest = Web.request

type jsResponse = Web.response

let handler = (routes, ~trust) =>
  async request => {
    let headers = request->Web.requestHeaders
    let read: Calls.request = {
      method_: request->Web.requestMethod,
      path: request->Web.requestUrl->Web.pathOf,
      contentType: headers->Web.header("content-type")->Nullable.toOption,
      accept: headers->Web.header("accept")->Nullable.toOption,
      body: await request->Web.bodyOf,
    }
    let response = await Calls.serve(routes, ~trust, read)
    Web.makeResponse(
      response.body,
      {status: response.status, headers: Dict.fromArray([("content-type", response.contentType)])},
    )
  }
