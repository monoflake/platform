/***
 * A host faked behind a reach, its driver keeping a list and deployments as `deployments` and
 * `management` write them, and its entry answering by the host a request names.
 */
module Contracts = Envelope.Contracts

type seen = {url: string, authorization: option<string>, host: option<string>}

// The entry faked chooses by `X-Forwarded-Host` before `Host`, as the gateway asks of the real one.

type t = {
  reach: Reach.t,
  seen: array<seen>,
  /** Whether a container asked is answered making once before it is made. */
  slow: ref<bool>,
  /** Whether nothing answers at all. */
  gone: ref<bool>,
  /** The last deploy sent. */
  deployed: ref<option<Contracts.DeploymentDeploy.t>>,
}

let json = (status, value) =>
  Web.answered(~status, ~contentType="application/json", JSON.stringify(value))

let success = data => json(200, JSON.Object(dict{"status": String("success"), "data": data}))

let make = (): t => {
  let items: array<Contracts.ManagementHolding.t> = []
  let generation = ref(0.)
  let running: dict<Contracts.DeploymentDescribed.t> = dict{}
  let seen = []
  let slow = ref(false)
  let gone = ref(false)
  let deployed = ref(None)
  {
    reach: {
      origin: (~address, ~port) => `http://${address}:${Int.toString(port)}`,
      fetch: async request => {
        let headers = request->Web.requestHeaders
        let header = name => headers->Web.header(name)->Nullable.toOption
        seen->Array.push({
          url: request->Web.url,
          authorization: header("authorization"),
          host: header("host"),
        })
        if gone.contents {
          JsError.throwWithMessage("connection refused")
        }
        let path = Web.parts(request->Web.url)->Web.pathname
        let input = async () =>
          JSON.parseOrThrow(Web.fromUtf8(await request->Web.bytesOf))
          ->JSON.Decode.object
          ->Option.flatMap(o => o->Dict.get("input"))
          ->Option.getOr(JSON.Null)
        switch path {
        | "/management/describe" =>
          let described: Contracts.ManagementDescribed.t = {
            generation: generation.contents,
            policy: 0.,
            grace: 0.,
            items: items->Array.copy,
          }
          items->Array.forEachWithIndex((i, at) =>
            switch i.state {
            | Making => items->Array.set(at, {...i, state: Made({address: "10.0.0.2"})})
            | Made(_) | Failed(_) | Unasked(_) => ()
            }
          )
          success(Contracts.ManagementDescribed.toJson(described))
        | "/management/apply" =>
          switch Contracts.ManagementApply.fromJson(await input()) {
          | Ok(list) =>
            generation := list.generation
            list.items->Array.forEach(i =>
              items->Array.push({
                id: i.id,
                capacity: i.capacity,
                state: slow.contents ? Making : Made({address: "10.0.0.2"}),
              })
            )
            success(Contracts.ManagementHeld.toJson({generation: list.generation}))
          | Error(_) => json(400, JSON.Null)
          }
        | "/deployments/deploy" =>
          switch Contracts.DeploymentDeploy.fromJson(await input()) {
          | Ok(d) =>
            let described: Contracts.DeploymentDescribed.t = {
              runs: d.runs,
              version: d.version,
              state: Running({address: "10.0.0.2:8080", runtime: Workerd, isolation: [Isolate]}),
            }
            running->Dict.set("app", described)
            deployed := Some(d)
            success(Contracts.DeploymentDescribed.toJson(described))
          | Error(_) => json(400, JSON.Null)
          }
        | "/deployments/describe" =>
          switch running->Dict.get("app") {
          | Some(described) => success(Contracts.DeploymentDescribed.toJson(described))
          | None =>
            json(
              404,
              JSON.parseOrThrow(`{"status": "error", "failure": "rejected", "reason": "not_found", "message": "none"}`),
            )
          }
        | _ =>
          Web.answered(
            ~status=200,
            `entry asked ${path} for ${header("x-forwarded-host")
              ->Option.orElse(header("host"))
              ->Option.getOr("")}`,
          )
        }
      },
    },
    seen,
    slow,
    gone,
    deployed,
  }
}
