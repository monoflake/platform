type options = {encoding: string, maxBuffer: int, timeout: int, input?: string}
type ran = {status: int, stdout: string, stderr: string}
@module("node:crypto") external unique: unit => string = "randomUUID"

type failed
@get external code: failed => JSON.t = "code"
@module("node:child_process")
external execFile: (
  string,
  array<string>,
  options,
  (Nullable.t<failed>, string, string) => unit,
) => Conform.Host.child = "execFile"

let run = (program, args, ~input=?) =>
  Promise.make((resolve, _) => {
    let child = execFile(program, args, {encoding: "utf8", maxBuffer: 4194304, timeout: 180000}, (
      failed,
      stdout,
      stderr,
    ) => {
      let status = switch failed->Nullable.toOption {
      | None => 0
      | Some(failed) => failed->code->JSON.Decode.float->Option.mapOr(1, Float.toInt)
      }
      resolve({status, stdout, stderr})
    })
    child->Conform.Host.stdin->Conform.Host.endWith(input->Option.getOr(""))
  })
