open Node
module Life = Lifecycle

let thrown = async work =>
  switch await work() {
  | _ => None
  | exception JsExn(e) => e->JsExn.message
  }

let alive = process =>
  switch process.Rehearsal.child->Life.pid->Nullable.toOption {
  | None => false
  | Some(pid) =>
    try {
      Life.probe(pid)
      true
    } catch {
    | JsExn(_) => false
    }
  }

let started = (scope, script) =>
  Rehearsal.start(scope, ~program=Life.execPath, ~args=["-e", script], ~cwd=fromRoot(""))

test("a Worker that accepts requests without answering has a named startup bound", async () => {
  let before = Life.now()
  let why = await thrown(() =>
    Rehearsal.using(
      async scope => {
        let (_, port) = await Rehearsal.listening(scope, (_, _) => ())
        await Rehearsal.answering(
          scope,
          ~name="silent",
          ~timeout=100,
          `http://127.0.0.1:${Int.toString(port)}/`,
        )
      },
    )
  )
  ok(
    why->Option.mapOr(false, text =>
      text->String.includes("silent Worker did not answer within 100 ms")
    ),
  )
  ok(Life.now() -. before < 2_000.)
})

test("the whole run is bounded and kills every child even when SIGTERM is ignored", async () => {
  let processes = []
  let before = Life.now()
  let why = await thrown(() =>
    Rehearsal.using(
      ~timeout=400,
      async scope => {
        processes->Array.push(
          started(scope, "process.on('SIGTERM', () => {}); setInterval(() => {}, 1000)"),
        )
        processes->Array.push(started(scope, "setInterval(() => {}, 1000)"))
        await Web.sleep(700)
        started(scope, "setInterval(() => {}, 1000)")->ignore
      },
    )
  )
  ok(why->Option.mapOr(false, text => text->String.includes("rehearsal exceeded 400 ms")))
  ok(processes->Array.every(process => !alive(process)))
  ok(Life.now() -. before < 4_000.)
})

test("success, exceptions, spawn errors and children already exited all clean up", async () => {
  let processes = []
  await Rehearsal.using(async scope => {
    let process = started(scope, "process.exit(0)")
    processes->Array.push(process)
    await process.done
    processes->Array.push(started(scope, "setInterval(() => {}, 1000)"))
  })
  deepEqual(
    await thrown(() =>
      Rehearsal.using(
        async scope => {
          processes->Array.push(started(scope, "setInterval(() => {}, 1000)"))
          JsError.throwWithMessage("fixture failed")
        },
      )
    ),
    Some("fixture failed"),
  )
  let why = await thrown(() =>
    Rehearsal.using(
      async scope => {
        await Rehearsal.ran(scope, "/missing/rehearsal-command", [], ~cwd=fromRoot(""))
      },
    )
  )
  ok(why->Option.mapOr(false, text => text->String.includes("/missing/rehearsal-command failed")))
  ok(processes->Array.every(process => !alive(process)))
})

test("an exited Worker fails by name before the startup deadline", async () => {
  let why = await thrown(() =>
    Rehearsal.using(
      async scope => {
        let process = started(scope, "process.exit(1)")
        await process.done
        await Rehearsal.answering(scope, ~name="exited", ~process, "http://127.0.0.1:1/")
      },
    )
  )
  deepEqual(why, Some("exited Worker exited before answering at http://127.0.0.1:1/"))
})

test("cleanup kills a descendant after its launcher has already exited", async () => {
  let pid = ref(None)
  await Rehearsal.using(async scope => {
    let process = started(
      scope,
      "const {spawn} = require('node:child_process'); const child = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {stdio: 'ignore'}); console.log(child.pid); process.exit(0)",
    )
    process.child->stdout->onText(bytes => pid := Web.fromUtf8(bytes)->String.trim->Int.fromString)
    await process.done
    ok(pid.contents->Option.isSome)
  })
  let running = switch pid.contents {
  | None => false
  | Some(pid) =>
    try {
      Life.probe(pid)
      true
    } catch {
    | JsExn(_) => false
    }
  }
  ok(!running, ~message="the descendant survived its launcher's cleanup")
})
