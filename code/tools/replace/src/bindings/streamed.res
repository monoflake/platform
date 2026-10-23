/*** A program left running while what it writes is kept, and the code a fetch's failure carries. */

type child
type readable
type options = {stdio: array<string>}
@module("node:child_process")
external spawn: (string, array<string>, options) => child = "spawn"
@get external stdout: child => readable = "stdout"
@send external setEncoding: (readable, string) => unit = "setEncoding"
@send external onData: (readable, @as("data") _, string => unit) => unit = "on"
@send external onClose: (child, @as("close") _, Nullable.t<int> => unit) => unit = "on"

/** A program started, its stderr shown, and a promise of its exit code and all it wrote. */
let started = (program, args) => {
  let child = spawn(program, args, {stdio: ["ignore", "pipe", "inherit"]})
  let written = []
  child->stdout->setEncoding("utf8")
  child->stdout->onData(chunk => written->Array.push(chunk))
  Promise.make((resolve, _) =>
    child->onClose(code =>
      resolve((code->Nullable.toOption->Option.getOr(1), written->Array.join("")))
    )
  )
}

type cause
@get @return(nullable) external causeOf: JsExn.t => option<cause> = "cause"
@get @return(nullable) external codeOf: cause => option<string> = "code"

/** The code of what caused a fetch to throw, `ECONNREFUSED` for a connection refused. */
let code = e => e->causeOf->Option.flatMap(codeOf)
