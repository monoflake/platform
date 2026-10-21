/***
 * Where a parcel goes among the stores meeting its placement, by rendezvous hashing over integers
 * so no two platforms differ, RFC b8f35. The model's interface, `docs/code.md`.
 */

/** A store a parcel may go to, its id, an integer of 0 to 2^32 - 1, and its weight, 1 to 255. */
type store = {id: float, weight: int}

/**
 * Why stores were not ranked, the parcel first and then each store's id, weight and repeat in
 * order.
 */
type refused =
  /** A parcel's id not of 32 bytes. */
  | Parcel
  /** A store's id outside its range. */
  | Store(float)
  /** A store's weight outside 1 to 255. */
  | Weight({store: float, weight: int})
  /** Two stores of one id. */
  | Repeated(float)

/**
 * A store's score, the highest `Keys.Derive.score` as a big-endian u64 over `k` below its weight,
 * so choice follows weight exactly.
 */
let score: (~parcel: Uint8Array.t, store) => result<bigint, refused>

/**
 * The stores ranked for the parcel, highest score first and a tie to the lower id, copy or shard
 * `i` going to store `i`.
 */
let ranked: (~parcel: Uint8Array.t, array<store>) => result<array<store>, refused>
