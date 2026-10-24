type t = {
  origin: (~address: string, ~port: int) => string,
  fetch: Web.fetch,
}

let network = hosts => {
  origin: (~address, ~port) => `http://${address}:${Int.toString(port)}`,
  fetch: request => hosts->Web.fetchThrough(request),
}

let local = given => {
  origin: (~address as _, ~port) => `http://${given}:${Int.toString(port)}`,
  // Called as a method, the global fetch would be given a receiver workerd refuses.
  fetch: request => Web.fetch(request),
}

let relayed = (~origin, ~token, fetch: Web.fetch) => {
  origin: (~address, ~port) => `${origin}/relay/${address}/${Int.toString(port)}`,
  fetch: request => {
    request->Web.requestHeaders->Web.setHeader("proxy-authorization", `Bearer ${token}`)
    fetch(request)
  },
}
