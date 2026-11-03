type request
type response
type headers

@get external url: request => string = "url"
@get external requestHeaders: request => headers = "headers"
@send external header: (headers, string) => Nullable.t<string> = "get"
@send external setHeader: (headers, string, string) => unit = "set"
@send external deleteHeader: (headers, string) => unit = "delete"
@new external resent: (string, request) => request = "Request"
external fetch: request => promise<response> = "fetch"

type responseInit = {status: int}
@new external response: (string, responseInit) => response = "Response"
let answered = (~status, text) => response(text, {status: status})

type parts
@new external parts: string => parts = "URL"
@get external pathname: parts => string = "pathname"
@get external search: parts => string = "search"
