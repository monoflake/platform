module Web = ControlOrganization.Web
module Reach = ControlOrganization.Reach

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
  /** How many of the next requests fail before any answer, as a connection closed would. */
  drops: ref<int>,
  /** A path whose every request fails before any answer, as a connection closed would. */
  cut: ref<option<string>>,
  /** The kinds the driver's describe answers it offers, none where it names none. */
  kinds: ref<option<array<Contracts.ManagementKind.t>>>,
  /** The last list applied. */
  applied: ref<option<Contracts.ManagementApply.t>>,
  /** The last deploy sent. */
  deployed: ref<option<Contracts.DeploymentDeploy.t>>,
  /** Whether the driver has lost what it ran, answering a stop and a delete `not_found`. */
  lost: ref<bool>,
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
  let drops = ref(0)
  let cut = ref(None)
  let kinds = ref(None)
  let applied = ref(None)
  let deployed = ref(None)
  let lost = ref(false)
  let notFound = () =>
    json(
      404,
      JSON.parseOrThrow(`{"status": "error", "failure": "rejected", "reason": "not_found", "message": "none"}`),
    )
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
        if drops.contents > 0 {
          drops := drops.contents - 1
          JsError.throwWithMessage("Network connection lost.")
        }
        let path = Web.parts(request->Web.url)->Web.pathname
        if cut.contents == Some(path) {
          JsError.throwWithMessage("Network connection lost.")
        }
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
            kinds: ?kinds.contents,
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
            applied := Some(list)
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
        | "/object/write" =>
          if (
            items->Array.some(i =>
              switch i.capacity {
              | Object(_) => true
              | Container(_) | Volume(_) | Database(_) => false
              }
            )
          ) {
            success(JSON.Object(dict{}))
          } else {
            json(
              503,
              JSON.parseOrThrow(`{"status": "error", "failure": "unavailable", "reason": "storage_full", "message": "the binding holds no bucket"}`),
            )
          }
        // A stop leaves the deployment stopped, and a delete refuses one still running.
        | "/deployments/stop" =>
          switch running->Dict.get("app") {
          | Some(described) if !lost.contents =>
            let stopped = {...described, state: Stopped}
            running->Dict.set("app", stopped)
            success(Contracts.DeploymentDescribed.toJson(stopped))
          | Some(_) | None => notFound()
          }
        | "/deployments/delete" if lost.contents => notFound()
        | "/deployments/delete" =>
          switch running->Dict.get("app") {
          | Some({state: Running(_)}) =>
            json(
              409,
              JSON.parseOrThrow(`{"status": "error", "failure": "rejected", "reason": "still_running", "message": "it runs"}`),
            )
          | Some({state: Making | Stopped | Failed(_)}) | None =>
            running->Dict.delete("app")
            success(Contracts.DeploymentDeleted.toJson({}))
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
    drops,
    cut,
    kinds,
    applied,
    deployed,
    lost,
  }
}
