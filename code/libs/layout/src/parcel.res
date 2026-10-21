/*** A parcel, RFC b8f35, its 41-byte header and then 256 segments sealed by AES-256-GCM. */

let size = 16_777_216
let capacity = 16_773_079

// How many segments a parcel holds.
let segments = 256

type header = {master: float, seed: Uint8Array.t}

type unsealable = Key | Master | Seed | Overfull

type unopened =
  | Size
  | Magic
  | Reserved
  | Revision(int)
  | Master
  | Key
  | Tag(int)

let fits = (~used, ~length) =>
  used >= 0 && length >= 0 && used + length <= capacity ? Some(used) : None

let sealable = (~key, ~header, pieces): result<unit, unsealable> =>
  if TypedArray.length(key) != 32 {
    Error(Key)
  } else if !Segments.versioned(header.master) {
    Error(Master)
  } else if TypedArray.length(header.seed) != 32 {
    Error(Seed)
  } else if TypedArray.length(pieces) > capacity {
    Error(Overfull)
  } else {
    Ok()
  }

let seal = async (~key, ~header, pieces) =>
  switch sealable(~key, ~header, pieces) {
  | Error(refused) => Error(refused)
  | Ok() =>
    let plain = Uint8Array.fromLength(capacity)
    plain->Web.setFrom(pieces, 0)
    let head = Segments.header(~master=header.master, ~seed=header.seed)
    let sealing = await Web.key(key)
    let sealed = await Promise.all(
      Array.fromInitializer(~length=segments, i =>
        sealing->Web.sealed(
          ~iv=Segments.nonce(i),
          ~additionalData=Segments.associated(head, i, ~final=i == segments - 1),
          plain->TypedArray.subarray(
            ~start=i * Segments.segment,
            ~end=Math.Int.min((i + 1) * Segments.segment, capacity),
          ),
        )
      ),
    )
    let parcel = Uint8Array.fromLength(size)
    parcel->Web.setFrom(head, 0)
    sealed->Array.forEachWithIndex((bytes, i) =>
      parcel->Web.setFrom(bytes, Segments.headed + i * Segments.sealed)
    )
    Ok(parcel)
  }

let header = bytes =>
  if TypedArray.length(bytes) != size {
    Error(Size)
  } else if (
    Segments.magic->Array.someWithIndex((byte, i) => bytes->TypedArray.get(i) != Some(byte))
  ) {
    Error(Magic)
  } else {
    switch bytes->TypedArray.get(4)->Option.getOr(0) {
    | 1 =>
      let master = Segments.read32(bytes, 5)
      master == 0.
        ? Error(Master)
        : Ok({master, seed: bytes->TypedArray.slice(~start=9, ~end=Segments.headed)})
    | 2 => Error(Reserved)
    | revision => Error(Revision(revision))
    }
  }

let opened = async (~key, bytes) =>
  switch header(bytes) {
  | Error(refused) => Error(refused)
  | Ok(_) if TypedArray.length(key) != 32 => Error(Key)
  | Ok(read) =>
    let head = bytes->TypedArray.subarray(~start=0, ~end=Segments.headed)
    let sealing = await Web.key(key)
    let opened = await Promise.all(
      Array.fromInitializer(~length=segments, i => {
        let start = Segments.headed + i * Segments.sealed
        sealing->Web.opened(
          ~iv=Segments.nonce(i),
          ~additionalData=Segments.associated(head, i, ~final=i == segments - 1),
          bytes->TypedArray.subarray(~start, ~end=Math.Int.min(start + Segments.sealed, size)),
        )
      }),
    )
    switch opened->Array.findIndex(Option.isNone) {
    | -1 =>
      let plain = Uint8Array.fromLength(capacity)
      opened->Array.forEachWithIndex((opened, i) =>
        opened->Option.forEach(bytes => plain->Web.setFrom(bytes, i * Segments.segment))
      )
      Ok((read, plain))
    | i => Error(Tag(i))
    }
  }
