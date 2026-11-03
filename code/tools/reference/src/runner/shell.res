let quote = text => "'" ++ text->String.replaceAll("'", "'\\''") ++ "'"

let remote = (target, command) =>
  [
    "-o",
    "ServerAliveInterval=15",
    "-o",
    "ServerAliveCountMax=4",
    ...Conform.Remote.apart(Conform.Remote.target(Target.name(target)), command),
  ]

let request = (~app, ~binding, {method, path, body}: Steps.request) => {
  let host = `${Ids.Id.text(app)}.b${Ids.Id.text(binding)}`
  let data = body->Option.mapOr("", _ => " --data-binary @-")
  `${Conform.Live.entered}curl -sS -m 10 -w '\\n%{http_code}' -X ${quote(method)} -H ${quote(
      `Host: ${host}`,
    )}${data} "http://$e${path}"\n`
}

let app = output =>
  output
  ->String.split("\n")
  ->Array.findMap(line =>
    line->String.startsWith("deploy: app ") ? Ids.Id.ofText(line->String.slice(~start=12)) : None
  )

let drawn = output =>
  output
  ->String.split("\n")
  ->Array.findMap(line =>
    switch /^deploy: app [0-9.]+s, ([0-9a-f]{8}), /->RegExp.exec(line) {
    | None => None
    | Some(found) =>
      switch found->RegExp.Result.matches {
      | [Some(id)] => Ids.Id.ofText(id)
      | _ => None
      }
    }
  )

let deployArgs = (~directory, ~target, ~app, ~dry) =>
  [
    "code/tools/deploy/src/main.res.mjs",
    directory,
    Target.name(target),
    ...app->Option.mapOr([], id => ["--app", Ids.Id.text(id)]),
    ...dry ? ["--dry-run"] : [],
  ]
