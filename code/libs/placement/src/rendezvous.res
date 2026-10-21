/***
 * Where a parcel goes among the stores that meet its placement, RFC b8f35: rendezvous hashing over
 * integers alone, each store's score a bigint and never a float.
 */

type store = {id: float, weight: int}

type refused =
  | Parcel
  | Store(float)
  | Weight({store: float, weight: int})
  | Repeated(float)

/** The bytes read as an unsigned integer, big-endian. */
let unsigned = bytes =>
  bytes->TypedArray.reduce(
    (n, byte) => BigInt.add(BigInt.shiftLeft(n, 8n), BigInt.fromInt(byte)),
    0n,
  )

/** Keys' score at `k`, read as rendezvous reads it. `k` is below the store's weight and so in
 * range, which leaves the parcel and the store's id the only parts keys refuses. */
let at = (~parcel, store, ~k) =>
  switch Keys.Derive.score(~parcel, ~store=store.id, ~k) {
  | Ok(bytes) => Ok(unsigned(bytes))
  | Error(Length(_)) => Error(Parcel)
  | Error(Range(_)) => Error(Store(store.id))
  }

/** The highest of `best` and each score from `k` to the store's weight less one. */
let rec highest = (~parcel, store, ~k, ~best) =>
  k == store.weight
    ? Ok(best)
    : at(~parcel, store, ~k)->Result.flatMap(score =>
        highest(~parcel, store, ~k=k + 1, ~best=score > best ? score : best)
      )

let score = (~parcel, store) =>
  at(~parcel, store, ~k=0)->Result.flatMap(first =>
    store.weight >= 1 && store.weight <= 255
      ? highest(~parcel, store, ~k=1, ~best=first)
      : Error(Weight({store: store.id, weight: store.weight}))
  )

/** Each store with its score, in the order given, or the first refusal among them. */
let rec scored = (~parcel, stores, ~from, ~seen, ~done) =>
  switch stores[from] {
  | None => Ok(done)
  | Some(store) =>
    score(~parcel, store)->Result.flatMap(score =>
      if seen->Set.has(store.id) {
        Error(Repeated(store.id))
      } else {
        seen->Set.add(store.id)
        done->Array.push((store, score))
        scored(~parcel, stores, ~from=from + 1, ~seen, ~done)
      }
    )
  }

let ranked = (~parcel, stores) =>
  TypedArray.length(parcel) == 32
    ? scored(~parcel, stores, ~from=0, ~seen=Set.make(), ~done=[])->Result.map(scored =>
        scored
        ->Array.toSorted(((a, scoreA), (b, scoreB)) =>
          if scoreA != scoreB {
            scoreA > scoreB ? -1.0 : 1.0
          } else {
            Float.compare(a.id, b.id)
          }
        )
        ->Array.map(((store, _)) => store)
      )
    : Error(Parcel)
