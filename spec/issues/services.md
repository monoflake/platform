# Issues: the services

What the services' own files leave open. The rules over an entry are the index's; see
[issues.md](issues.md).

## Where the telemetry view goes

The platform's own page has nowhere settled to show what telemetry gathers -- see
[../architecture/platform.md](../architecture/platform.md).

## A second place shares `checks` with the first

A check's row is keyed by its id alone, so a probe on the VPS declaring the same checks would
overwrite the node's; the key gains `place` when the second probe is written -- see
[../architecture/probe.md](../architecture/probe.md).

## A picture is served at its id, to whoever holds it, for as long as it is kept

What it lacks is a place that issues a temporary file -- an address signed for a while and then
refused -- which `pictures/<id>.png` would give way to. Until one exists the route stays as it is;
see [../architecture/shot.md](../architecture/shot.md).

## grok listens only once it is signed in

A signed-out grok2api waits for `grok2api login` and binds no port until it is signed in, which
suited a container somebody could sign in inside. Under host a deploy is judged by its health check,
so a first deploy of a signed-out app reads as failed, and the sign-in has to come first, by hand --
[../architecture/grok/deployment.md](../architecture/grok/deployment.md), "Under host the first
sign-in comes before the first deploy". Serving `/health` at once, and answering the API with a
503 until the agent is ready, would remove the step; it changes what the server promises a caller,
which is why it is not decided.

## A GitHub bot

Commits, pull requests and runs are answered by hand today: nothing of ours comments on a pull
request with what a deploy did, labels an issue, or answers a check. A bot -- a GitHub App the
platform runs, acting on webhooks the hook already receives -- could, once deploys go through the
platform. What it does first, whether it is a service of its own or part of the deployer, and
where its key is kept are undecided.

## An avatar has no placeholder a page can paint before it arrives

The console's sidebar shows the signed-in account's avatar, and until accounts exist it is the
author's, fetched from GitHub through the CDN's proxy -- web's `spec/architecture/console.md`. The
`<img>` is in the server's HTML; the picture is a second request, so for a moment there is an
empty circle, and the console paints a neutral one under it in the meantime. The resource layer
already answers this for every other picture: a record carries `image.thumbhash` and its decoded
copy, and a page rendered on the server inlines the placeholder for every rid it names --
[../architecture/resource.md](../architecture/resource.md), "A rid is resolved three times, and
each stage bakes only what it can know".

**What deciding it would cost.** Once accounts exist, an avatar a person uploads or links is a
resource like any picture: its bytes in the platform's store, its record holding the thumbhash
taken at import, so every consumer -- the console, a comment, a page that names the author --
renders it on the server with its placeholder already painted. What is open is whether an account
holds a rid or an avatar of its own kind, and whether an avatar linked from elsewhere, GitHub's
today, is imported once or followed and re-imported when it changes.
