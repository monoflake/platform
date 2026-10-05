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
