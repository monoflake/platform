type t = Machine(string)

let name = (Machine(name)) => name

let ofName = name =>
  name != "" &&
  !(name->String.startsWith("-")) &&
  !(name->String.includes(":")) &&
  /^[A-Za-z0-9_.@-]+$/->RegExp.test(name)
    ? Ok(Machine(name))
    : Error("reference takes a machine target ssh reaches")

let parse = args =>
  switch args {
  | [name] => ofName(name)->Result.map(target => (target, false))
  | [name, "--dry-run"] => ofName(name)->Result.map(target => (target, true))
  | _ => Error("reference <target> [--dry-run]")
  }
