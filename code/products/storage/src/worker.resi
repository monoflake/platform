/***
 * The storage product's Worker, one module set run as two workerd workers told apart by
 * `MONOFLAKE_SOCKET`, `public` serving objects and `data` taking the driver's calls. The model's
 * interface, `docs/code.md`.
 */

/** The runtime's `Request` and `Response`. */
type request
type response

/** A service binding, the `object` kind at `OBJECT`. */
type fetcher

/** What the function kind binds, each absent where it is not given. */
type env = {
  @as("MONOFLAKE_SOCKET") socket?: string,
  @as("MONOFLAKE_SALT") salt?: string,
  @as("OBJECT") objects?: fetcher,
}

/** The kind called through its binding, `POST http://object/object/{operation}` with JSON. */
let objects: fetcher => Operations.objects

/** The salt read from 64 lowercase hex, none for any other text. */
let salt: string => option<Uint8Array.t>

/**
 * An operation of buckets.res by its name over its input's JSON, its answer's JSON; a name no
 * object operation has, or input malformed, answers as the contracts say.
 */
let call: (Operations.context, ~operation: string, JSON.t) => promise<JSON.t>

/**
 * On `data`, `POST /storage/{operation}` carrying `Monoflake-Caller` is called, and anything else
 * there answers `forbidden`. On `public`, a call answers `forbidden` and every other path 404.
 */
let fetch: (request, env) => promise<response>

type worker = {fetch: (request, env) => promise<response>}

let default: worker
