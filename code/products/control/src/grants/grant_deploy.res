module C = Envelope.Contracts
module Context = Grant_context
module Calls = Serve.Calls

let refused = reason => Calls.Refused({reason, message: None})
let denied = refused("denied")
let sha = /^[0-9a-f]{40}$/
let candidateValid = (c: C.DeploymentCandidate.t) =>
  [c.platform, c.cloud, c.driver, c.machine]->Array.every(s => sha->RegExp.test(s))

// Settled clears the intent, Open leaves it for a later reconcile since the driver may have acted.
type outcome = Settled(Calls.answer) | Open(Calls.answer)

let ranAs = async (
  t: Context.t,
  app,
  expected,
  token,
  lease,
  bytes,
  input: C.DeploymentGrantDeploy.t,
) =>
  switch await Grant_lease.record(t, app, expected, token, lease, ~bytes) {
  | exception JsExn(_) => Open(Grant_lease.unavailable)
  | false => Settled(refused("stale"))
  | true =>
    Settled(
      Calls.Output(
        Calls.output(
          (
            {
              app,
              digest: input.digest,
              version: expected +. 1.,
              candidate: input.candidate,
            }: C.DeploymentGrantDescribed.t
          ),
          ~toJson=C.DeploymentGrantDescribed.toJson,
          ~toCbor=C.DeploymentGrantDescribed.toCbor,
        ),
      ),
    )
  }

let committed = async (t: Context.t, proof, input: C.DeploymentGrantDeploy.t, bytes, token) => {
  let digest = Envelope.Hex.encode(input.digest)
  switch await Context.verified(t, proof) {
  | None => Settled(denied)
  | Some(row) =>
    switch await Context.fixed(t, row) {
    | None => Settled(denied)
    | Some((d, b)) =>
      if !(await Context.initialized(t, d, b)) {
        Settled(refused("unbound"))
      } else if !Grant_archive.valid(bytes, ~ingress=Grant_archive.ingressText(d.ingress)) {
        Settled(refused("invalid"))
      } else {
        let lease: Grant_lease.t = {
          at: t.store.now(),
          grant: row.grant,
          digest,
          candidate: JSON.stringify(C.DeploymentCandidate.toJson(input.candidate)),
          ingress: Grant_archive.ingressText(d.ingress),
          size: Int.toFloat(bytes->TypedArray.length),
        }
        let held = token.contents
        let next = Grant_lease.encode(lease, ~nonce=held)
        if !(await Grant_lease.compatible(t, Grant_lease.release(lease))) {
          Settled(refused("invalid"))
        } else if !(await Grant_store.claim(t.store, d.app, held, next)) {
          Settled(refused("stale"))
        } else {
          token := next
          switch Context.host(t, b) {
          | None => Settled(refused("unbound"))
          | Some(host) =>
            // Authority and staging are checked at the dispatch boundary.
            switch (
              await Context.verified(t, proof),
              await Grant_store.staged(t.store, row.grant, digest),
            ) {
            | (None, _) => Settled(denied)
            | (_, None) => Settled(refused("not_found"))
            | (_, Some(s)) if s.expires <= t.store.now() => Settled(refused("not_found"))
            | (Some(_), Some(s)) =>
              let deployment = Deploying.deploy(
                ~app=d.app,
                ~hash=input.digest,
                ~form=Modules,
                ~address=`${t.origin}/artifacts/${Context.stagingKey(
                    row.grant,
                    digest,
                  )}/${s.token}`,
                // RFC fkwf2, the runner keeps the secrets.
                ~secrets=None,
                ~network=[Http],
                ~ingress=d.ingress,
                ~into=?d.capacity == 0. ? None : Some(d.capacity),
              )
              let envelope = C.Interface.Deployments.toJson({
                call: Deploy(deployment),
                capabilities: [],
              })
              switch await Driver.call(
                Grant_lease.host(host),
                envelope,
                C.DeploymentDescribed.fromJson,
              ) {
              | exception JsExn(_) => Open(Grant_lease.unavailable)
              | Error({reason: "fault"}) => Open(Grant_lease.unavailable)
              | Error({reason}) if Grant_lease.ambiguous(reason) => Open(refused(reason))
              | Error({reason}) => Settled(refused(reason))
              | Ok(answer)
                if answer.runs != C.DeploymentRuns.App({id: d.app}) ||
                  !Access.equal(answer.version, input.digest) =>
                Settled(refused("invalid"))
              | Ok({state: Running(_)}) =>
                await ranAs(t, d.app, input.expected, next, lease, bytes, input)
              | Ok({state: Making}) => Open(Grant_lease.unavailable)
              | Ok({state: Stopped | Failed(_)}) => Settled(refused("invalid"))
              }
            }
          }
        }
      }
    }
  }
}

let deploy = async (t: Context.t, proof, input: C.DeploymentGrantDeploy.t) =>
  switch await Context.verified(t, proof) {
  | None => denied
  | Some(row) =>
    switch await Context.fixed(t, row) {
    | None => denied
    | Some((d, b)) =>
      if !(await Grant_lease.reconcile(t, d.app)) {
        Grant_lease.unavailable
      } else if (
        // A replay after its recorded deploy finds its staging gone, and is still stale.
        (await Grant_store.head(t.store, d.app))->Option.mapOr(false, head =>
          head.version != input.expected
        )
      ) {
        refused("stale")
      } else {
        let digest = Envelope.Hex.encode(input.digest)
        let staged = await Grant_store.staged(t.store, row.grant, digest)
        let served =
          staged->Option.isSome
            ? await t.artifacts.served(Context.stagingKey(row.grant, digest))
            : None
        switch served {
        | None => refused("not_found")
        | Some(served) =>
          let bytes = await Web.responseBytes(served)
          if !Grant_archive.valid(bytes, ~ingress=Grant_archive.ingressText(d.ingress)) {
            refused("invalid")
          } else if !(await Context.initialized(t, d, b)) {
            refused("unbound")
          } else if staged->Option.mapOr(true, s => s.expires <= t.store.now()) {
            refused("not_found")
          } else if (
            bytes->TypedArray.length > 33554432 ||
            staged->Option.mapOr(true, s => s.size != Int.toFloat(bytes->TypedArray.length)) ||
            !candidateValid(input.candidate) ||
            !Access.equal(await Web.sha256(bytes), input.digest)
          ) {
            refused("invalid")
          } else {
            let token = ref(Grant_lease.pending(t, Envelope.Base64url.encode(t.random(16))))
            if !(await Grant_store.lock(t.store, d.app, input.expected, token.contents)) {
              refused("stale")
            } else {
              // Nothing past the driver call throws, so what throws here preceded any effect.
              switch await committed(t, proof, input, bytes, token) {
              | Settled(answer) =>
                await Grant_store.releaseLock(t.store, d.app, token.contents)
                answer
              | Open(answer) => answer
              | exception JsExn(error) =>
                await Grant_store.releaseLock(t.store, d.app, token.contents)
                throw(JsExn(error))
              }
            }
          }
        }
      }
    }
  }
