/***
 * What the storage Worker takes of the Fetch API, requests, responses, a URL's path and a service
 * binding, alike on a Worker and in node.
 */
type request
type response
type headers

@get external url: request => string = "url"
@get external method_: request => string = "method"
@get external requestHeaders: request => headers = "headers"
@send external header: (headers, string) => Nullable.t<string> = "get"
@send external requestText: request => promise<string> = "text"

type requestInit = {method: string, headers: dict<string>, body?: string}
@new external request: (string, requestInit) => request = "Request"

type responseInit = {status: int, headers: dict<string>}
@new external response: (string, responseInit) => response = "Response"
@new external bytesResponse: (Uint8Array.t, responseInit) => response = "Response"
@new external emptyResponse: (Null.t<string>, responseInit) => response = "Response"
@get external status: response => int = "status"
@get external responseHeaders: response => headers = "headers"
@send external text: response => promise<string> = "text"

/** JSON written as a response of the status given. */
let json = (~status, value) =>
  response(JSON.stringify(value), {status, headers: dict{"content-type": "application/json"}})

/** What sends a request and gives its response. */
type fetch = request => promise<response>

/** A service binding, every name read on it present, so an option of it is never unwrapped. */
@notUndefined
type fetcher
@send external fetchThrough: (fetcher, request) => promise<response> = "fetch"

type parts
@new external parts: string => parts = "URL"
@get external pathname: parts => string = "pathname"
