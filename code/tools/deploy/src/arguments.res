/*** The deploy tool's arguments read, each id 8 lowercase hex digits, RFC b8f35. */
module Contracts = Envelope.Contracts

let usage = "deploy <app directory> <target> [--app <8 hex>] [--binding <8 hex>] [--component storage|compute --organization <8 hex>] [--secrets <A,B>] [--network <http,tcp>] [--ingress <domain:name|mount:scope|binding>]... [--dry-run], or deploy <control target> --forget <8 hex> [--dry-run], or deploy <target> --retire <8 hex> [--dry-run]"

/**
 * The arguments, the app's directory, the target, the app redeployed, the binding a control deploys
 * it onto, the app a control forgets or retires, the secrets and network it hands the driver, and
 * whether nothing is changed.
 */
type t = {
  directory: string,
  target: string,
  app: option<float>,
  binding: option<float>,
  forget: option<float>,
  retire: option<float>,
  secrets: array<string>,
  network: array<Contracts.DeploymentNetwork.t>,
  ingress: option<array<Contracts.AppIngress.t>>,
  component: option<string>,
  organization: option<float>,
  dry: bool,
}

/** A comma's list, its empty entries passed over. */
let listed = text => text->String.split(",")->Array.map(String.trim)->Array.filter(s => s != "")

/** A secret's name, as an environment variable writes it. */
let secretName = /^[A-Z][A-Z0-9_]*$/

let networkOf = name =>
  switch name {
  | "http" => Some(Contracts.DeploymentNetwork.Http)
  | "tcp" => Some(Tcp)
  | "udp" => Some(Udp)
  | "icmp" => Some(Icmp)
  | _ => None
  }

// Domain validation follows the control's releases.put in parts/ingress.res.
let validDomain = domain => {
  let name = domain->String.startsWith("*.") ? domain->String.slice(~start=2) : domain
  let labels = name->String.split(".")
  String.length(domain) <= 253 &&
  labels->Array.length >= 2 &&
  !(/^[0-9]+$/->RegExp.test(labels->Array.at(-1)->Option.getOr(""))) &&
  labels->Array.every(label => /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/->RegExp.test(label))
}

// Scope validation follows the control's releases.put in parts/ingress.res.
let validScope = scope =>
  /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/->RegExp.test(scope) &&
    !(["compute", "storage", "database"]->Array.includes(scope))

let ingressOf = text => {
  let value = text->String.slice(~start=text->String.indexOf(":") + 1)
  if text == "binding" {
    Some(Contracts.AppIngress.Binding)
  } else if text->String.startsWith("domain:") && validDomain(value) {
    Some(Contracts.AppIngress.Domain({domain: value}))
  } else if text->String.startsWith("mount:") && validScope(value) {
    Some(Contracts.AppIngress.Mount({scope: value}))
  } else {
    None
  }
}

let rec read = (args, given) =>
  switch args {
  | list{"--dry-run", ...rest} => read(rest, {...given, dry: true})
  | list{"--ingress", text, ...rest} =>
    switch ingressOf(text) {
    | None => Error(`--ingress ${text} is no domain:<name>, mount:<scope> or binding`)
    | Some(ingress) =>
      read(rest, {...given, ingress: Some([...given.ingress->Option.getOr([]), ingress])})
    }
  | list{"--component", ("storage" | "compute") as component, ...rest} =>
    read(rest, {...given, component: Some(component)})
  | list{"--component", text, ..._} => Error(`--component ${text} is not storage or compute`)
  | list{"--secrets", text, ...rest} =>
    switch listed(text)->Array.find(n => !(secretName->RegExp.test(n))) {
    | Some(bad) => Error(`--secrets ${bad} is no secret's name`)
    | None => read(rest, {...given, secrets: listed(text)})
    }
  | list{"--network", text, ...rest} =>
    let kinds = listed(text)->Array.map(n => (n, networkOf(n)))
    switch kinds->Array.find(((_, kind)) => kind == None) {
    | Some((bad, _)) => Error(`--network ${bad} is none of http, tcp, udp and icmp`)
    | None => read(rest, {...given, network: kinds->Array.filterMap(((_, kind)) => kind)})
    }
  | list{flag, ..._} if flag->String.startsWith("--") => Error(`${flag} is no flag of ${usage}`)
  | list{named, ...rest} if given.directory == "" => read(rest, {...given, directory: named})
  | list{named, ...rest} if given.target == "" => read(rest, {...given, target: named})
  | list{named, ..._} => Error(`${named} is one argument too many`)
  | list{} => Ok(given)
  }

/**
 * What a forget or a retire takes, the target alone and a dry run, its one positional read as the
 * target, `flag` naming which.
 */
let controlOnly = (given: t, ~flag) =>
  switch (given.directory, given.target) {
  | ("", _) => Error(usage)
  | (_, more) if more != "" =>
    Error(`${more} is one argument too many, as --${flag} builds nothing`)
  | (named, _) if flag == "forget" && Control.origin(named) == None =>
    Error(`--${flag} asks a control, and ${named} is a machine ssh reaches`)
  | _
    if given.app != None ||
    given.binding != None ||
    given.secrets != [] ||
    given.network != [] ||
    given.component != None ||
    given.organization != None ||
    given.ingress != None =>
    Error(`--${flag} takes its target alone, and --dry-run`)
  | (named, _) => Ok({...given, directory: "", target: named})
  }

/** The arguments read, or why they are not a deploy's, a forget's or a retire's. */
let parse = args => {
  let ids =
    Ids.Id.taken(args, ~flag="app")->Result.flatMap(((app, rest)) =>
      Ids.Id.taken(rest, ~flag="binding")->Result.flatMap(((binding, rest)) =>
        Ids.Id.taken(rest, ~flag="forget")->Result.flatMap(
          ((forget, rest)) =>
            Ids.Id.taken(rest, ~flag="retire")->Result.flatMap(
              ((retire, rest)) =>
                Ids.Id.taken(rest, ~flag="organization")->Result.map(
                  ((organization, rest)) => (app, binding, forget, retire, organization, rest),
                ),
            ),
        )
      )
    )
  switch ids {
  | Error(why) => Error(why)
  | Ok((app, binding, forget, retire, organization, rest)) =>
    let empty = {
      directory: "",
      target: "",
      app,
      binding,
      forget,
      retire,
      secrets: [],
      network: [],
      ingress: None,
      component: None,
      organization: None,
      dry: false,
    }
    let empty = {...empty, organization}
    switch (read(List.fromArray(rest), empty), forget, retire) {
    | (Error(why), _, _) => Error(why)
    | (Ok(_), Some(_), Some(_)) => Error("--forget and --retire are two calls, made one at a time")
    | (Ok(given), Some(_), None) => controlOnly(given, ~flag="forget")
    | (Ok(given), None, Some(_)) => controlOnly(given, ~flag="retire")
    | (Ok({target: ""}), None, None) => Error(usage)
    | (Ok({organization: Some(_), component: None}), None, None) =>
      Error("--organization asks --component storage or --component compute")
    | (Ok({component: Some(component), organization: None}), None, None) =>
      Error(`--component ${component} asks --organization`)
    | (Ok({component: Some(component), app: _, target}), None, None)
      if Control.origin(target) != None =>
      Error(`--component ${component} is deployed to a machine, and a control target is not one`)
    | (Ok(given), None, None) => Ok(given)
    }
  }
}

let grant = args => {
  let values = dict{}
  let flags = ["expected-version", "platform", "cloud", "driver", "machine"]
  let rec take = (args, rest) =>
    switch args {
    | list{flag, value, ...tail} if flags->Array.includes(flag->String.slice(~start=2)) =>
      let name = flag->String.slice(~start=2)
      if !(flag->String.startsWith("--")) || values->Dict.has(name) {
        Error("grant deployment options are malformed or repeated")
      } else {
        values->Dict.set(name, value)
        take(tail, rest)
      }
    | list{flag, ..._}
      if [
        "--secrets",
        "--binding",
        "--app",
        "--forget",
        "--retire",
        "--network",
        "--ingress",
        "--component",
        "--organization",
      ]->Array.includes(flag) =>
      Error("grant deployment takes no policy or operator options")
    | list{value, ...tail} => take(tail, [...rest, value])
    | list{} => Ok(rest)
    }
  take(List.fromArray(args), [])
  ->Result.flatMap(rest =>
    parse(rest)->Result.mapError(_ => "grant deployment arguments are invalid")
  )
  ->Result.flatMap(given => {
    let value = name => values->Dict.get(name)->Option.getOr("")
    let expected = value("expected-version")
    let commits = ["platform", "cloud", "driver", "machine"]
    if Control.origin(given.target) == None {
      Error("grant deployment requires a control target")
    } else if !(commits->Array.every(name => /^[a-f0-9]{40}$/->RegExp.test(value(name)))) {
      Error("grant deployment requires --platform --cloud --driver --machine full lowercase SHAs")
    } else if !(/^(0|[1-9][0-9]*)$/->RegExp.test(expected)) {
      Error("grant deployment requires --expected-version as an unsigned safe integer")
    } else {
      switch Float.fromString(expected) {
      | Some(expected) if expected < 9007199254740991. =>
        let candidate: Contracts.DeploymentCandidate.t = {
          platform: value("platform"),
          cloud: value("cloud"),
          driver: value("driver"),
          machine: value("machine"),
        }
        Ok((given, expected, candidate))
      | Some(_) | None => Error("grant deployment expected version cannot be incremented safely")
      }
    }
  })
}
