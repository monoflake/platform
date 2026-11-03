type request
type response
type headers

@get external url: request => string = "url"
@get external requestHeaders: request => headers = "headers"
@send external header: (headers, string) => Nullable.t<string> = "get"
@send external setHeader: (headers, string, string) => unit = "set"
@send external deleteHeader: (headers, string) => unit = "delete"
@new external resent: (string, request) => request = "Request"
type requestInit = {method: string, headers: dict<string>, body: string}
@new external request: (string, requestInit) => request = "Request"
external fetch: request => promise<response> = "fetch"

type responseInit = {status: int, headers?: dict<string>}
@new external response: (string, responseInit) => response = "Response"
let answered = (~status, text) => response(text, {status: status})

type parts
@new external parts: string => parts = "URL"
@get external pathname: parts => string = "pathname"
@get external search: parts => string = "search"

@get external method_: request => string = "method"
@send external requestJson: request => promise<JSON.t> = "json"
@get external status: response => int = "status"
@get external responseHeaders: response => headers = "headers"
@send external clone: response => response = "clone"
@send external responseJson: response => promise<JSON.t> = "json"
type body
@get external body: response => body = "body"
@new external copiedResponse: (body, response) => response = "Response"
@val @scope("Date") external now: unit => float = "now"
external setTimeout: (unit => unit, float) => unit = "setTimeout"
let wait = milliseconds => Promise.make((resolve, _) => setTimeout(() => resolve(), milliseconds))

let json = (~status, value) => {
  let answer = answered(~status, JSON.stringify(value))
  answer->responseHeaders->setHeader("content-type", "application/json")
  answer
}

let withCall = (answer, id) => {
  let copy = copiedResponse(answer->body, answer)
  copy->responseHeaders->setHeader("Call", id)
  copy
}
