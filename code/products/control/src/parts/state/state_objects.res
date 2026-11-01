/***
 * The state kept as objects, one JSON document a record under `state/`, RFC rxmd9.
 */
open Records
open State_types

let bindingJson = (b: binding, sealed) => {
  let o = dict{
    "id": JSON.Number(b.id),
    "organization": Number(b.organization),
    "secret": String(sealed),
    "relayed": Boolean(b.relayed),
  }
  // Written even where none, so a record with no field at all is one kept before the order was.
  o->Dict.set("bound", b.bound->Option.mapOr(JSON.Null, n => JSON.Number(n)))
  b.tunnel->Option.forEach(t => o->Dict.set("tunnel", String(t)))
  b.address->Option.forEach(a => o->Dict.set("address", String(a)))
  b.origin->Option.forEach(a => o->Dict.set("origin", String(a)))
  JSON.Object(o)
}

let ofObjects = (objects: Objects.t, ~sealing) => {
  let readJson = async name =>
    held(await objects.read(name))->Option.map(bytes => JSON.parseOrThrow(Web.fromUtf8(bytes)))
  let writeJson = async (name, json) =>
    held(await objects.write(name, Web.utf8(JSON.stringify(json))))
  // A record is read by the id its path names, a document holding another id a fault.
  let record = async (name, id) =>
    switch await readJson(name) {
    | Some(json) if json->number("id") == Some(id) => Some(json)
    | Some(_) => JsError.throwWithMessage(`the record at ${name} holds another id than its path's`)
    | None => None
    }
  let idOf = name =>
    switch name
    ->String.split("/")
    ->Array.at(-1)
    ->Option.filter(last => /^[0-9]+$/->RegExp.test(last))
    ->Option.flatMap(Float.fromString) {
    | Some(id) => id
    | None => JsError.throwWithMessage(`the record at ${name} is named by no id`)
    }
  let every = async prefix =>
    (
      await Promise.all(
        held(await objects.list(prefix))->Array.map(async name => {
          let id = idOf(name)
          (await record(name, id))->Option.map(json => (id, json))
        }),
      )
    )->Array.filterMap(j => j)
  // Ids are given one at a time within a request, a state being built for each, RFC rxmd9.
  let queue = ref(Promise.resolve())
  let serial = f => {
    let run = queue.contents->Promise.then(() => f())
    queue := run->Promise.then(_ => Promise.resolve())->Promise.catch(_ => Promise.resolve())
    run
  }
  // The id after the greatest, counted on past every id an app or a binding holds.
  let rec past = async id =>
    switch await Promise.all([
      readJson(`state/apps/${Float.toString(id)}`),
      readJson(`state/deployments/${Float.toString(id)}`),
      readJson(`state/bindings/${Float.toString(id)}`),
    ]) {
    | [None, None, None] => id
    | _ => await past(id +. 1.)
    }
  let next = all => past(all->Array.reduce(0., (most, (id, _)) => Math.max(most, id)) +. 1.)
  let organizationAt = id => `state/organizations/${Float.toString(id)}`
  let bindingAt = id => `state/bindings/${Float.toString(id)}`
  let organizationOf = async binding =>
    (await readJson(bindingAt(binding)))->Option.flatMap(json => json->number("organization"))
  // A kept deployment's mounts given back, under the organization of the binding it names.
  let unmounted = async kept =>
    switch kept {
    | None => ()
    | Some(json) =>
      switch await json->number("binding")->Option.mapOr(Promise.resolve(None), organizationOf) {
      | None => ()
      | Some(organization) =>
        let ingress = field(json, "ingress")->Option.map(Ingress.ofJson)
        await Ingress.unmountObjects(objects, ~organization, ~ingress)
      }
    }
  // An organization's plain secret is written back, since no write but its opening changes it.
  // A binding's is not, since worker.res builds a state per request and another may write it.
  // A binding's plain secret is sealed at the binding's next write, `changed` below.
  let replaced = async (id, plain, seal) =>
    switch await record(organizationAt(id), id) {
    | Some(json) if json->text("secret") == Some(plain) =>
      let o = json->JSON.Decode.object->Option.getOr(dict{})->Dict.copy
      o->Dict.set("secret", JSON.String(seal))
      await writeJson(organizationAt(id), JSON.Object(o))
    | Some(_) | None => ()
    }
  let bindingFromJson = async (~id, json) =>
    switch (json->number("organization"), json->text("secret")) {
    | (Some(organization), Some(kept)) =>
      let secret = await opened(sealing, ~kind="binding", ~id, kept)
      Some(
        (
          {
            id,
            organization,
            secret,
            tunnel: json->text("tunnel"),
            address: json->text("address"),
            origin: json->text("origin"),
            relayed: json->field("relayed")->Option.flatMap(JSON.Decode.bool)->Option.getOr(false),
            // A record kept with an address before the order was is bound by its id, as 0006 does.
            bound: switch json->field("bound") {
            | Some(order) => order->JSON.Decode.float
            | None => json->text("address")->Option.map(_ => id)
            },
          }: binding
        ),
      )
    | _ => None
    }
  let binding = async id =>
    switch await record(bindingAt(id), id) {
    | Some(json) => await bindingFromJson(~id, json)
    | None => None
    }
  let bindings = async () =>
    (
      await Promise.all(
        (await every("state/bindings/"))->Array.map(((id, json)) => bindingFromJson(~id, json)),
      )
    )->Array.filterMap(b => b)
  let writeBinding = async (b: binding) =>
    await writeJson(
      bindingAt(b.id),
      bindingJson(b, await sealed(sealing, ~kind="binding", ~id=b.id, b.secret)),
    )
  let changed = (id, f) =>
    serial(async () =>
      switch await record(bindingAt(id), id) {
      | Some(json) =>
        // Written whole and sealed below, so a plain secret read here is sealed as it is written.
        switch await bindingFromJson(~id, json) {
        | Some(b) => await writeBinding(f(b))
        | None => ()
        }
      | None => ()
      }
    )
  let organization = id => record(organizationAt(id), id)
  {
    openOrganization: (label, ~secret) =>
      serial(async () => {
        await sealable(sealing, ~kind="organization", secret)
        let all = await every("state/organizations/")
        switch all->Array.find(((_, json)) => json->text("label") == Some(label)) {
        | Some((id, json)) =>
          switch json->text("secret") {
          | Some(kept) =>
            let secret = await opened(sealing, ~kind="organization", ~id, kept, ~writeBack=seal =>
              replaced(id, kept, seal)
            )
            ({id, secret}: organization)
          | None =>
            await writeJson(
              organizationAt(id),
              organizationJson(id, label, await sealed(sealing, ~kind="organization", ~id, secret)),
            )
            ({id, secret}: organization)
          }
        | None =>
          let id = await next(all)
          await writeJson(
            organizationAt(id),
            organizationJson(id, label, await sealed(sealing, ~kind="organization", ~id, secret)),
          )
          ({id, secret}: organization)
        }
      }),
    hasOrganization: async id => (await organization(id))->Option.isSome,
    organizationSecret: async id =>
      switch (await organization(id))->Option.flatMap(json => json->text("secret")) {
      | Some(kept) =>
        Some(
          await opened(sealing, ~kind="organization", ~id, kept, ~writeBack=seal =>
            serial(() => replaced(id, kept, seal))
          ),
        )
      | None => None
      },
    // Checked and written within the queue, as an app's id is drawn.
    openBinding: (~organization, ~secret, ~relayed, ~random) =>
      serial(async () => {
        await sealable(sealing, ~kind="binding", secret)
        await Ids.drawn(~random, ~kind="binding", async id => {
          let held = [
            bindingAt(id),
            `state/apps/${Float.toString(id)}`,
            organizationAt(id),
            `state/deployments/${Float.toString(id)}`,
          ]
          switch await Promise.all(held->Array.map(readJson)) {
          | found if found->Array.every(Option.isNone) =>
            await writeBinding({
              id,
              organization,
              secret,
              tunnel: None,
              address: None,
              origin: None,
              relayed,
              bound: None,
            })
            true
          | _ => false
          }
        })
      }),
    binding,
    storage: async organization =>
      (await bindings())
      ->Array.filterMap(b =>
        b.organization == organization && !b.relayed && b.origin == None
          ? b.bound->Option.map(order => (order, b))
          : None
      )
      ->Array.toSorted(((a, _), (b, _)) => a -. b)
      ->Array.get(0)
      ->Option.map(((_, b)) => b),
    addressedAt: async address => (await bindings())->Array.find(b => b.address == Some(address)),
    tunneled: (~binding, ~tunnel) => changed(binding, b => {...b, tunnel: Some(tunnel)}),
    // Taken within the queue, which orders one request's calls alone, as a state is built for each.
    // Two requests at once may each take one address, as D1's one statement never does.
    addressed: (~binding as id, ~address as given=?) =>
      serial(async () =>
        switch await binding(id) {
        | Some({address: Some(address)}) => Some(address)
        | Some(b) if b.origin == None =>
          let chosen = switch given {
          | Some(given) => Some(given)
          | None => Addresses.lowest((await bindings())->Array.filterMap(b => b.address))
          }
          switch chosen {
          | Some(address) =>
            await writeBinding({...b, address: Some(address)})
            Some(address)
          | None => None
          }
        | Some(_) | None => None
        }
      ),
    unaddressed: (~binding as id, ~address) =>
      serial(async () =>
        switch await binding(id) {
        | Some(b) if b.address == Some(address) && b.bound == None =>
          await writeBinding({...b, address: None})
        | Some(_) | None => ()
        }
      ),
    routed: (~binding as id) =>
      serial(async () =>
        switch await binding(id) {
        | Some({address: Some(_), bound: None, origin: None} as b) =>
          let order = (await bindings())->Array.filterMap(b => b.bound)->Array.reduce(0., Math.max)
          await writeBinding({...b, bound: Some(order +. 1.)})
        | Some(_) | None => ()
        }
      ),
    originated: (~binding as id, ~origin) =>
      serial(async () =>
        switch await binding(id) {
        | Some(b) if b.origin == None && b.bound == None =>
          await writeBinding({...b, origin: Some(origin)})
          true
        | Some(_) | None => false
        }
      ),
    domain: name => Ingress.domainOfObjects(objects, name),
    putRelease: async release => {
      let name = `state/releases/${release.hash}`
      if (await readJson(name))->Option.isNone {
        let o = dict{
          "hash": JSON.String(release.hash),
          "form": String(formName(release.form)),
          "size": Number(release.size),
        }
        release.ingress->Option.forEach(i => o->Dict.set("ingress", Ingress.toJson(i)))
        release.kinds->Option.forEach(kinds =>
          o->Dict.set("kinds", Array(kinds->Array.map(kind => JSON.String(kindName(kind)))))
        )
        await writeJson(name, JSON.Object(o))
      }
    },
    release: async hash =>
      (await readJson(`state/releases/${hash}`))->Option.flatMap(json => {
        let ingress = json->field("ingress")->Option.map(Ingress.ofJson)
        let kinds =
          json
          ->field("kinds")
          ->Option.map(kinds =>
            kinds
            ->JSON.Decode.array
            ->Option.flatMap(
              names => {
                let texts = names->Array.filterMap(JSON.Decode.string)
                texts->Array.length == names->Array.length ? kindsOf(texts) : None
              },
            )
          )
        switch (json->text("form")->Option.flatMap(formOf), json->number("size"), kinds) {
        | (Some(form), Some(size), None) =>
          Some(({hash, form, size, ?ingress, kinds: None}: release))
        | (Some(form), Some(size), Some(Some(kinds))) =>
          Some(({hash, form, size, ?ingress, kinds: Some(kinds)}: release))
        | _ => None
        }
      }),
    // Written within the queue only where the app is held, as D1 writes it.
    deploy: d =>
      serial(async () => {
        let at = `state/deployments/${Float.toString(d.app)}`
        switch await Promise.all([readJson(`state/apps/${Float.toString(d.app)}`), readJson(at)]) {
        | [None, None] => ()
        | [None, Some(json)]
          if json->text("kind") == None && json->number("capacity")->Option.getOr(0.) == 0. => ()
        | _ =>
          switch await Ingress.conflict(objects, ~app=d.app, ~ingress=d.ingress) {
          | Some(domain) => throw(DomainHeld(domain))
          | None => ()
          }
          let organization = await organizationOf(d.binding)
          switch organization {
          | None => ()
          | Some(organization) =>
            switch await Ingress.scopeConflict(
              objects,
              ~organization,
              ~app=d.app,
              ~ingress=d.ingress,
            ) {
            | Some(scope) => throw(Ingress.ScopeHeld(scope))
            | None => ()
            }
          }
          let kept = await readJson(at)
          let before = kept->Option.flatMap(j => field(j, "ingress"))->Option.map(Ingress.ofJson)
          await Ingress.replaceObjects(objects, ~app=d.app, ~before, ~after=d.ingress)
          await unmounted(kept)
          switch organization {
          | None => ()
          | Some(organization) =>
            await Ingress.mountObjects(objects, ~organization, ~app=d.app, ~ingress=d.ingress)
          }
          let o = dict{
            "app": JSON.Number(d.app),
            "binding": Number(d.binding),
            "release": String(d.release),
            "capacity": Number(d.capacity),
          }
          d.ingress->Option.forEach(i => o->Dict.set("ingress", Ingress.toJson(i)))
          d.kind->Option.forEach(kind => o->Dict.set("kind", String(kindName(kind))))
          await writeJson(at, JSON.Object(o))
        }
      }),
    deployment: async app =>
      (await readJson(`state/deployments/${Float.toString(app)}`))->Option.flatMap(json => {
        let ingress = json->field("ingress")->Option.map(Ingress.ofJson)
        switch (
          json->number("binding"),
          json->text("release"),
          json->number("capacity"),
          json->text("kind")->Option.map(kindOf),
        ) {
        | (Some(binding), Some(release), Some(capacity), None) =>
          Some(({app, binding, release, capacity, ?ingress, kind: None}: deployment))
        | (Some(binding), Some(release), Some(capacity), Some(Some(kind))) =>
          Some(({app, binding, release, capacity, ?ingress, kind: Some(kind)}: deployment))
        | _ => None
        }
      }),
    // Checked and written within the queue, as a binding's id is drawn.
    drawApp: (~random) =>
      serial(() =>
        Ids.drawn(~random, ~kind="app", async id => {
          let at = `state/apps/${Float.toString(id)}`
          let held = [
            at,
            organizationAt(id),
            bindingAt(id),
            `state/deployments/${Float.toString(id)}`,
          ]
          switch await Promise.all(held->Array.map(readJson)) {
          | found if found->Array.every(Option.isNone) =>
            await writeJson(at, JSON.Object(dict{"id": JSON.Number(id)}))
            true
          | _ => false
          }
        })
      ),
    // The deployment goes before the app, so an id is held until both are gone.
    forgetApp: app =>
      serial(async () => {
        let at = `state/apps/${Float.toString(app)}`
        let deploymentAt = `state/deployments/${Float.toString(app)}`
        switch await Promise.all([readJson(at), readJson(deploymentAt)]) {
        | [None, None] => false
        | [_, Some(json)]
          if json->text("kind") != None || json->number("capacity") != Some(0.) => false
        | _ =>
          let kept = await readJson(deploymentAt)
          let before = kept->Option.flatMap(j => field(j, "ingress"))->Option.map(Ingress.ofJson)
          await Ingress.replaceObjects(objects, ~app, ~before, ~after=None)
          await unmounted(kept)
          held(await objects.delete(deploymentAt))
          held(await objects.delete(at))
          // A control stood on that answers a delete as done while keeping the object is a fault.
          switch await Promise.all([readJson(at), readJson(deploymentAt)]) {
          | [None, None] => true
          | _ => JsError.throwWithMessage(`app ${Ids.text(app)} is still kept once deleted`)
          }
        }
      }),
    hasApp: async app => (await readJson(`state/apps/${Float.toString(app)}`))->Option.isSome,
    // Taken within the queue as a forget is, the record before the deployment.
    retireApp: app =>
      serial(async () => {
        let at = `state/apps/${Float.toString(app)}`
        let deploymentAt = `state/deployments/${Float.toString(app)}`
        let kept = await readJson(deploymentAt)
        let before = kept->Option.flatMap(j => field(j, "ingress"))->Option.map(Ingress.ofJson)
        await Ingress.replaceObjects(objects, ~app, ~before, ~after=None)
        await unmounted(kept)
        held(await objects.delete(at))
        held(await objects.delete(deploymentAt))
        switch await Promise.all([readJson(at), readJson(deploymentAt)]) {
        | [None, None] => ()
        | _ => JsError.throwWithMessage(`app ${Ids.text(app)} is still kept once deleted`)
        }
      }),
  }
}
