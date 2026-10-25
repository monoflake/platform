/***
 * An app's id drawn where no control draws it, checked against what the machine holds, RFC b8f35,
 * and the app a control drew for a deploy it refused.
 */
module Contracts = Envelope.Contracts

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
    | [Some(id)] => Ids.Id.ofText(id)
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
    `${why}; app ${Ids.Id.text(id)} was opened, so deploy again with --app ${Ids.Id.text(
        id,
      )} to redeploy it`
  | (Some(_), _) | (None, None) => why
  }
