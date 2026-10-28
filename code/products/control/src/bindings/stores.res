/*** What the control takes of a Worker's D1 and R2, and the environment that names them. */
@notUndefined
type database
type statement

/** A value bound to a statement, text, a number or none. */
@unboxed
type value = Text(string) | Number(float) | @as(null) Null

@send external prepare: (database, string) => statement = "prepare"
@send @variadic external bind: (statement, array<value>) => statement = "bind"
/** The first row, its columns read as the caller's record names them. */
@send external first: statement => promise<Nullable.t<'row>> = "first"
@send external batch: (database, array<statement>) => promise<unit> = "batch"
@send external run: statement => promise<unit> = "run"

@notUndefined
type bucket
type held = {size: float, body: Web.body}
@send external put: (bucket, string, Uint8Array.t) => promise<unit> = "put"
@send external get: (bucket, string) => promise<Nullable.t<held>> = "get"

/**
 * The Worker's bindings, secrets and variables, `wrangler.json`'s names, each variable text and
 * absent where unset; a control standing on another is given its origin and token in their place.
 */
type env = {
  @as("STATE") state?: database,
  @as("ARTIFACTS") artifacts?: bucket,
  @as("STANDS_ON") standsOn?: string,
  @as("STANDS_ON_TOKEN") standsOnToken?: string,
  @as("HOSTS") hosts?: Web.fetcher,
  @as("OPERATOR") operator?: string,
  @as("SEALING_KEY") sealingKey?: string,
  @as("REACH") reach?: string,
  @as("ORIGIN") origin?: string,
  @as("DRIVER_PORT") driverPort?: string,
  @as("ENTRY_PORT") entryPort?: string,
  @as("TUNNEL_API") tunnelApi?: string,
  @as("TUNNEL_ACCOUNT") tunnelAccount?: string,
  @as("TUNNEL_CREDENTIAL") tunnelCredential?: string,
}
