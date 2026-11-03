type request
type response
type url
@get external method: request => string = "method"
@get external address: request => string = "url"
@new external url: string => url = "URL"
@get external pathname: url => string = "pathname"
type init = {status: int}
@new external response: (string, init) => response = "Response"
