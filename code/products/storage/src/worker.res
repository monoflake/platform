type request
type response
type fetcher
type env = {
  @as("SOCKET") socket?: string,
  @as("SALT") salt?: string,
  @as("OBJECT") objects?: fetcher,
}
let objects = _ => failwith("worker seat")
let salt = _ => failwith("worker seat")
let call = (_, ~operation as _, _) => failwith("worker seat")
let fetch = (_, _) => failwith("worker seat")
type worker = {fetch: (request, env) => promise<response>}
let default: worker = {fetch: fetch}
