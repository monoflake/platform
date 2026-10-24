/***
 * The releases' artifacts, kept by their hash in hex, in R2 here and behind this record wherever
 * the control runs, RFC rxmd9.
 */
type t = {
  put: (string, Uint8Array.t) => promise<unit>,
  /** The artifact as an answer to its fetch, none where no artifact has the hash. */
  served: string => promise<option<Web.response>>,
}

let ofBucket: Stores.bucket => t

/** Kept as objects under `artifacts/`, each whole, so 16 MiB at most. */
let ofObjects: Objects.t => t
