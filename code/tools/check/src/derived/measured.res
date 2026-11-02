/**
 * The state each contract's samples measure on a target, read from its snapshot by RFC s42ex's
 * table, and never read by the part of the check that refuses.
 */
open Base

@module("node:os") external homedir: unit => string = "homedir"
@module("node:fs") external readText: (string, @as("utf8") _) => string = "readFileSync"

/** A state of RFC s42ex's table but proven, which this model does not derive yet. */
type state = NoSamples | NotStarted | Failing | Thin | Whole | Unknown

let stateName = s =>
  switch s {
  | NoSamples => "no samples"
  | NotStarted => "not started"
  | Failing => "failing"
  | Thin => "thin"
  | Whole => "whole"
  | Unknown => "unknown"
  }

/** A contract's state from its counts, a skipped case taken as one still waiting. */
let stateOf = (c: Snapshots.counted) => {
  let waiting = c.waiting + c.skipped
  if c.passed + c.failed + waiting == 0 {
    NoSamples
  } else if c.failed > 0 {
    Failing
  } else if c.passed == 0 {
    NotStarted
  } else if waiting > 0 {
    Thin
  } else {
    Whole
  }
}

/** The directory snapshots are written to, `~` read as the home directory. */
let directory = () =>
  Snapshots.directory->String.startsWith("~/")
    ? `${homedir()}/${Snapshots.directory->String.slice(~start=2)}`
    : Snapshots.directory

let count = (j: JSON.t, k) =>
  numeric(j->member(k))->Option.flatMap(n => isInteger(n) ? Some(Float.toInt(n)) : None)

let counted = (j: JSON.t): option<Snapshots.counted> =>
  switch (count(j, "passed"), count(j, "failed"), count(j, "waiting"), count(j, "skipped")) {
  | (Some(passed), Some(failed), Some(waiting), Some(skipped)) =>
    Some({passed, failed, waiting, skipped})
  | _ => None
  }

/** A snapshot read from its JSON, or none where any part of it is not as `Snapshots` has it. */
let decode = (j: JSON.t): option<Snapshots.snapshot> =>
  switch (
    text(j->member("target")),
    text(j->member("checkout")),
    text(j->member("at")),
    object(j->member("contracts")),
    j->member("revision"),
  ) {
  | (Some(target), Some(checkout), Some(at), Some(contracts), given)
    if given->Option.isNone || text(given)->Option.isSome =>
    let revision = text(given)
    let read = contracts->Dict.toArray->Array.map(((name, c)) => (name, counted(c)))
    read->Array.every(((_, c)) => c->Option.isSome)
      ? Some({
          target,
          ?revision,
          checkout,
          at,
          contracts: read
          ->Array.filterMap(((name, c)) => c->Option.map(c => (name, c)))
          ->Dict.fromArray,
        })
      : None
  | _ => None
  }

/** One target's snapshot, none where it is missing or unreadable. */
let read = target =>
  try {
    decode(JSON.parseOrThrow(readText(`${directory()}${target}.json`)))
  } catch {
  | _ => None
  }

/**
 * What a target's snapshot shows. Each contract's state is bound where the target reported its
 * revision, and unbound where only the local checkout is known, which the target does not report.
 */
let lines = (target, snapshot: option<Snapshots.snapshot>) =>
  switch snapshot {
  | None => [`${target}: ${stateName(Unknown)}, no readable snapshot`]
  | Some(s) =>
    let (head, binding) = switch s.revision {
    | Some(revision) => (`revision ${revision}`, "bound")
    | None => (`checkout ${s.checkout}`, "unbound")
    }
    [`${target}: ${head} at ${s.at}, ${binding}`]->Array.concat(
      s.contracts
      ->Dict.toArray
      ->Array.toSorted(((a, _), (b, _)) => byText(a, b))
      ->Array.map(((name, c)) =>
        `${target} ${name}: ${stateName(stateOf(c))}, ${binding}, ${int(c.passed)} passed, ${int(
            c.failed,
          )} failed, ${int(c.waiting)} waiting, ${int(c.skipped)} skipped`
      ),
    )
  }
