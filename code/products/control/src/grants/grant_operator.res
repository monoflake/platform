module C = Envelope.Contracts

let unknown = (answer: Serve.Calls.answer) =>
  switch answer {
  | Refused({reason}) => Grant_lease.ambiguous(reason)
  | Output(_) => false
  }

// An app with no head has no grant, so it takes no lease and no deadline.
let run = async (~context: option<Grant_context.t>, ~app, ~digest=?, operation) => {
  let free = () => operation(~mutate=async () => (), ~held=false)
  switch (context, app) {
  | (None, _) | (_, None) => await free()
  | (Some(t), Some(app)) =>
    switch (await t.state.deployment(app), await Grant_store.head(t.store, app)) {
    | (None, _) | (_, None) => await free()
    | (Some(d), Some(_)) =>
      ignore(await Grant_lease.reconcile(t, app, ~override=true))
      switch await Grant_store.head(t.store, app) {
      | None => await free()
      | Some(head) =>
        let candidate = JSON.stringify(C.DeploymentCandidate.toJson(Grant_context.emptyCandidate))
        let token = Grant_lease.encode(
          {
            at: t.store.now(),
            grant: "",
            digest: digest->Option.getOr(d.release),
            candidate,
            ingress: Grant_archive.ingressText(d.ingress),
            size: 0.,
          },
          ~nonce=Envelope.Base64url.encode(t.random(16)),
        )
        if !(await Grant_store.lock(t.store, app, head.version, token)) {
          Serve.Calls.Refused({reason: "denied", message: None})
        } else {
          let mutated = ref(false)
          let mutate = async () =>
            if !mutated.contents {
              mutated := true
              if !(await Grant_store.bump(t.store, ~app, ~token, ~candidate)) {
                JsError.throwWithMessage("the operator's intent is no longer held")
              }
            }
          // Past its version bump only a definite answer clears the intent.
          switch await operation(~mutate, ~held=true) {
          | answer =>
            if !(mutated.contents && unknown(answer)) {
              await Grant_store.releaseLock(t.store, app, token)
            }
            answer
          | exception JsExn(_) if mutated.contents => Grant_lease.unavailable
          | exception JsExn(error) =>
            await Grant_store.releaseLock(t.store, app, token)
            throw(JsExn(error))
          }
        }
      }
    }
  }
}

// The driver calls of one operator operation, ended together before its lease.
let bounded = (reach: Reach.t, direct: Web.fetch) => {
  let signal = Web.deadline(Grant_lease.deadline)
  let within = (fetch: Web.fetch): Web.fetch =>
    request => fetch(Web.withSignal(request, {signal: signal}))
  ({...reach, fetch: within(reach.fetch)}, within(direct))
}
