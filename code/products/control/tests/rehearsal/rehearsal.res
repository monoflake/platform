open Node
module Life = Lifecycle

let startupMs = 60_000
let runMs = 180_000

let quiet = () => {
  let given = Dict.copy(env)
  given->Dict.set("WRANGLER_SEND_METRICS", "false")
  given->Dict.set("CI", "1")
  given->Dict.set("CLOUDFLARE_CF_FETCH_ENABLED", "false")
  ["CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"]->Array.forEach(k => given->Dict.delete(k))
  given
}

let freePort = async () => {
  let (server, port) = await listening((_, _) => ())
  await shut(server)
  port
}

let bounded = async (ms, message, work) => {
  let timer = ref(None)
  let expired = Promise.make((_, reject) => {
    timer := Some(Life.later(() => reject(Life.error(message())), ms))
  })
  let clear = () => timer.contents->Option.forEach(Life.cancel)
  try {
    let answer = await Promise.race([work(), expired])
    clear()
    answer
  } catch {
  | e =>
    clear()
    throw(e)
  }
}

type process = {
  child: child,
  ended: ref<bool>,
  done: promise<unit>,
  failed: ref<bool>,
  output: ref<string>,
}
type t = {
  processes: array<process>,
  cleanups: array<unit => promise<unit>>,
  controller: Life.controller,
  closed: ref<bool>,
  stage: ref<string>,
}

let active = scope => {
  if scope.closed.contents {
    JsError.throwWithMessage("rehearsal has ended")
  }
}

let start = (scope, ~program, ~args, ~cwd) => {
  active(scope)
  let child = Life.spawn(
    program,
    args,
    {cwd, env: quiet(), stdio: ["ignore", "pipe", "pipe"], detached: true},
  )
  let ended = ref(false)
  let failed = ref(false)
  let done = Promise.make((resolve, _) => {
    child->onExit(() => {
      ended := true
      resolve()
    })
    child->Life.onError(_ => {
      failed := true
      ended := true
      resolve()
    })
  })
  let output = ref("")
  let keep = bytes =>
    output := `${output.contents}${Web.fromUtf8(bytes)}`->String.slice(~start=-16_384)
  child->stdout->onText(keep)
  child->stderr->onText(keep)
  let process = {child, ended, done, failed, output}
  scope.processes->Array.push(process)
  process
}

let signal = (process, signal) => {
  switch process.child->Life.pid->Nullable.toOption {
  | Some(pid) =>
    try Life.kill(-pid, signal) catch {
    | JsExn(_) => ()
    }
  | None => ()
  }
}

let stop = async process => {
  signal(process, "SIGTERM")
  await Web.sleep(500)
  signal(process, "SIGKILL")
  try {
    await bounded(2_000, () => "child did not exit after SIGKILL", () => process.done)
  } catch {
  | JsExn(_) => ()
  }
}

let using = async (~timeout=runMs, work) => {
  let scope = {
    processes: [],
    cleanups: [],
    controller: Life.controller(),
    closed: ref(false),
    stage: ref("setup"),
  }
  let finished = async () => {
    scope.closed := true
    scope.controller->Life.abort
    (await Promise.all(scope.processes->Array.map(stop)))->ignore

    (
      await Promise.all(
        scope.cleanups->Array.map(async clean => {
          try await clean() catch {
          | JsExn(_) => ()
          }
        }),
      )
    )->ignore
  }
  try {
    await bounded(
      timeout,
      () => `rehearsal exceeded ${Int.toString(timeout)} ms during ${scope.stage.contents}`,
      () => work(scope),
    )
    await finished()
  } catch {
  | e =>
    await finished()
    throw(e)
  }
}

let scratch = scope => {
  active(scope)
  let path = mkdtemp(join([tmpdir(), "rehearsal-"]))
  scope.cleanups->Array.push(async () => rm(path, {recursive: true, force: true}))
  path
}

let listening = async (scope, handler) => {
  active(scope)
  let server = createServer(handler)
  scope.cleanups->Array.push(() => shut(server))
  await Promise.make((resolve, _) => server->listen(0, "127.0.0.1", () => resolve()))
  (server, (server->address).port)
}

let fetch = (scope, request) => {
  active(scope)
  Life.fetch(request, {signal: Life.any([scope.controller->Life.signal, Web.deadline(5_000)])})
}

let ran = async (scope, program, args, ~cwd) => {
  scope.stage := program
  let process = start(scope, ~program, ~args, ~cwd)
  await process.done
  if process.failed.contents || process.child->Life.exitCode->Nullable.toOption != Some(0) {
    JsError.throwWithMessage(`${program} failed ${process.output.contents}`)
  }
}

let answering = async (scope, ~name, ~timeout=startupMs, ~process=?, url) => {
  scope.stage := `${name} Worker did not answer at ${url}`
  await bounded(
    timeout,
    () => `${name} Worker did not answer within ${Int.toString(timeout)} ms at ${url}`,
    async () => {
      let answered = ref(false)
      while !answered.contents && !scope.closed.contents {
        if process->Option.mapOr(false, p => p.ended.contents) {
          JsError.throwWithMessage(
            `${name} Worker exited before answering at ${url}${process->Option.mapOr("", p =>
                p.output.contents
              )}`,
          )
        }
        try {
          let response = await fetch(scope, Web.request(url, {method: "GET", headers: dict{}}))
          (await response->Web.responseBytes)->ignore
          answered := true
        } catch {
        | JsExn(_) => await Web.sleep(250)
        }
      }
      active(scope)
    },
  )
}

let dev = async (scope, ~name, ~program, ~args, ~cwd, ~url) => {
  let inspector = await freePort()
  let process = start(
    scope,
    ~program,
    ~args=Array.concat(args, ["--inspector-port", Int.toString(inspector), "--local"]),
    ~cwd,
  )
  await answering(scope, ~name, ~process, url)
}
