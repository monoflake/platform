/***
 * A host's tunnel and the route to its private address, made through Cloudflare's API by the
 * control's own credential, RFC rxmd9. The fetch is given, so a test answers it.
 */
type t = {
  /** A tunnel run by its token alone, by its name, answering its id. */
  make: string => promise<result<string, string>>,
  /** The route sending one address to a tunnel. */
  route: (~tunnel: string, ~address: string) => promise<result<unit, string>>,
  /** The token a tunnel is run by. */
  token: string => promise<result<string, string>>,
}

/** The API's base URL, the account and the credential, which holds Cloudflare Tunnel Edit. */
type config = {api: string, account: string, credential: string}

let through: (config, Web.fetch) => t
