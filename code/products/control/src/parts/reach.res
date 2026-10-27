/** The driver's port and the entry's, as the driver names them. */
let driverPort = 37483
let entryPort = 36879

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

/** Whether Cloudflare's edge set a header, which it refuses on a request sent back to it. */
let edge = name =>
  name->String.startsWith("cf-") || ["cdn-loop", "true-client-ip"]->Array.includes(name)

let relayed = (~origin, ~token, fetch: Web.fetch) => {
  origin: (~address, ~port) => `${origin}/relay/${address}/${Int.toString(port)}`,
  fetch: request => {
    let headers = request->Web.requestHeaders
    headers
    ->Web.headerNames
    ->Iterator.toArray
    ->Array.filter(edge)
    ->Array.forEach(name => headers->Web.deleteHeader(name))
    headers->Web.setHeader("proxy-authorization", `Bearer ${token}`)
    fetch(request)
  },
}

let direct = (origin, fetch: Web.fetch) => {
  origin: (~address as _, ~port as _) => origin,
  // A redirect could aim the binding's token at another host, so it is answered and not followed.
  fetch: request => fetch(Web.unredirected(request)),
}

/** Both Workers select the same local, network or relayed reach. */
let configured = (env: Stores.env) =>
  switch (env.standsOn, env.standsOnToken, env.reach, env.hosts) {
  | (Some(origin), Some(token), given, _) if origin != "" && token != "" =>
    Some(
      switch given {
      | Some(address) if address != "" => local(address)
      | Some(_) | None => relayed(~origin, ~token, Web.fetch)
      },
    )
  | (_, _, Some(address), _) if address != "" => Some(local(address))
  | (_, _, _, Some(hosts)) => Some(network(hosts))
  | (_, _, _, None) => None
  }
