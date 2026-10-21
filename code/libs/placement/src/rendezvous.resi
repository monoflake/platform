/***
 * Where a parcel goes among the stores that meet its placement, RFC b8f35: rendezvous hashing over
 * integers alone, so two platforms never compute a place apart, as a float's last bit could. Which
 * stores meet a placement is the caller's; a deployment placed among hosts so waits on its own
 * context, vr5lw. The model's interface, `docs/code.md`.
 */

/** A store a parcel may go to: its id, an integer of 0 to 2^32 - 1, and its weight, 1 to 255. */
type store = {id: float, weight: int}

/** Why stores were not ranked: the parcel first, then each store in the order given, its id, its
 * weight, then whether an earlier store has its id. */
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
 * A store's score for the parcel: the highest, over `k` from 0 to its weight less one, of
 * `Keys.Derive.score` read as an unsigned 64-bit integer, big-endian. A store is so chosen
 * in proportion to its weight, exactly.
 */
let score: (~parcel: Uint8Array.t, store) => result<bigint, refused>

/**
 * The stores ranked for the parcel, the highest score first and a tie to the lower id: the copy or
 * shard `i` goes to the store at `i`. A store added or removed moves only what it wins or held.
 */
let ranked: (~parcel: Uint8Array.t, array<store>) => result<array<store>, refused>
