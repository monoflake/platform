/***
 * An app's id written as 8 lowercase hex digits, RFC b8f35, and one drawn where no control draws
 * it, checked against what the machine holds.
 */
module Contracts = Envelope.Contracts

/** The id written out, leading zeros kept. */
let text = id => id->Float.toString(~radix=16)->String.padStart(8, "0")

let written = /^[0-9a-f]{8}$/

/** The id 8 lowercase hex digits write, none for any other text or for 0, which no id is. */
let ofText = text =>
  written->RegExp.test(text)
    ? Some(Float.parseInt(text, ~radix=16))->Option.filter(id => id > 0.)
    : None

/** The 32 bits of 4 bytes read big-endian, as an id is read from its bytes. */
let ofBytes = (bytes: Uint8Array.t) =>
  [0, 1, 2, 3]->Array.reduce(0., (id, i) =>
    id *. 256. +. bytes->TypedArray.get(i)->Option.mapOr(0., Int.toFloat)
  )

/** Every id the machine's list holds, its items' and those of what it adopted. */
let listed = (described: Contracts.ManagementDescribed.t) =>
  Array.concat(
    described.items->Array.map(i => i.id),
    described.adopted
    ->Option.getOr([])
    ->Array.map(a =>
      switch a.for_ {
      | Deployment({runs: App({id})}) | Deployment({runs: Component({id})}) | Item({id}) => id
      }
    ),
  )

/** How many draws are made before the drawing gives up, each one a conflict. */
let draws = 16

/**
 * An id drawn by `random` that `held` says nothing holds, drawn again on a conflict, 0 passed over
 * as no id, or why none was found.
 */
let drawn = (~random: unit => float, ~held: float => result<bool, string>) => {
  let rec draw = left =>
    if left == 0 {
      Error(`every one of ${Int.toString(draws)} ids drawn is held already`)
    } else {
      switch random() {
      | 0. => draw(left - 1)
      | id =>
        switch held(id) {
        | Ok(false) => Ok(id)
        | Ok(true) => draw(left - 1)
        | Error(why) => Error(why)
        }
      }
    }
  draw(draws)
}

/** A control's refusal naming the app it drew, `app <8 hex>, ` before what it says. */
let naming = /^app ([0-9a-f]{8}), /

/** The app a control's refusal names as drawn for the deploy it refused, none where none is. */
let named = message =>
  switch naming->RegExp.exec(message) {
  | Some(found) =>
    switch found->RegExp.Result.matches {
    | [Some(id)] => ofText(id)
    | _ => None
    }
  | None => None
  }

/**
 * Why a deploy failed, and where it opened a new app, its id and the retry that redeploys it rather
 * than drawing another.
 */
let retried = (~given, ~drawn, why) =>
  switch (given, drawn) {
  | (None, Some(id)) =>
    `${why}; app ${text(id)} was opened, so deploy again with --app ${text(id)} to redeploy it`
  | (Some(_), _) | (None, None) => why
  }
