/***
 * Capabilities by name, type and rule, RFCs 49qyg and kd7f9, a need compared with what is held
 * capability by capability, every failure kept.
 */

type value =
  | Flag(bool)
  | Amount(float)
  | One(string)
  | Subset(array<string>)

type type_ = [
  | #flag
  | #amount
  | #one(array<string>)
  | #some(array<string>)
  | #amounts(array<string>)
]

type entry = {name: string, type_: type_, default: value}

type t = array<entry>

type malformed =
  | Name(string)
  | Repeated(string)
  | Default(string)

/** Whether a name is one, lowercase ASCII letters, digits and hyphens and not empty. */
let named = name => /^[a-z0-9-]+$/->RegExp.test(name)

/** Whether an amount is an integer of 0 to 2^53 - 1, as `uint53` is. */
let counted = n => n >= 0. && n <= 9007199254740991. && Math.floor(n) == n

let within = (values, members) => values->Array.every(v => members->Array.includes(v))

/** The first member repeated, if one is. */
let repeat = members => members->Array.findWithIndex((m, at) => members->Array.indexOf(m) != at)

let membersOf = (type_: type_) =>
  switch type_ {
  | #flag | #amount => []
  | #one(members) | #some(members) | #amounts(members) => members
  }

/** Whether a default is of its type, a one of a set's the members held against it. */
let ofType = (type_: type_, default) =>
  switch (type_, default) {
  | (#flag, Flag(_)) => true
  | (#amount | #amounts(_), Amount(n)) => counted(n)
  | (#one(members) | #some(members), Subset(values)) => within(values, members)
  | (#flag, Amount(_) | One(_) | Subset(_))
  | (#amount | #amounts(_), Flag(_) | One(_) | Subset(_))
  | (#one(_) | #some(_), Flag(_) | Amount(_) | One(_)) => false
  }

let make = entries => {
  let seen = []
  let refused = entries->Array.findMap(e =>
    if !named(e.name) {
      Some(Name(e.name))
    } else if seen->Array.includes(e.name) {
      Some(Repeated(e.name))
    } else {
      seen->Array.push(e.name)
      let members = membersOf(e.type_)
      switch (members->Array.find(m => !named(m)), repeat(members)) {
      | (Some(m), _) => Some(Name(m))
      | (None, Some(m)) => Some(Repeated(m))
      | (None, None) => ofType(e.type_, e.default) ? None : Some(Default(e.name))
      }
    }
  )
  switch refused {
  | Some(malformed) => Error(malformed)
  | None => Ok(entries)
  }
}

let entries = vocabulary => vocabulary

/** A value as `allowance-value` writes it in JSON, by its `name`. */
let valueOf = json => {
  let o = json->JSON.Decode.object
  let get = k => o->Option.flatMap(o => o->Dict.get(k))
  switch get("name")->Option.flatMap(JSON.Decode.string) {
  | Some("flag") => get("value")->Option.flatMap(JSON.Decode.bool)->Option.map(b => Flag(b))
  | Some("amount") => get("value")->Option.flatMap(JSON.Decode.float)->Option.map(n => Amount(n))
  | Some("one") => get("value")->Option.flatMap(JSON.Decode.string)->Option.map(s => One(s))
  | Some("some") =>
    get("values")
    ->Option.flatMap(JSON.Decode.array)
    ->Option.flatMap(xs => {
      let values = xs->Array.filterMap(JSON.Decode.string)
      values->Array.length == xs->Array.length ? Some(Subset(values)) : None
    })
  | Some(_) | None => None
  }
}

/** An entry as the product writes it, its type by name and its members where it has a set. */
let entryOf = json => {
  let o = json->JSON.Decode.object
  let get = k => o->Option.flatMap(o => o->Dict.get(k))
  let members =
    get("members")
    ->Option.flatMap(JSON.Decode.array)
    ->Option.map(xs => xs->Array.filterMap(JSON.Decode.string))
  let type_: option<type_> = switch (get("type")->Option.flatMap(JSON.Decode.string), members) {
  | (Some("flag"), None) => Some(#flag)
  | (Some("amount"), None) => Some(#amount)
  | (Some("one"), Some(m)) => Some(#one(m))
  | (Some("some"), Some(m)) => Some(#some(m))
  | (Some("amounts"), Some(m)) => Some(#amounts(m))
  | _ => None
  }
  switch (
    get("name")->Option.flatMap(JSON.Decode.string),
    type_,
    get("default")->Option.flatMap(valueOf),
  ) {
  | (Some(name), Some(type_), Some(default)) => Some({name, type_, default})
  | _ => None
  }
}

/** The product's vocabulary, which its check holds well formed, so reading it cannot fail. */
let model = {
  let written =
    Contracts.contracts
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("vocabulary"))
    ->Option.flatMap(JSON.Decode.array)
    ->Option.getOr([])
  let read = written->Array.filterMap(entryOf)
  switch (read->Array.length == written->Array.length, make(read)) {
  | (true, Ok(vocabulary)) => vocabulary
  | (false, _) | (true, Error(_)) =>
    JsError.throwWithMessage("model/contracts.json: its vocabulary is not as the model writes it")
  }
}

type side = Need | Held

/** The key a group's member is held at, RFC b194m. */
let memberKey = (group, member) => `${group}.${member}`

let filled = (vocabulary, side, values) => {
  let filled = values->Dict.copy
  let fill = (key, default) =>
    if filled->Dict.get(key) == None {
      filled->Dict.set(key, default)
    }
  vocabulary->Array.forEach(e =>
    switch (e.type_, side) {
    // A need's one of a set takes no default, RFC b194m.
    | (#one(_), Need) => ()
    | (#amounts(members), Need | Held) =>
      members->Array.forEach(m => fill(memberKey(e.name, m), e.default))
    | (#flag | #amount | #one(_) | #some(_), Need | Held) => fill(e.name, e.default)
    }
  )
  filled
}

type failure =
  | Unknown(string)
  | Mistyped({name: string, side: side})
  | Exceeds({name: string, need: value, held: value})

/** A capability compared by its own rule, a type a group's member's key stands for. */
type rule = Yes | Most | Member(array<string>) | Within(array<string>)

/** A need's value as its rule asks, or none where it is mistyped. */
let asNeeded = (rule, value) =>
  switch (rule, value) {
  | (Yes, Flag(_)) => Some(value)
  | (Most, Amount(n)) if counted(n) => Some(value)
  | (Member(members), One(m)) if members->Array.includes(m) => Some(value)
  | (Within(members), Subset(values)) if within(values, members) => Some(value)
  | (Yes | Most | Member(_) | Within(_), Flag(_) | Amount(_) | One(_) | Subset(_)) => None
  }

/** A held value as its rule reads it, members it does not know passed over, RFC b194m. */
let asHeld = (rule, value) =>
  switch (rule, value) {
  | (Yes, Flag(_)) => Some(value)
  | (Most, Amount(n)) if counted(n) => Some(value)
  | (Member(members) | Within(members), Subset(values)) =>
    Some(Subset(values->Array.filter(v => members->Array.includes(v))))
  | (Yes | Most | Member(_) | Within(_), Flag(_) | Amount(_) | One(_) | Subset(_)) => None
  }

/** Whether a need is within what is held, both read by their rule. */
let holds = (need, held) =>
  switch (need, held) {
  | (Flag(needed), Flag(given)) => !needed || given
  | (Amount(needed), Amount(given)) => needed <= given
  | (One(m), Subset(given)) => given->Array.includes(m)
  | (Subset(needed), Subset(given)) => within(needed, given)
  | (Flag(_) | Amount(_) | One(_) | Subset(_), _) => false
  }

/** Every key the vocabulary compares, with its rule. */
let keys = vocabulary =>
  vocabulary->Array.flatMap(e =>
    switch e.type_ {
    | #flag => [(e.name, Yes)]
    | #amount => [(e.name, Most)]
    | #one(members) => [(e.name, Member(members))]
    | #some(members) => [(e.name, Within(members))]
    | #amounts(members) => members->Array.map(m => (memberKey(e.name, m), Most))
    }
  )

let nameOf = failure =>
  switch failure {
  | Unknown(name) | Mistyped({name}) | Exceeds({name}) => name
  }

let compare = (vocabulary, need, held) => {
  let need = filled(vocabulary, Need, need)
  let held = filled(vocabulary, Held, held)
  let compared = keys(vocabulary)
  // A group's own name holds no value, its members do.
  let groups = vocabulary->Array.filterMap(e =>
    switch e.type_ {
    | #amounts(_) => Some(e.name)
    | #flag | #amount | #one(_) | #some(_) => None
    }
  )
  let failed = compared->Array.filterMap(((key, rule)) =>
    switch (need->Dict.get(key), held->Dict.get(key)) {
    | (None, _) => None
    | (Some(n), h) =>
      switch (asNeeded(rule, n), h->Option.flatMap(h => asHeld(rule, h))) {
      | (None, _) => Some(Mistyped({name: key, side: Need}))
      | (Some(_), None) => Some(Mistyped({name: key, side: Held}))
      | (Some(n), Some(h)) => holds(n, h) ? None : Some(Exceeds({name: key, need: n, held: h}))
      }
    }
  )
  let groupsMistyped = groups->Array.filterMap(g =>
    switch (need->Dict.get(g), held->Dict.get(g)) {
    | (Some(_), _) => Some(Mistyped({name: g, side: Need}))
    | (None, Some(_)) => Some(Mistyped({name: g, side: Held}))
    | (None, None) => None
    }
  )
  let unknown =
    need
    ->Dict.keysToArray
    ->Array.filter(k =>
      !(compared->Array.some(((key, _)) => key == k)) && !(groups->Array.includes(k))
    )
    ->Array.map(k => Unknown(k))
  switch Array.concatMany(failed, [groupsMistyped, unknown]) {
  | [] => Ok()
  | failures => Error(failures->Array.toSorted((a, b) => String.compare(nameOf(a), nameOf(b))))
  }
}

let fits = (vocabulary, ~need, ~allowance) => compare(vocabulary, need, allowance)

let meets = (vocabulary, ~need, ~offer) => compare(vocabulary, need, offer)
