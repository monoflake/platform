# Deploy

The operator and machine paths take the existing deployment arguments.

When `CONTROL_PRODUCTION_DEPLOY` is present, the tool uses only that deployment grant. Set it
through the calling environment, then invoke the compiled tool with the app directory, control
target, expected deployment version, and four full lowercase candidate commit SHAs:

```text
node code/tools/deploy/src/main.res.mjs <directory> control:<address> \
  --expected-version <version> \
  --platform <sha> --cloud <sha> --driver <sha> --machine <sha>
```

This mode rejects app, binding, secret, network, ingress, forget, and retire options. It bundles
locally with the app's installed Wrangler, uploads the Modules archive, deploys with the expected
version, and polls scoped status. Success requires the next version, artifact digest, and all four
candidate commits to match. The control retains its existing runtime secrets.

`--dry-run` builds the archive without calling the control. An empty grant variable fails instead
of falling back to the operator path. Grant responses and transport errors are masked, and the
grant and operator credentials are excluded from the local builder's environment.

The tests replace fetch and the local builder. They mint no credential and open no connection.

## Slots

A build's `metadata.json` may declare `slots` and `functions` beside `kinds` and `ingress`, RFC
rt6gi. On a machine target a declared `database` slot is filled with the binding's one `database`
item, 268435456 bytes added to the list beside the container where none is held, and the deploy
carries `bindings` naming that item under the slot's name. A slot of another type is refused, and
a control target fills none yet.
