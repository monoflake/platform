/***
 * A journal, RFC b8f35, a first object's prefix and then each write's segments sealed as a parcel's
 * are.
 */

let prefix = 5

type written = {object: Uint8Array.t, next: int}

type unsealable = Key | Master | Seed | First | Empty | Overfull

type unopened =
  | First
  | Prefix
  | Reserved
  | Revision(int)
  | Master
  | Key
  | Length
  | Tag(int)

let sealable = (~key, ~header: Parcel.header, ~first, bytes): result<unit, unsealable> =>
  if TypedArray.length(key) != 32 {
    Error(Key)
  } else if !Segments.versioned(header.master) {
    Error(Master)
  } else if TypedArray.length(header.seed) != 32 {
    Error(Seed)
  } else if first < 0 {
    Error(First)
  } else if TypedArray.length(bytes) == 0 {
    Error(Empty)
  } else if TypedArray.length(bytes) > Parcel.capacity {
    Error(Overfull)
  } else {
    Ok()
  }

let seal = async (~key, ~header, ~first, bytes) =>
  switch sealable(~key, ~header, ~first, bytes) {
  | Error(refused) => Error(refused)
  | Ok() =>
    let length = TypedArray.length(bytes)
    let count = (length + Segments.segment - 1) / Segments.segment
    let head = Segments.header(~master=header.master, ~seed=header.seed)
    let sealing = await Web.key(key)
    let sealed = await Promise.all(
      Array.fromInitializer(~length=count, j =>
        sealing->Web.sealed(
          ~iv=Segments.nonce(first + j),
          ~additionalData=Segments.associated(head, first + j, ~final=false),
          bytes->TypedArray.subarray(
            ~start=j * Segments.segment,
            ~end=Math.Int.min((j + 1) * Segments.segment, length),
          ),
        )
      ),
    )
    let begun = first == 0 ? prefix : 0
    let object = Uint8Array.fromLength(begun + length + count * Segments.tag)
    if first == 0 {
      object->TypedArray.setArray(Segments.begins(~master=header.master))
    }
    sealed->Array.forEachWithIndex((sealed, j) =>
      object->Web.setFrom(sealed, begun + j * Segments.sealed)
    )
    Ok({object, next: first + count})
  }

let begun = bytes =>
  if TypedArray.length(bytes) < prefix {
    Error(Prefix)
  } else {
    switch bytes->TypedArray.get(0)->Option.getOr(0) {
    | 1 =>
      let master = Segments.read32(bytes, 1)
      master == 0. ? Error(Master) : Ok(master)
    | 2 => Error(Reserved)
    | revision => Error(Revision(revision))
    }
  }

/** What a first object's prefix refuses, or none where it holds, or the object is not a first. */
let prefixed = (~header: Parcel.header, ~first, bytes) =>
  if first != 0 {
    None
  } else {
    switch begun(bytes) {
    | Error(refused) => Some(refused)
    | Ok(master) => master == header.master ? None : Some(Master)
    }
  }

let opened = async (~key, ~header, ~first, bytes) =>
  switch first < 0 ? Some(First) : prefixed(~header, ~first, bytes) {
  | Some(refused) => Error(refused)
  | None if TypedArray.length(key) != 32 => Error(Key)
  | None =>
    let body = bytes->TypedArray.subarray(~start=first == 0 ? prefix : 0)
    let length = TypedArray.length(body)
    let count = (length + Segments.sealed - 1) / Segments.sealed
    if count == 0 || length - (count - 1) * Segments.sealed <= Segments.tag {
      Error(Length)
    } else {
      let head = Segments.header(~master=header.master, ~seed=header.seed)
      let sealing = await Web.key(key)
      let opened = await Promise.all(
        Array.fromInitializer(~length=count, j =>
          sealing->Web.opened(
            ~iv=Segments.nonce(first + j),
            ~additionalData=Segments.associated(head, first + j, ~final=false),
            body->TypedArray.subarray(
              ~start=j * Segments.sealed,
              ~end=Math.Int.min((j + 1) * Segments.sealed, length),
            ),
          )
        ),
      )
      switch opened->Array.findIndex(Option.isNone) {
      | -1 =>
        let plain = Uint8Array.fromLength(length - count * Segments.tag)
        opened->Array.forEachWithIndex((opened, j) =>
          opened->Option.forEach(bytes => plain->Web.setFrom(bytes, j * Segments.segment))
        )
        Ok((plain, first + count))
      | j => Error(Tag(first + j))
      }
    }
  }
