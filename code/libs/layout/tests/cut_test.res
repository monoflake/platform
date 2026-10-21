/***
 * `Cut` held to `tests/layout/cuts.json`, every content cut into the pieces it gives however it is
 * split.
 */
open Node
open Sample

let cuts = "tests/layout/cuts.json"

let gear = switch Keys.Derive.gear(~salt=read(cuts)->hexAt(["salt"])) {
| Ok(gear) => gear
| Error(_) => JsError.throwWithMessage(`${cuts}: a salt refused`)
}

/** The pieces content gives, pushed in parts cut at `points`, offsets in order. */
let pieces = (content, points) => {
  let cut = switch Cut.make(~gear) {
  | Ok(cut) => cut
  | Error(Gear) => JsError.throwWithMessage("a gear table refused")
  }
  let length = TypedArray.length(content)
  let ends = points->Array.filter(p => p > 0 && p < length)->Array.concat([length])
  let (_, found) =
    ends->Array.reduce((0, []), ((start, found), end) => (
      end,
      found->Array.concat(cut->Cut.push(content->TypedArray.subarray(~start, ~end))),
    ))
  switch cut->Cut.finish {
  | Some(last) => found->Array.concat([last])
  | None => found
  }
}

/** Offsets every `step` bytes, then on in a cycle of uneven steps, some empty. */
let every = (length, steps) => {
  let points = []
  let at = ref(0)
  let i = ref(0)
  while at.contents < length {
    at := at.contents + steps->Array.getUnsafe(mod(i.contents, Array.length(steps)))
    i := i.contents + 1
    points->Array.push(at.contents)
  }
  points
}

/** Offsets at each piece's end, a byte before it and a byte after. */
let around = pieces => {
  let (_, points) = pieces->Array.reduce((0, []), ((end, points), length) => {
    let end = end + length
    (end, points->Array.concat([end - 1, end, end, end + 1]))
  })
  points
}

test("content is cut into the pieces its sample gives, however it is split", () =>
  read(cuts)
  ->at(["cases"])
  ->array
  ->Array.forEach(item => {
    let message = JSON.stringify(item->at(["content"]))
    let content = content(item->at(["content"]))
    let expected = item->at(["pieces"])->array->Array.map(p => p->number->Float.toInt)
    let length = TypedArray.length(content)
    [
      [],
      every(length, [65_536]),
      every(length, [1_000_003]),
      every(length, [1, 0, 7, 262_143, 262_144, 0, 1, 99_991, 4_194_303]),
      around(expected),
    ]->Array.forEach(points => deepEqual(pieces(content, points), expected, ~message))
  })
)

test("a gear table not of 2,048 bytes is refused", () =>
  [0, 2047, 2049]->Array.forEach(length =>
    deepEqual(
      Cut.make(~gear=Uint8Array.fromLength(length))->Result.isError,
      true,
      ~message=Int.toString(length),
    )
  )
)
