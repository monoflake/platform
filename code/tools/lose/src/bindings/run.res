/*** A program run without blocking, so the paths are asked side by side. */

/** How a program ended, its exit code, 1 where it ended by a signal, and what it wrote. */
type ran = {code: int, stdout: string, stderr: string}

type failed
type options = {encoding: string, maxBuffer: int}
@module("node:child_process")
external execFile: (
  string,
  array<string>,
  options,
  (Nullable.t<failed>, string, string) => unit,
) => unit = "execFile"
@get external codeOf: failed => JSON.t = "code"

/** A program run to its end. */
let run = (program, args) =>
  Promise.make((resolve, _) =>
    execFile(program, args, {encoding: "utf8", maxBuffer: 1048576}, (failed, stdout, stderr) => {
      let code = switch failed->Nullable.toOption {
      | None => 0
      | Some(failed) => failed->codeOf->JSON.Decode.float->Option.mapOr(1, Float.toInt)
      }
      resolve({code, stdout, stderr})
    })
  )
