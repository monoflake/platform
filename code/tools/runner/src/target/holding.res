/***
 * What a case is held before its first step, through the same driver's `management`, RFC p8e8k.
 */
let making = 120000

/** How an item is asked again, as `within` is retried. */
let firstDelay = 100
let longestDelay = 2000

/** The capacity a case of each kind is held, by its interface, as the check reads a `given`. */
let kindOf = interface =>
  switch interface {
  | "deployments" => Some("container")
  | "object" => Some("object")
  | "database" => Some("database")
  | _ => None
  }

// A given naming its capacity, a volume among them, is applied as it names it.
let capacity = (~interface, given) =>
  given
  ->JSON.Decode.object
  ->Option.flatMap(fields =>
    switch (fields->Dict.get("name")->Option.flatMap(JSON.Decode.string), kindOf(interface)) {
    | (Some(_), _) => Some(given)
    | (None, Some(name)) =>
      let fields = fields->Dict.copy
      fields->Dict.set("name", JSON.String(name))
      Some(JSON.Object(fields))
    | (None, None) => None
    }
  )

let field = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))

let text = (json, name) => field(json, name)->Option.flatMap(JSON.Decode.string)

/** The items a described list holds, each its id and its state's JSON. */
let itemsOf = described =>
  field(described, "items")
  ->Option.flatMap(JSON.Decode.array)
  ->Option.getOr([])
  ->Array.filterMap(item =>
    switch (field(item, "id")->Option.flatMap(JSON.Decode.float), field(item, "state")) {
    | (Some(id), Some(state)) => Some((id, state))
    | (Some(_) | None, Some(_) | None) => None
    }
  )

let given = (~call, ~now, ~wait, ~held) =>
  async (~interface, ~form, given) => {
    let managed = async (operation, input) =>
      switch await call(~interface="management", ~operation, ~input, ~form, ~as_=None) {
      | Ok(Run.Answered(json)) => Ok(json)
      | Ok(Failed({failure, reason, message})) =>
        Error(`management ${operation} answered ${failure} ${reason}, ${message}`)
      | Error(why) => Error(`management ${operation}, ${why}`)
      }
    let asked = switch given {
    | Some(given) => Some(given)
    | None => held->Dict.get(interface)
    }
    switch (asked, asked->Option.flatMap(asked => capacity(~interface, asked))) {
    | (None, _) => Ok()
    | (Some(_), None) =>
      Error(
        Filling.Unoffered(
          `a given of ${interface}, which holds no capacity a driver's management makes`,
        ),
      )
    | (Some(_), Some(capacity)) =>
      let described = await managed("describe", JSON.Object(dict{}))
      let applied = switch described {
      | Error(why) => Error(why)
      | Ok(described) if itemsOf(described) != [] =>
        Error("the case's binding holds items already, whose credentials describe never gives")
      | Ok(described) =>
        let generation = field(described, "generation")->Option.flatMap(JSON.Decode.float)
        let credential = Envelope.Hex.encode(Noble.blake3(Web.random(32), {dkLen: 32}))
        let list = JSON.Object(
          dict{
            "generation": JSON.Number(generation->Option.getOr(0.) +. 1.),
            "items": JSON.Array([
              JSON.Object(
                dict{
                  "id": JSON.Number(1.),
                  "capacity": capacity,
                  "credentials": JSON.Array([JSON.String(credential)]),
                },
              ),
            ]),
          },
        )
        (await managed("apply", list))->Result.map(_ => ())
      }
      // The item is asked again until it is made, as `within` asks a step.
      let start = now()
      let rec made = async delay =>
        switch await managed("describe", JSON.Object(dict{})) {
        | Error(why) => Error(why)
        | Ok(described) =>
          switch itemsOf(described)->Array.find(((id, _)) => id == 1.) {
          | None => Error("the item applied is not held")
          | Some((_, state)) =>
            switch text(state, "name") {
            | Some("made") => Ok()
            | Some("failed") =>
              Error(
                `the item applied failed, ${text(state, "reason")->Option.getOr("")} ${text(
                    state,
                    "message",
                  )->Option.getOr("")}`->String.trim,
              )
            | Some(_) | None if now() -. start >= Int.toFloat(making) =>
              Error(`the item applied is not made within ${Int.toString(making)} ms`)
            | Some(_) | None =>
              await wait(delay)
              await made(Math.Int.min(delay * 2, longestDelay))
            }
          }
        }
      switch applied {
      | Error(why) => Error(Filling.Unwritten(why))
      | Ok() => (await made(firstDelay))->Result.mapError(why => Filling.Unwritten(why))
      }
    }
  }
