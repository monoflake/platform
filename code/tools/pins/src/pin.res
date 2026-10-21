type published = {version: string, at: float}

type registry = {latest: string, published: array<published>}

let field = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))

let registry = text =>
  switch try Some(JSON.parseOrThrow(text)) catch {
  | JsExn(_) => None
  } {
  | None => Error("the registry's document is not JSON")
  | Some(document) =>
    let latest =
      document
      ->field("dist-tags")
      ->Option.flatMap(tags => tags->field("latest"))
      ->Option.flatMap(JSON.Decode.string)
    let versions = document->field("versions")->Option.flatMap(JSON.Decode.object)
    let times = document->field("time")->Option.flatMap(JSON.Decode.object)
    switch (latest, versions, times) {
    | (None, _, _) => Error("the registry's document has no latest tag")
    | (_, None, _) => Error("the registry's document has no versions")
    | (_, _, None) => Error("the registry's document has no publish times")
    | (Some(latest), Some(versions), Some(times)) =>
      // `time` keeps a version unpublished since, and `created` and `modified`; `versions` does not.
      let published =
        versions
        ->Dict.keysToArray
        ->Array.filterMap(version =>
          times
          ->Dict.get(version)
          ->Option.flatMap(JSON.Decode.string)
          ->Option.map(time => {version, at: Date.fromString(time)->Date.getTime})
          ->Option.filter(({at}) => !Float.isNaN(at))
        )
      Ok({latest, published})
    }
  }

let delay = text =>
  switch /^minimumReleaseAge:\s*(\d+)\s*$/m
  ->RegExp.exec(text)
  ->Option.map(RegExp.Result.matches) {
  | Some([Some(minutes)]) =>
    minutes->Int.fromString->Option.mapOr(Error("minimumReleaseAge is not a number"), m => Ok(m))
  | _ => Error("no minimumReleaseAge")
  }

type chosen = {take: option<string>, held: array<string>}

let choose = ({latest, published}, ~delay, ~now) => {
  let newest = published->Array.toSorted((a, b) => b.at -. a.at)
  let bound = published->Array.find(p => p.version == latest)->Option.mapOr(now, p => p.at)
  let candidates = newest->Array.filter(p => p.at <= bound)
  let ready = now -. Int.toFloat(delay) *. 60_000.
  let take = candidates->Array.find(p => p.at <= ready)
  {
    take: take->Option.map(p => p.version),
    held: candidates
    ->Array.filter(p => take->Option.mapOr(true, t => p.at > t.at))
    ->Array.map(p => p.version),
  }
}

type pin = {version: string, hashes: dict<string>}

/** A value's place in a text, from its first byte to past its last. */
type span = {start: int, end: int}

/** Every match of `pattern` in `text`, in order. */
let all = (~flags="g", pattern, text) => {
  let global = RegExp.fromString(pattern, ~flags)
  let found = []
  let rec next = () =>
    switch global->RegExp.exec(text) {
    | Some(m) =>
      found->Array.push(m)
      next()
    | None => ()
    }
  next()
  found
}

/** An `ARG`'s default where a match of `arg` lies: past its name and any opening quote. */
let value = m => {
  let length = group => group->Option.flatMap(g => g)->Option.mapOr(0, String.length)
  let groups = m->RegExp.Result.matches
  let start = m->RegExp.Result.index + length(groups[0]) + length(groups->Array.at(-2))
  {start, end: start + length(groups->Array.at(-1))}
}

/** An `ARG` named `name`, its prefix, its quote and its default each a group. */
let arg = name => `^([ \\t]*(?:ARG|arg)[ \\t]+${name}=)("?)([^"\\s]+)`

/** The one place `pattern` matches in `text`, or why there is not exactly one. */
let once = (~flags="g", pattern, text, ~what) =>
  switch all(~flags, pattern, text) {
  | [m] => Ok(m)
  | [] => Error(`no ${what}`)
  | _ => Error(`more than one ${what}`)
  }

/** Where the pin's values lie: the version's, and each architecture's hash's. */
let places = text =>
  once(
    ~flags="gm",
    arg("WORKERD_VERSION"),
    text,
    ~what="WORKERD_VERSION ARG with a default",
  )->Result.flatMap(version => {
    let hashes = Dict.make()
    let doubled = all(~flags="gm", arg("WORKERD_SHA256_([A-Z0-9]+)"), text)->Array.filter(m =>
      switch m->RegExp.Result.matches {
      | [_, Some(architecture), _, _]
        if hashes->Dict.get(architecture->String.toLowerCase) == None =>
        hashes->Dict.set(architecture->String.toLowerCase, value(m))
        false
      | _ => true
      }
    )
    switch (doubled, hashes->Dict.keysToArray) {
    | ([], []) => Error("no WORKERD_SHA256_ ARG with a default")
    | ([], _) => Ok((value(version), hashes))
    | _ => Error("an architecture's WORKERD_SHA256_ ARG twice")
    }
  })

let slice = (text, {start, end}) => text->String.slice(~start, ~end)

let read = text =>
  places(text)->Result.map(((version, hashes)) => {
    version: text->slice(version),
    hashes: hashes->Dict.mapValues(span => text->slice(span)),
  })

let sorted = keys => keys->Array.toSorted(String.compare)

let write = (text, pin) =>
  places(text)->Result.flatMap(((version, hashes)) =>
    hashes->Dict.keysToArray->sorted != pin.hashes->Dict.keysToArray->sorted
      ? Error(
          `the pin's architectures, ${pin.hashes
            ->Dict.keysToArray
            ->sorted
            ->Array.join(", ")}, are not the file's, ${hashes
            ->Dict.keysToArray
            ->sorted
            ->Array.join(", ")}`,
        )
      : Ok(
          [
            (version, pin.version),
            ...hashes
            ->Dict.toArray
            ->Array.map(((architecture, span)) => (span, pin.hashes->Dict.getUnsafe(architecture))),
          ]
          // The last place first, so each earlier one still lies where it was found.
          ->Array.toSorted(((a, _), (b, _)) => Int.toFloat(b.start - a.start))
          ->Array.reduce(text, (text, ({start, end}, value)) =>
            text->String.slice(~start=0, ~end=start) ++ value ++ text->String.slice(~start=end)
          ),
        )
  )

let follows = text =>
  once(
    `\\bnixpkgs\\.url = "github:NixOS/nixpkgs/(nixos-\\d\\d\\.\\d\\d)";`,
    text,
    ~what="nixpkgs input on a NixOS release branch",
  )->Result.map(m =>
    switch m->RegExp.Result.matches {
    | [Some(branch)] => branch
    | _ => ""
    }
  )

let release = (heads, ~follows) =>
  all(~flags="gm", `refs/heads/(nixos-\\d\\d\\.\\d\\d)$`, heads->String.replaceAll("\r", ""))
  ->Array.filterMap(m => m->RegExp.Result.matches->Array.at(0)->Option.flatMap(x => x))
  ->Array.reduce(follows, (newest, branch) => branch > newest ? branch : newest)
  ->(newest => newest == follows ? None : Some(newest))
