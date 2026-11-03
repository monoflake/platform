/*** The `object` kind in memory, a name to its bytes, as model/contracts/kinds/objects.res says. */
open Envelope

/** The kind, what it holds, and each call made of it as its operation and name. */
type t = {objects: Operations.objects, held: dict<Uint8Array.t>, calls: array<string>}

/** The most bytes an object holds, and the names listed unless a limit is set. */
let most =
  16 * 1024 * 1024
let page = 1000

let make = (): t => {
  let held: dict<Uint8Array.t> = dict{}
  let calls = []
  let size = bytes => TypedArray.length(bytes)->Int.toFloat
  let objects: Operations.objects = {
    status: async ({id}) => {
      calls->Array.push(`status ${id}`)
      Error({failure: Rejected, reason: "not_found", message: "Nothing of that name or id exists"})
    },
    write: async ({name, content}) => {
      calls->Array.push(`write ${name}`)
      if TypedArray.length(content) > most {
        Error({
          failure: Rejected,
          reason: "too_large",
          message: Contracts.messages->Dict.get("too_large")->Option.getOr(""),
        })
      } else {
        held->Dict.set(name, content->TypedArray.slice(~start=0, ~end=TypedArray.length(content)))
        Success({})
      }
    },
    read: async ({name, ?range}) => {
      calls->Array.push(`read ${name}`)
      switch held->Dict.get(name) {
      | None =>
        Error({
          failure: Rejected,
          reason: "not_found",
          message: Contracts.messages->Dict.get("not_found")->Option.getOr(""),
        })
      | Some(bytes) =>
        let whole = TypedArray.length(bytes)
        let (start, end) = switch range {
        | None => (0, whole)
        | Some({start, length}) =>
          let start = Math.Int.min(Float.toInt(start), whole)
          (start, Math.Int.min(start + Float.toInt(length), whole))
        }
        Success({content: bytes->TypedArray.slice(~start, ~end), size: size(bytes)})
      }
    },
    describe: async ({name}) => {
      calls->Array.push(`describe ${name}`)
      Success({size: ?(held->Dict.get(name)->Option.map(size))})
    },
    delete: async ({name}) => {
      calls->Array.push(`delete ${name}`)
      held->Dict.delete(name)
      Success({})
    },
    list: async ({prefix, ?after, ?limit}) => {
      calls->Array.push(`list ${prefix}`)
      let limit = limit->Option.mapOr(page, Float.toInt)
      let names =
        held
        ->Dict.keysToArray
        ->Array.filter(name =>
          name->String.startsWith(prefix) &&
            switch after {
            | None => true
            | Some(after) => name > after
            }
        )
        ->Array.toSorted(String.compare)
      let taken = names->Array.slice(~start=0, ~end=limit)
      let next = Array.length(names) > limit ? taken->Array.at(-1) : None
      Success({
        objects: taken->Array.map((name): Contracts.ObjectListedOne.t => {
          name,
          size: held->Dict.get(name)->Option.mapOr(0., size),
        }),
        ?next,
      })
    },
  }
  {objects, held, calls}
}
