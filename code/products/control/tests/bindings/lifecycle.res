open! Node
module Web = Web

type timer
@val external later: (unit => unit, int) => timer = "setTimeout"
@val external cancel: timer => unit = "clearTimeout"
@new external error: string => exn = "Error"
@val @scope("Date") external now: unit => float = "now"

type controller
@new external controller: unit => controller = "AbortController"
@get external signal: controller => Web.signal = "signal"
@send external abort: controller => unit = "abort"
@val @scope("AbortSignal") external any: array<Web.signal> => Web.signal = "any"
type fetchOptions = {signal: Web.signal}
@val external fetch: (Web.request, fetchOptions) => promise<Web.response> = "fetch"

type options = {cwd: string, env: dict<string>, stdio: array<string>, detached: bool}
@module("node:child_process")
external spawn: (string, array<string>, options) => Node.child = "spawn"
@get external pid: Node.child => Nullable.t<int> = "pid"
@get external exitCode: Node.child => Nullable.t<int> = "exitCode"
@send external onError: (Node.child, @as("error") _, exn => unit) => unit = "once"
@module("node:process") external kill: (int, string) => unit = "kill"

@module("node:process") external execPath: string = "execPath"
@module("node:process") external probe: (int, @as(0) _) => unit = "kill"
